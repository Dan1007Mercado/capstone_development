import '../../engines/camera/application/camera_engine.dart';
import '../../engines/camera/domain/camera_engine_config.dart';
import '../../engines/camera/infrastructure/flutter_camera_backend.dart';
import '../../engines/camera/infrastructure/isolate_camera_analysis_worker.dart';
import '../../engines/aruco/domain/page_marker_signature_resolver.dart';
import '../camera_scanner/application/camera_scanner_coordinator.dart';
import '../camera_scanner/infrastructure/camera_scan_adapters.dart';
import '../camera_scanner/infrastructure/isolate_offline_scanner_runner.dart';
import 'scanner_validation_session.dart';
import 'failed_scan_capture.dart';

final class RealScannerRuntime {
  const RealScannerRuntime({
    required this.backend,
    required this.coordinator,
    this.failedScanCaptureRecorder,
  });

  final FlutterCameraBackend backend;
  final CameraScannerCoordinator coordinator;
  final FailedScanCaptureRecorder? failedScanCaptureRecorder;
}

RealScannerRuntime createRealScannerRuntime(
  ScannerValidationSession session, {
  bool autoCaptureEnabled = true,
}) {
  final backend = FlutterCameraBackend();
  final cameraEngine = CameraEngine(
    backend: backend,
    analyzer: IsolateCameraAnalysisWorker(),
    config: CameraEngineConfig(
      pageMarkerSignatures: session.pages
          .map(PageMarkerSignature.fromPage)
          .toList(growable: false),
    ),
  );
  final failedCaptureRecorder = failedScanCaptureExportEnabled
      ? FailedScanCaptureRecorder()
      : null;
  return RealScannerRuntime(
    backend: backend,
    failedScanCaptureRecorder: failedCaptureRecorder,
    coordinator: CameraScannerCoordinator(
      camera: CameraEngineScanAdapter(cameraEngine),
      imageLoader: const InMemoryCapturedImageBytesLoader(),
      scanner: IsolateOfflineScannerRunner(),
      context: session.currentContext,
      autoCaptureEnabled: autoCaptureEnabled,
      failedScanCaptureSink: failedCaptureRecorder,
    ),
  );
}
