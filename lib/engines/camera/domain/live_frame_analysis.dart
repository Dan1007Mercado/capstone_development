import 'dart:collection';

import '../../aruco/domain/image_geometry.dart';

final class DocumentGeometry {
  DocumentGeometry({
    required Iterable<ImagePoint> corners,
    required this.areaRatio,
    required this.centroid,
    required this.perspectiveRatio,
  }) : corners = UnmodifiableListView(List.of(corners)) {
    if (this.corners.length != 4) {
      throw ArgumentError.value(corners, 'corners', 'Four corners required.');
    }
  }

  /// Canonical order: top-left, top-right, bottom-right, bottom-left.
  final List<ImagePoint> corners;
  final double areaRatio;
  final ImagePoint centroid;
  final double perspectiveRatio;
}

final class DetectedDocument {
  const DetectedDocument({required this.geometry, required this.confidence});

  final DocumentGeometry geometry;
  final double confidence;
}

enum DocumentTrackingPhase { searching, acquired, tracking, temporarilyLost }

final class DocumentTrackingUpdate {
  const DocumentTrackingUpdate({
    required this.phase,
    required this.document,
    required this.isFresh,
    required this.temporaryMissCount,
    required this.stability,
  });

  const DocumentTrackingUpdate.searching()
    : phase = DocumentTrackingPhase.searching,
      document = null,
      isFresh = false,
      temporaryMissCount = 0,
      stability = DocumentStability.unavailable;

  final DocumentTrackingPhase phase;
  final DetectedDocument? document;
  final bool isFresh;
  final int temporaryMissCount;
  final DocumentStability stability;
}

final class DocumentQuality {
  const DocumentQuality({required this.brightness, required this.sharpness});

  final double brightness;
  final double sharpness;
}

enum LiveFrameGateReason {
  disabled,
  noDocument,
  tooSmall,
  tooSkewed,
  tooDark,
  tooBright,
  tooBlurry,
  pass,
}

final class DocumentStability {
  const DocumentStability({
    required this.isStable,
    required this.stableFrameCount,
    required this.motion,
  });

  static const unavailable = DocumentStability(
    isStable: false,
    stableFrameCount: 0,
    motion: double.infinity,
  );

  final bool isStable;
  final int stableFrameCount;
  final double motion;
}

final class LiveFrameGateResult {
  const LiveFrameGateResult({
    required this.reason,
    required this.shouldRunAruco,
    required this.fallbackProbe,
  });

  final LiveFrameGateReason reason;
  final bool shouldRunAruco;
  final bool fallbackProbe;

  bool get passed =>
      reason == LiveFrameGateReason.pass ||
      reason == LiveFrameGateReason.disabled;
}
