import 'dart:math' as math;

import '../../aruco/domain/image_geometry.dart';
import '../domain/live_frame_analysis.dart';

/// Retains and smooths document geometry for preview continuity only.
///
/// [isFresh] remains the boundary for capture gating: retained geometry from a
/// temporary miss is never authoritative.
final class DocumentTracker {
  DocumentTracker({
    required this.maximumMotion,
    required this.minimumStableFrames,
  });

  static const _maximumTemporaryMisses = 3;
  static const _smoothing = 0.65;
  static const _maximumCentroidDistance = 0.3;
  static const _maximumAreaDifference = 0.55;

  final double maximumMotion;
  final int minimumStableFrames;

  DetectedDocument? _tracked;
  int _stableFrames = 0;
  int _misses = 0;

  DocumentTrackingUpdate update(
    DetectedDocument? candidate, {
    required ImageSize frameSize,
  }) {
    final previous = _tracked;
    if (candidate == null ||
        (previous != null && !_matches(previous, candidate, frameSize))) {
      return _miss();
    }

    _misses = 0;
    if (previous == null) {
      _tracked = candidate;
      _stableFrames = 1;
      return DocumentTrackingUpdate(
        phase: DocumentTrackingPhase.acquired,
        document: candidate,
        isFresh: true,
        temporaryMissCount: 0,
        stability: DocumentStability(
          isStable: minimumStableFrames <= 1,
          stableFrameCount: 1,
          motion: 0,
        ),
      );
    }

    final motion = _motion(previous.geometry, candidate.geometry, frameSize);
    _stableFrames = motion <= maximumMotion ? _stableFrames + 1 : 1;
    _tracked = _smooth(previous, candidate);
    return DocumentTrackingUpdate(
      phase: DocumentTrackingPhase.tracking,
      document: _tracked,
      isFresh: true,
      temporaryMissCount: 0,
      stability: DocumentStability(
        isStable: _stableFrames >= minimumStableFrames,
        stableFrameCount: _stableFrames,
        motion: motion,
      ),
    );
  }

  DocumentTrackingUpdate _miss() {
    final tracked = _tracked;
    if (tracked == null) return const DocumentTrackingUpdate.searching();
    _misses++;
    _stableFrames = 0;
    if (_misses > _maximumTemporaryMisses) {
      reset();
      return const DocumentTrackingUpdate.searching();
    }
    return DocumentTrackingUpdate(
      phase: DocumentTrackingPhase.temporarilyLost,
      document: tracked,
      isFresh: false,
      temporaryMissCount: _misses,
      stability: DocumentStability.unavailable,
    );
  }

  bool _matches(
    DetectedDocument previous,
    DetectedDocument candidate,
    ImageSize frameSize,
  ) {
    final diagonal = math.sqrt(
      frameSize.width * frameSize.width + frameSize.height * frameSize.height,
    );
    final centroidDistance =
        previous.geometry.centroid.distanceTo(candidate.geometry.centroid) /
        diagonal;
    final areaDifference =
        (previous.geometry.areaRatio - candidate.geometry.areaRatio).abs();
    return centroidDistance <= _maximumCentroidDistance &&
        areaDifference <= _maximumAreaDifference;
  }

  double _motion(
    DocumentGeometry previous,
    DocumentGeometry current,
    ImageSize frameSize,
  ) {
    final diagonal = math.sqrt(
      frameSize.width * frameSize.width + frameSize.height * frameSize.height,
    );
    var cornerMotion = 0.0;
    for (var index = 0; index < 4; index++) {
      cornerMotion = math.max(
        cornerMotion,
        previous.corners[index].distanceTo(current.corners[index]) / diagonal,
      );
    }
    final centroidMotion =
        previous.centroid.distanceTo(current.centroid) / diagonal;
    final areaMotion = (previous.areaRatio - current.areaRatio).abs();
    return math.max(math.max(cornerMotion, centroidMotion), areaMotion);
  }

  DetectedDocument _smooth(
    DetectedDocument previous,
    DetectedDocument current,
  ) {
    ImagePoint blend(ImagePoint oldPoint, ImagePoint newPoint) => ImagePoint(
      oldPoint.x + (newPoint.x - oldPoint.x) * _smoothing,
      oldPoint.y + (newPoint.y - oldPoint.y) * _smoothing,
    );

    return DetectedDocument(
      geometry: DocumentGeometry(
        corners: [
          for (var index = 0; index < 4; index++)
            blend(
              previous.geometry.corners[index],
              current.geometry.corners[index],
            ),
        ],
        areaRatio:
            previous.geometry.areaRatio +
            (current.geometry.areaRatio - previous.geometry.areaRatio) *
                _smoothing,
        centroid: blend(previous.geometry.centroid, current.geometry.centroid),
        perspectiveRatio:
            previous.geometry.perspectiveRatio +
            (current.geometry.perspectiveRatio -
                    previous.geometry.perspectiveRatio) *
                _smoothing,
      ),
      confidence:
          previous.confidence +
          (current.confidence - previous.confidence) * _smoothing,
    );
  }

  void reset() {
    _tracked = null;
    _stableFrames = 0;
    _misses = 0;
  }
}
