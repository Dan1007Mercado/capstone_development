import 'dart:math' as math;

import '../domain/live_frame_analysis.dart';

final class FrameStabilityTracker {
  FrameStabilityTracker({
    required this.maximumMotion,
    required this.minimumStableFrames,
  }) {
    if (!maximumMotion.isFinite || maximumMotion <= 0) {
      throw ArgumentError.value(maximumMotion, 'maximumMotion');
    }
    if (minimumStableFrames <= 0) {
      throw ArgumentError.value(minimumStableFrames, 'minimumStableFrames');
    }
  }

  final double maximumMotion;
  final int minimumStableFrames;
  DocumentGeometry? _previous;
  int _stableFrames = 0;

  DocumentStability update(DetectedDocument? document) {
    if (document == null) {
      reset();
      return DocumentStability.unavailable;
    }
    final current = document.geometry;
    final previous = _previous;
    if (previous == null) {
      _previous = current;
      _stableFrames = 1;
      return DocumentStability(
        isStable: minimumStableFrames <= 1,
        stableFrameCount: _stableFrames,
        motion: 0,
      );
    }

    var cornerMotion = 0.0;
    for (var index = 0; index < 4; index++) {
      cornerMotion = math.max(
        cornerMotion,
        previous.corners[index].distanceTo(current.corners[index]),
      );
    }
    final centroidMotion = previous.centroid.distanceTo(current.centroid);
    final areaMotion = (previous.areaRatio - current.areaRatio).abs();
    final motion = math.max(math.max(cornerMotion, centroidMotion), areaMotion);
    if (motion <= maximumMotion) {
      _stableFrames++;
    } else {
      _stableFrames = 1;
    }
    _previous = current;
    return DocumentStability(
      isStable: _stableFrames >= minimumStableFrames,
      stableFrameCount: _stableFrames,
      motion: motion,
    );
  }

  void reset() {
    _previous = null;
    _stableFrames = 0;
  }
}
