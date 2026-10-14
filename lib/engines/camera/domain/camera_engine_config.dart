import '../../layout/domain/layout_config.dart';

enum CameraLensPreference { rear, front }

enum CameraResolutionPreference { medium, high, veryHigh, ultraHigh, maximum }

enum AnalysisFrameDropPolicy { dropWhileBusy }

final class CameraEngineConfig {
  factory CameraEngineConfig({
    CameraLensPreference preferredLens = CameraLensPreference.rear,
    CameraResolutionPreference preferredResolution =
        CameraResolutionPreference.veryHigh,
    int? preferredPreviewFps = 60,
    double targetAnalysisFps = 10,
    int minimumStableFrames = 3,
    int stabilityWindowSize = 5,
    double maximumMotionThreshold = 0.015,
    bool requireAllMarkers = true,
    MarkerIds markerIds = MarkerIds.defaults,
    double minimumPageAreaRatio = 0.12,
    double maximumPerspectiveRatio = 6,
    double minimumMarkerSidePixels = 12,
    double minimumBrightness = 45,
    double maximumBrightness = 220,
    double minimumSharpness = 80,
    bool autoCaptureEnabled = true,
    Duration captureCooldown = const Duration(seconds: 2),
    AnalysisFrameDropPolicy frameDropPolicy =
        AnalysisFrameDropPolicy.dropWhileBusy,
  }) {
    if (preferredPreviewFps != null &&
        (preferredPreviewFps <= 0 || preferredPreviewFps > 120)) {
      throw ArgumentError.value(preferredPreviewFps, 'preferredPreviewFps');
    }
    if (!targetAnalysisFps.isFinite ||
        targetAnalysisFps <= 0 ||
        targetAnalysisFps > 60) {
      throw ArgumentError.value(targetAnalysisFps, 'targetAnalysisFps');
    }
    if (minimumStableFrames <= 0 || stabilityWindowSize < minimumStableFrames) {
      throw ArgumentError(
        'The stability window must contain the required stable frames.',
      );
    }
    final positive = [
      maximumMotionThreshold,
      minimumPageAreaRatio,
      maximumPerspectiveRatio,
      minimumMarkerSidePixels,
      minimumSharpness,
    ];
    if (positive.any((value) => !value.isFinite || value <= 0) ||
        minimumPageAreaRatio >= 1 ||
        maximumPerspectiveRatio < 1) {
      throw ArgumentError('Camera quality thresholds are invalid.');
    }
    if (!minimumBrightness.isFinite ||
        !maximumBrightness.isFinite ||
        minimumBrightness < 0 ||
        maximumBrightness > 255 ||
        minimumBrightness >= maximumBrightness) {
      throw ArgumentError(
        'Brightness thresholds must be ordered within 0–255.',
      );
    }
    if (!markerIds.areUnique || markerIds.values.any((id) => id < 0)) {
      throw ArgumentError('Camera marker IDs must be unique and non-negative.');
    }
    if (captureCooldown.isNegative) {
      throw ArgumentError.value(captureCooldown, 'captureCooldown');
    }
    return CameraEngineConfig._(
      preferredLens: preferredLens,
      preferredResolution: preferredResolution,
      preferredPreviewFps: preferredPreviewFps,
      targetAnalysisFps: targetAnalysisFps,
      minimumStableFrames: minimumStableFrames,
      stabilityWindowSize: stabilityWindowSize,
      maximumMotionThreshold: maximumMotionThreshold,
      requireAllMarkers: requireAllMarkers,
      markerIds: markerIds,
      minimumPageAreaRatio: minimumPageAreaRatio,
      maximumPerspectiveRatio: maximumPerspectiveRatio,
      minimumMarkerSidePixels: minimumMarkerSidePixels,
      minimumBrightness: minimumBrightness,
      maximumBrightness: maximumBrightness,
      minimumSharpness: minimumSharpness,
      autoCaptureEnabled: autoCaptureEnabled,
      captureCooldown: captureCooldown,
      frameDropPolicy: frameDropPolicy,
    );
  }

  const CameraEngineConfig._({
    required this.preferredLens,
    required this.preferredResolution,
    required this.preferredPreviewFps,
    required this.targetAnalysisFps,
    required this.minimumStableFrames,
    required this.stabilityWindowSize,
    required this.maximumMotionThreshold,
    required this.requireAllMarkers,
    required this.markerIds,
    required this.minimumPageAreaRatio,
    required this.maximumPerspectiveRatio,
    required this.minimumMarkerSidePixels,
    required this.minimumBrightness,
    required this.maximumBrightness,
    required this.minimumSharpness,
    required this.autoCaptureEnabled,
    required this.captureCooldown,
    required this.frameDropPolicy,
  });

  final CameraLensPreference preferredLens;
  final CameraResolutionPreference preferredResolution;
  final int? preferredPreviewFps;
  final double targetAnalysisFps;
  final int minimumStableFrames;
  final int stabilityWindowSize;
  final double maximumMotionThreshold;
  final bool requireAllMarkers;
  final MarkerIds markerIds;
  final double minimumPageAreaRatio;
  final double maximumPerspectiveRatio;
  final double minimumMarkerSidePixels;
  final double minimumBrightness;
  final double maximumBrightness;
  final double minimumSharpness;
  final bool autoCaptureEnabled;
  final Duration captureCooldown;
  final AnalysisFrameDropPolicy frameDropPolicy;

  Duration get analysisInterval => Duration(
    microseconds: (Duration.microsecondsPerSecond / targetAnalysisFps).round(),
  );
}
