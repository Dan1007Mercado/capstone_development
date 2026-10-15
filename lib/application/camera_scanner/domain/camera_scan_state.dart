import '../../../core/errors/engine_error.dart';
import '../../../engines/camera/domain/camera_models.dart';
import '../../../engines/scanner/domain/scan_result.dart';

enum CameraScanPhase {
  idle,
  cameraInitializing,
  cameraReady,
  tracking,
  readyToCapture,
  capturing,
  scanning,
  scanCompleted,
  scanFailed,
  disposed,
}

final class FinalScanTimings {
  const FinalScanTimings({
    this.captureDuration = Duration.zero,
    this.byteLoadDuration = Duration.zero,
    this.scannerDuration = Duration.zero,
    this.totalDuration = Duration.zero,
    this.workerDuration = Duration.zero,
    this.isolateOverhead = Duration.zero,
    this.workerReused = false,
    this.workerStartupDuration = Duration.zero,
  });

  static const zero = FinalScanTimings();

  final Duration captureDuration;
  final Duration byteLoadDuration;
  final Duration scannerDuration;
  final Duration totalDuration;
  final Duration workerDuration;
  final Duration isolateOverhead;
  final bool workerReused;
  final Duration workerStartupDuration;
}

final class CameraScanState {
  const CameraScanState({
    required this.phase,
    required this.cameraState,
    this.result,
    this.error,
    this.finalScanTimings = FinalScanTimings.zero,
  });

  const CameraScanState.idle()
    : phase = CameraScanPhase.idle,
      cameraState = const CameraEngineState.uninitialized(),
      result = null,
      error = null,
      finalScanTimings = FinalScanTimings.zero;

  final CameraScanPhase phase;
  final CameraEngineState cameraState;
  final ScanResult? result;
  final EngineError? error;
  final FinalScanTimings finalScanTimings;

  bool get canCapture => phase == CameraScanPhase.readyToCapture;
  bool get operationInProgress =>
      phase == CameraScanPhase.capturing || phase == CameraScanPhase.scanning;
}
