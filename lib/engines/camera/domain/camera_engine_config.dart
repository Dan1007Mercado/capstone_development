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
    int? arucoAnalysisMaxDimension,
    bool documentGateEnabled = true,
    int documentGateMaxDimension = 640,
    double minimumDocumentAreaRatio = 0.12,
    double maximumDocumentPerspectiveRatio = 6,
    double documentStabilityThreshold = 0.02,
    int arucoProbeEveryNFrames = 5,
    Duration arucoConfirmationMaxAge = const Duration(milliseconds: 450),
    double documentCannyLowThreshold = 40,
    double documentCannyHighThreshold = 120,
    double documentPolygonEpsilonRatio = 0.02,
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
    final effectiveArucoDimension =
        arucoAnalysisMaxDimension ?? analysisMaxDimension;
    if (effectiveArucoDimension < minimumAnalysisMaxDimension ||
        effectiveArucoDimension > maximumAnalysisMaxDimension) {
      throw ArgumentError.value(
        effectiveArucoDimension,
        'arucoAnalysisMaxDimension',
      );
    }
    if (documentGateMaxDimension < minimumAnalysisMaxDimension ||
        documentGateMaxDimension > effectiveArucoDimension) {
      throw ArgumentError.value(
        documentGateMaxDimension,
        'documentGateMaxDimension',
      );
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
    if (!minimumDocumentAreaRatio.isFinite ||
        minimumDocumentAreaRatio <= 0 ||
        minimumDocumentAreaRatio >= 1 ||
        !maximumDocumentPerspectiveRatio.isFinite ||
        maximumDocumentPerspectiveRatio < 1 ||
        !documentStabilityThreshold.isFinite ||
        documentStabilityThreshold <= 0 ||
        arucoProbeEveryNFrames <= 0 ||
        arucoConfirmationMaxAge <= Duration.zero ||
        !documentCannyLowThreshold.isFinite ||
        !documentCannyHighThreshold.isFinite ||
        documentCannyLowThreshold <= 0 ||
        documentCannyLowThreshold >= documentCannyHighThreshold ||
        !documentPolygonEpsilonRatio.isFinite ||
        documentPolygonEpsilonRatio <= 0 ||
        documentPolygonEpsilonRatio >= 0.2) {
      throw ArgumentError('Document gate configuration is invalid.');
    }
    return CameraEngineConfig._(
      preferredLens: preferredLens,
      preferredResolution: preferredResolution,
      preferredPreviewFps: preferredPreviewFps,
      targetAnalysisFps: targetAnalysisFps,
      analysisMaxDimension: effectiveArucoDimension,
      documentGateEnabled: documentGateEnabled,
      documentGateMaxDimension: documentGateMaxDimension,
      minimumDocumentAreaRatio: minimumDocumentAreaRatio,
      maximumDocumentPerspectiveRatio: maximumDocumentPerspectiveRatio,
      documentStabilityThreshold: documentStabilityThreshold,
      arucoProbeEveryNFrames: arucoProbeEveryNFrames,
      arucoConfirmationMaxAge: arucoConfirmationMaxAge,
      documentCannyLowThreshold: documentCannyLowThreshold,
      documentCannyHighThreshold: documentCannyHighThreshold,
      documentPolygonEpsilonRatio: documentPolygonEpsilonRatio,
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
    required this.documentGateEnabled,
    required this.documentGateMaxDimension,
    required this.minimumDocumentAreaRatio,
    required this.maximumDocumentPerspectiveRatio,
    required this.documentStabilityThreshold,
    required this.arucoProbeEveryNFrames,
    required this.arucoConfirmationMaxAge,
    required this.documentCannyLowThreshold,
    required this.documentCannyHighThreshold,
    required this.documentPolygonEpsilonRatio,
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
  final bool documentGateEnabled;
  final int documentGateMaxDimension;
  final double minimumDocumentAreaRatio;
  final double maximumDocumentPerspectiveRatio;
  final double documentStabilityThreshold;
  final int arucoProbeEveryNFrames;
  final Duration arucoConfirmationMaxAge;
  final double documentCannyLowThreshold;
  final double documentCannyHighThreshold;
  final double documentPolygonEpsilonRatio;

  int get arucoAnalysisMaxDimension => analysisMaxDimension;
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
