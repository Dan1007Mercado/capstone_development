import '../../aruco/domain/image_geometry.dart';
import '../domain/live_frame_analysis.dart';

/// Retains and smooths document geometry for preview continuity only.
///
/// This tracker is visual-only. Its output must never affect marker readiness,
/// capture authorization, homography, or OMR alignment.
final class DocumentTracker {
  DocumentTracker();

  static const _maximumTemporaryMisses = 3;
  static const _smoothing = 0.65;

  DetectedDocument? _tracked;
  int _misses = 0;

  DocumentTrackingUpdate update(DetectedDocument? candidate) {
    final previous = _tracked;
    if (candidate == null) {
      return _miss();
    }

    _misses = 0;
    if (previous == null) {
      _tracked = candidate;
      return DocumentTrackingUpdate(
        phase: DocumentTrackingPhase.acquired,
        document: candidate,
        isFresh: true,
        temporaryMissCount: 0,
      );
    }

    _tracked = _smooth(previous, candidate);
    return DocumentTrackingUpdate(
      phase: DocumentTrackingPhase.tracking,
      document: _tracked,
      isFresh: true,
      temporaryMissCount: 0,
    );
  }

  /// Keeps the last visual polygon between deliberately throttled detections.
  DocumentTrackingUpdate retain() {
    final tracked = _tracked;
    if (tracked == null) return const DocumentTrackingUpdate.searching();
    return DocumentTrackingUpdate(
      phase: DocumentTrackingPhase.tracking,
      document: tracked,
      isFresh: false,
      temporaryMissCount: _misses,
    );
  }

  DocumentTrackingUpdate _miss() {
    final tracked = _tracked;
    if (tracked == null) return const DocumentTrackingUpdate.searching();
    _misses++;
    if (_misses > _maximumTemporaryMisses) {
      reset();
      return const DocumentTrackingUpdate.searching();
    }
    return DocumentTrackingUpdate(
      phase: DocumentTrackingPhase.temporarilyLost,
      document: tracked,
      isFresh: false,
      temporaryMissCount: _misses,
    );
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
    _misses = 0;
  }
}
