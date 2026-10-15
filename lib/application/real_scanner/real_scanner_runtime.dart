import '../../engines/camera/application/camera_engine.dart';
import '../../engines/camera/infrastructure/flutter_camera_backend.dart';
import '../../engines/camera/infrastructure/isolate_camera_analysis_worker.dart';
import '../camera_scanner/application/camera_scanner_coordinator.dart';
import '../camera_scanner/infrastructure/camera_scan_adapters.dart';
import '../camera_scanner/infrastructure/isolate_offline_scanner_runner.dart';
import 'scanner_validation_session.dart';

final class RealScannerRuntime {
  const RealScannerRuntime({required this.backend, required this.coordinator});

  final FlutterCameraBackend backend;
  final CameraScannerCoordinator coordinator;
}

RealScannerRuntime createRealScannerRuntime(ScannerValidationSession session) {
  final backend = FlutterCameraBackend();
  final cameraEngine = CameraEngine(
    backend: backend,
    analyzer: IsolateCameraAnalysisWorker(),
  );
  return RealScannerRuntime(
    backend: backend,
    coordinator: CameraScannerCoordinator(
      camera: CameraEngineScanAdapter(cameraEngine),
      imageLoader: const InMemoryCapturedImageBytesLoader(),
      scanner: IsolateOfflineScannerRunner(),
      context: session.currentContext,
    ),
  );
}
