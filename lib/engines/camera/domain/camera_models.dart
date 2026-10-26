import 'dart:collection';
import 'dart:typed_data';

import '../../../core/errors/engine_error.dart';
import '../../../core/ids/identifiers.dart';
import '../../aruco/domain/image_geometry.dart';
import 'camera_engine_config.dart';
import 'live_frame_analysis.dart';

enum CameraLifecycleState {
  uninitialized,
  initializing,
  ready,
  analyzing,
  capturing,
  error,
  disposed,
}

enum CameraDeviceOrientation {
  portraitUp,
  portraitDown,
  landscapeLeft,
  landscapeRight,
  unknown,
}

enum CaptureReadinessStatus {
  notReady,
  searching,
  markersMissing,
  verifyingMarkers,
  unknownSheet,
  tooSmall,
  tooSkewed,
  tooBlurry,
  tooDark,
  tooBright,
  unstable,
  ready,
}

final class CameraPreviewInfo {
  const CameraPreviewInfo({
    required this.width,
    required this.height,
    required this.sensorOrientationDegrees,
    required this.lens,
    required this.automaticFocusEnabled,
    required this.automaticExposureEnabled,
    required this.requestedPreviewFps,
  });

  final int width;
  final int height;
  final int sensorOrientationDegrees;
  final CameraLensPreference lens;
  final bool automaticFocusEnabled;
  final bool automaticExposureEnabled;
  final int? requestedPreviewFps;

  double get aspectRatio => width / height;
}

final class CameraAnalysisFrame {
  CameraAnalysisFrame({
    required Uint8List lumaBytes,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.bytesPerPixel,
    required this.timestamp,
    required this.sensorOrientationDegrees,
    required this.deviceOrientation,
  }) : lumaBytes = Uint8List.fromList(lumaBytes) {
    if (width <= 0 || height <= 0 || bytesPerRow <= 0 || bytesPerPixel <= 0) {
      throw ArgumentError(
        'Camera frame dimensions and strides must be positive.',
      );
    }
    final requiredLength =
        (height - 1) * bytesPerRow + (width - 1) * bytesPerPixel + 1;
    if (this.lumaBytes.length < requiredLength) {
      throw ArgumentError(
        'Camera frame luma buffer is shorter than its strides.',
      );
    }
  }

  final Uint8List lumaBytes;
  final int width;
  final int height;
  final int bytesPerRow;
  final int bytesPerPixel;
  final DateTime timestamp;
  final int sensorOrientationDegrees;
  final CameraDeviceOrientation deviceOrientation;
}

final class CameraAnalysisTimings {
  const CameraAnalysisTimings({
    this.materializationDuration = Duration.zero,
    this.isolateOverheadDuration = Duration.zero,
    this.preparationDuration = Duration.zero,
    this.paperEdgeDetectionDuration = Duration.zero,
    this.paperEdgeTrackingDuration = Duration.zero,
    this.sharpnessDuration = Duration.zero,
    this.arucoDetectionDuration = Duration.zero,
    this.geometryDuration = Duration.zero,
    this.workerDuration = Duration.zero,
    this.totalDuration = Duration.zero,
  });

  static const zero = CameraAnalysisTimings();

  final Duration materializationDuration;
  final Duration isolateOverheadDuration;
  final Duration preparationDuration;
  final Duration paperEdgeDetectionDuration;
  final Duration paperEdgeTrackingDuration;
  final Duration sharpnessDuration;
  final Duration arucoDetectionDuration;
  final Duration geometryDuration;
  final Duration workerDuration;
  final Duration totalDuration;

  Duration get measuredWorkerStages =>
      preparationDuration +
      paperEdgeDetectionDuration +
      paperEdgeTrackingDuration +
      sharpnessDuration +
      arucoDetectionDuration +
      geometryDuration;

  bool get isInternallyConsistent {
    final durations = [
      materializationDuration,
      isolateOverheadDuration,
      preparationDuration,
      paperEdgeDetectionDuration,
      paperEdgeTrackingDuration,
      sharpnessDuration,
      arucoDetectionDuration,
      geometryDuration,
      workerDuration,
      totalDuration,
    ];
    return durations.every((duration) => !duration.isNegative) &&
        workerDuration >= measuredWorkerStages &&
        totalDuration >=
            materializationDuration + isolateOverheadDuration + workerDuration;
  }

