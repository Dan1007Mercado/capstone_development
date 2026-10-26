import '../../engines/camera/application/camera_engine.dart';
import '../../engines/camera/domain/camera_engine_config.dart';
import '../../engines/camera/infrastructure/flutter_camera_backend.dart';
import '../../engines/camera/infrastructure/isolate_camera_analysis_worker.dart';
import '../../engines/aruco/domain/page_marker_signature_resolver.dart';
import '../camera_scanner/application/camera_scanner_coordinator.dart';
import '../camera_scanner/infrastructure/camera_scan_adapters.dart';
import '../camera_scanner/infrastructure/isolate_offline_scanner_runner.dart';
import 'scanner_validation_session.dart';

final class RealScannerRuntime {
  const RealScannerRuntime({required this.backend, required this.coordinator});

  final FlutterCameraBackend backend;
  final CameraScannerCoordinator coordinator;
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
  return RealScannerRuntime(
    backend: backend,
    coordinator: CameraScannerCoordinator(
      camera: CameraEngineScanAdapter(cameraEngine),
      imageLoader: const InMemoryCapturedImageBytesLoader(),
      scanner: IsolateOfflineScannerRunner(),
      context: session.currentContext,
      autoCaptureEnabled: autoCaptureEnabled,
    ),
  );
}
