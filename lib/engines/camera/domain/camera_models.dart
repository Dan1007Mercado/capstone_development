import 'dart:collection';
import 'dart:typed_data';

import '../../../core/errors/engine_error.dart';
import '../../aruco/domain/image_geometry.dart';
import 'camera_engine_config.dart';

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
  markersMissing,
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
  }) : detectedMarkerIds = UnmodifiableListView(List.of(detectedMarkerIds)),
       registrationPoints = UnmodifiableListView(List.of(registrationPoints));

  final List<int> detectedMarkerIds;
  final List<ImagePoint> registrationPoints;
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
}

final class CameraDiagnostics {
  const CameraDiagnostics({
    this.receivedFrameCount = 0,
    this.acceptedFrameCount = 0,
    this.processedFrameCount = 0,
    this.droppedFrameCount = 0,
    this.estimatedAnalysisFps = 0,
    this.averageAnalysisDuration = Duration.zero,
  });

  final int receivedFrameCount;
  final int acceptedFrameCount;
  final int processedFrameCount;
  final int droppedFrameCount;
  final double estimatedAnalysisFps;
  final Duration averageAnalysisDuration;
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