  CameraAnalysisTimings withEngineDurations({
    required Duration materializationDuration,
    required Duration totalDuration,
  }) => CameraAnalysisTimings(
    materializationDuration: materializationDuration,
    isolateOverheadDuration: isolateOverheadDuration,
    preparationDuration: preparationDuration,
    paperEdgeDetectionDuration: paperEdgeDetectionDuration,
    paperEdgeTrackingDuration: paperEdgeTrackingDuration,
    sharpnessDuration: sharpnessDuration,
    arucoDetectionDuration: arucoDetectionDuration,
    geometryDuration: geometryDuration,
    workerDuration: workerDuration,
    totalDuration: totalDuration,
  );
}

final class CameraFrameObservation {
  CameraFrameObservation({
    required Iterable<int> detectedMarkerIds,
    required Iterable<ImagePoint> registrationPoints,
    required this.pageAreaRatio,
    required this.perspectiveRatio,
    required this.minimumMarkerSidePixels,
    required this.brightness,
    required this.sharpness,
    required this.frameSize,
    ImageSize? analysisFrameSize,
    this.analysisScaleX = 1,
    this.analysisScaleY = 1,
    this.timings = CameraAnalysisTimings.zero,
    this.sensorOrientationDegrees = 0,
    this.deviceOrientation = CameraDeviceOrientation.unknown,
    this.resolvedPageId,
    this.pageResolutionErrorCode,
    this.document,
    this.documentFresh = false,
    this.documentTrackingPhase = DocumentTrackingPhase.searching,
    this.documentTemporaryMissCount = 0,
    this.documentDetectionFailed = false,
    this.documentDetectionError,
  }) : analysisFrameSize = analysisFrameSize ?? frameSize,
       detectedMarkerIds = UnmodifiableListView(List.of(detectedMarkerIds)),
       registrationPoints = UnmodifiableListView(List.of(registrationPoints));

  final List<int> detectedMarkerIds;
  final List<ImagePoint> registrationPoints;
  final double? pageAreaRatio;
  final double? perspectiveRatio;
  final double? minimumMarkerSidePixels;
  final double brightness;
  final double sharpness;
  final ImageSize frameSize;
  final ImageSize analysisFrameSize;
  final double analysisScaleX;
  final double analysisScaleY;
  final CameraAnalysisTimings timings;
  final int sensorOrientationDegrees;
  final CameraDeviceOrientation deviceOrientation;
  final PageId? resolvedPageId;
  final String? pageResolutionErrorCode;
  final DetectedDocument? document;
  final bool documentFresh;
  final DocumentTrackingPhase documentTrackingPhase;
  final int documentTemporaryMissCount;
  final bool documentDetectionFailed;
  final String? documentDetectionError;
}

final class FrameQuality {
  const FrameQuality({
    required this.brightness,
    required this.sharpness,
    required this.pageAreaRatio,
    required this.perspectiveRatio,
  });

  final double brightness;
  final double sharpness;
  final double? pageAreaRatio;
  final double? perspectiveRatio;
}

final class MarkerTrackingState {
  MarkerTrackingState({
    required Iterable<int> detectedMarkerIds,
    required Iterable<ImagePoint> registrationPoints,
    this.resolvedPageId,
    this.pageResolutionErrorCode,
  }) : detectedMarkerIds = UnmodifiableListView(List.of(detectedMarkerIds)),
       registrationPoints = UnmodifiableListView(List.of(registrationPoints));

  final List<int> detectedMarkerIds;
  final List<ImagePoint> registrationPoints;
  final PageId? resolvedPageId;
  final String? pageResolutionErrorCode;
}

final class CaptureReadiness {
  const CaptureReadiness({
    required this.status,
    required this.stableFrameCount,
    required this.requiredStableFrameCount,
  });

  const CaptureReadiness.notReady()
    : status = CaptureReadinessStatus.notReady,
      stableFrameCount = 0,
      requiredStableFrameCount = 0;

  final CaptureReadinessStatus status;
  final int stableFrameCount;
  final int requiredStableFrameCount;

  bool get isReady => status == CaptureReadinessStatus.ready;
}

final class CameraAnalysisState {
  const CameraAnalysisState({
    required this.tracking,
    required this.quality,
    required this.readiness,
    required this.stabilityScore,
    required this.processingDuration,
    required this.sourceFrameSize,
    required this.analysisFrameSize,
    required this.analysisScaleX,
    required this.analysisScaleY,
    required this.timings,
    this.sensorOrientationDegrees = 0,
    this.deviceOrientation = CameraDeviceOrientation.unknown,
    this.document,
    this.documentFresh = false,
    this.documentTrackingPhase = DocumentTrackingPhase.searching,
  });

