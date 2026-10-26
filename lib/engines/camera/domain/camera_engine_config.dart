import '../../layout/domain/layout_config.dart';
import '../../aruco/domain/page_marker_signature_resolver.dart';

enum CameraLensPreference { rear, front }

enum CameraResolutionPreference { medium, high, veryHigh, ultraHigh, maximum }

enum AnalysisFrameDropPolicy { dropWhileBusy }

final class CameraEngineConfig {
  static const int minimumAnalysisMaxDimension = 480;
  static const int defaultAnalysisMaxDimension = 800;
  static const int maximumAnalysisMaxDimension = 1920;

  factory CameraEngineConfig({
    CameraLensPreference preferredLens = CameraLensPreference.rear,
    CameraResolutionPreference preferredResolution =
        CameraResolutionPreference.veryHigh,
    int? preferredPreviewFps = 60,
    double targetAnalysisFps = 10,
    int analysisMaxDimension = defaultAnalysisMaxDimension,
    bool paperEdgeVisualizationEnabled = false,
    int paperEdgeMaxDimension = 640,
    int paperEdgeDetectionIntervalFrames = 3,
    double paperEdgeCannyLowThreshold = 40,
    double paperEdgeCannyHighThreshold = 120,
    double paperEdgePolygonEpsilonRatio = 0.02,
    int minimumStableFrames = 3,
    int stabilityWindowSize = 5,
    double maximumMotionThreshold = 0.015,
    bool requireAllMarkers = true,
    MarkerIds markerIds = MarkerIds.defaults,
    List<PageMarkerSignature> pageMarkerSignatures = const [],
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
    if (analysisMaxDimension < minimumAnalysisMaxDimension ||
        analysisMaxDimension > maximumAnalysisMaxDimension) {
      throw ArgumentError.value(analysisMaxDimension, 'analysisMaxDimension');
    }
    if (paperEdgeMaxDimension < minimumAnalysisMaxDimension ||
        paperEdgeMaxDimension > maximumAnalysisMaxDimension) {
      throw ArgumentError.value(paperEdgeMaxDimension, 'paperEdgeMaxDimension');
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
    if (pageMarkerSignatures.isNotEmpty) {
      PageMarkerSignatureResolver(pageMarkerSignatures);
    }
    if (captureCooldown.isNegative) {
      throw ArgumentError.value(captureCooldown, 'captureCooldown');
    }
    if (paperEdgeDetectionIntervalFrames <= 0 ||
        !paperEdgeCannyLowThreshold.isFinite ||
        !paperEdgeCannyHighThreshold.isFinite ||
        paperEdgeCannyLowThreshold <= 0 ||
        paperEdgeCannyLowThreshold >= paperEdgeCannyHighThreshold ||
        !paperEdgePolygonEpsilonRatio.isFinite ||
        paperEdgePolygonEpsilonRatio <= 0 ||
        paperEdgePolygonEpsilonRatio >= 0.2) {
      throw ArgumentError('Paper-edge visualization configuration is invalid.');
    }
    final effectivePaperEdgeDimension =
        paperEdgeMaxDimension > analysisMaxDimension
        ? analysisMaxDimension
        : paperEdgeMaxDimension;
    return CameraEngineConfig._(
      preferredLens: preferredLens,
      preferredResolution: preferredResolution,
      preferredPreviewFps: preferredPreviewFps,
      targetAnalysisFps: targetAnalysisFps,
      analysisMaxDimension: analysisMaxDimension,
      paperEdgeVisualizationEnabled: paperEdgeVisualizationEnabled,
      paperEdgeMaxDimension: effectivePaperEdgeDimension,
      paperEdgeDetectionIntervalFrames: paperEdgeDetectionIntervalFrames,
      paperEdgeCannyLowThreshold: paperEdgeCannyLowThreshold,
      paperEdgeCannyHighThreshold: paperEdgeCannyHighThreshold,
      paperEdgePolygonEpsilonRatio: paperEdgePolygonEpsilonRatio,
      minimumStableFrames: minimumStableFrames,
      stabilityWindowSize: stabilityWindowSize,
      maximumMotionThreshold: maximumMotionThreshold,
      requireAllMarkers: requireAllMarkers,
      markerIds: markerIds,
      pageMarkerSignatures: List.unmodifiable(pageMarkerSignatures),
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
    required this.analysisMaxDimension,
    required this.paperEdgeVisualizationEnabled,
    required this.paperEdgeMaxDimension,
    required this.paperEdgeDetectionIntervalFrames,
    required this.paperEdgeCannyLowThreshold,
    required this.paperEdgeCannyHighThreshold,
    required this.paperEdgePolygonEpsilonRatio,
    required this.minimumStableFrames,
    required this.stabilityWindowSize,
    required this.maximumMotionThreshold,
    required this.requireAllMarkers,
    required this.markerIds,
    required this.pageMarkerSignatures,
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
  final int analysisMaxDimension;
  final bool paperEdgeVisualizationEnabled;
  final int paperEdgeMaxDimension;
  final int paperEdgeDetectionIntervalFrames;
  final double paperEdgeCannyLowThreshold;
  final double paperEdgeCannyHighThreshold;
  final double paperEdgePolygonEpsilonRatio;
  final int minimumStableFrames;
  final int stabilityWindowSize;
  final double maximumMotionThreshold;
  final bool requireAllMarkers;
  final MarkerIds markerIds;
  final List<PageMarkerSignature> pageMarkerSignatures;
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