  final MarkerTrackingState tracking;
  final FrameQuality quality;
  final CaptureReadiness readiness;
  final double stabilityScore;
  final Duration processingDuration;
  final ImageSize sourceFrameSize;
  final ImageSize analysisFrameSize;
  final double analysisScaleX;
  final double analysisScaleY;
  final CameraAnalysisTimings timings;
  final int sensorOrientationDegrees;
  final CameraDeviceOrientation deviceOrientation;
  final DetectedDocument? document;
  final bool documentFresh;
  final DocumentTrackingPhase documentTrackingPhase;
}

final class CameraDiagnostics {
  const CameraDiagnostics({
    this.receivedFrameCount = 0,
    this.acceptedFrameCount = 0,
    this.processedFrameCount = 0,
    this.droppedFrameCount = 0,
    this.estimatedAnalysisFps = 0,
    this.averageAnalysisDuration = Duration.zero,
    this.readinessDurations = const {},
    this.firstRecognitionToReadyDuration,
    this.paperEdgeDetectionCount = 0,
    this.paperEdgeDetectionFailureCount = 0,
    this.lastPaperEdgeDetectionError,
    this.paperEdgeTemporaryLossCount = 0,
    this.paperEdgeAcquisitionCount = 0,
    this.paperEdgeLossCount = 0,
    this.recoverableAnalysisFailureCount = 0,
    this.lastRecoverableAnalysisError,
    this.arucoAttemptedFrameCount = 0,
    this.readyFrameCount = 0,
    this.averagePaperEdgeDetectionDuration = Duration.zero,
    this.averageArucoDuration = Duration.zero,
    this.timeToFirstMarker,
    this.timeToFirstIdentity,
    this.timeToReady,
  });

  final int receivedFrameCount;
  final int acceptedFrameCount;
  final int processedFrameCount;
  final int droppedFrameCount;
  final double estimatedAnalysisFps;
  final Duration averageAnalysisDuration;
  final Map<CaptureReadinessStatus, Duration> readinessDurations;
  final Duration? firstRecognitionToReadyDuration;
  final int paperEdgeDetectionCount;
  final int paperEdgeDetectionFailureCount;
  final String? lastPaperEdgeDetectionError;
  final int paperEdgeTemporaryLossCount;
  final int paperEdgeAcquisitionCount;
  final int paperEdgeLossCount;
  final int recoverableAnalysisFailureCount;
  final String? lastRecoverableAnalysisError;
  final int arucoAttemptedFrameCount;
  final int readyFrameCount;
  final Duration averagePaperEdgeDetectionDuration;
  final Duration averageArucoDuration;
  final Duration? timeToFirstMarker;
  final Duration? timeToFirstIdentity;
  final Duration? timeToReady;

  double get arucoAttemptRatio => processedFrameCount == 0
      ? 0
      : arucoAttemptedFrameCount / processedFrameCount;

  double get droppedFrameRatio =>
      receivedFrameCount == 0 ? 0 : droppedFrameCount / receivedFrameCount;
}

final class CameraEngineState {
  const CameraEngineState({
    required this.lifecycle,
    required this.diagnostics,
    required this.readiness,
    this.previewInfo,
    this.analysis,
    this.error,
    this.autoCaptureRequested = false,
  });

  const CameraEngineState.uninitialized()
    : lifecycle = CameraLifecycleState.uninitialized,
      diagnostics = const CameraDiagnostics(),
      readiness = const CaptureReadiness.notReady(),
      previewInfo = null,
      analysis = null,
      error = null,
      autoCaptureRequested = false;

  final CameraLifecycleState lifecycle;
  final CameraPreviewInfo? previewInfo;
  final CameraAnalysisState? analysis;
  final CameraDiagnostics diagnostics;
  final CaptureReadiness readiness;
  final EngineError? error;
  final bool autoCaptureRequested;
}

final class CapturedPageImage {
  CapturedPageImage({
    required Uint8List encodedBytes,
    required this.timestamp,
    required this.sensorOrientationDegrees,
    required this.deviceOrientation,
    required this.orientationAppliedByBackend,
    this.width,
    this.height,
  }) : encodedBytes = Uint8List.fromList(encodedBytes);

  final Uint8List encodedBytes;
  final int? width;
  final int? height;
  final DateTime timestamp;
  final int sensorOrientationDegrees;
  final CameraDeviceOrientation deviceOrientation;
  final bool orientationAppliedByBackend;
}
