import '../application/camera_scanner/application/camera_scanner_coordinator.dart';
import '../application/camera_scanner/domain/camera_scan_context.dart';
import '../application/camera_scanner/infrastructure/camera_scan_adapters.dart';
import '../application/camera_scanner/infrastructure/isolate_offline_scanner_runner.dart';
import '../engines/camera/application/camera_engine.dart';
import '../engines/camera/infrastructure/flutter_camera_backend.dart';
import '../engines/camera/infrastructure/isolate_camera_analysis_worker.dart';
import '../engines/scanner/domain/scanner_config.dart';
import 'p11_1_scanner_validation_sheet.dart';

final class P11CameraScannerRuntime {
  const P11CameraScannerRuntime({
    required this.backend,
    required this.coordinator,
  });

  final FlutterCameraBackend backend;
  final CameraScannerCoordinator coordinator;
}

P11CameraScannerRuntime createP11CameraScannerRuntime() {
  final inputs = buildP11ScannerValidationSheetInputs();
  // The richer fixture paginates naturally. The current single-page capture
  // workflow validates page 1; later multi-page orchestration remains out of
  // scope for P11.1.
  final page = inputs.layout.pages.first;
  final backend = FlutterCameraBackend();
  final cameraEngine = CameraEngine(
    backend: backend,
    analyzer: IsolateCameraAnalysisWorker(),
  );
  return P11CameraScannerRuntime(
    backend: backend,
    coordinator: CameraScannerCoordinator(
      camera: CameraEngineScanAdapter(cameraEngine),
      imageLoader: const InMemoryCapturedImageBytesLoader(),
      scanner: IsolateOfflineScannerRunner(),
      context: CameraScanContext(
        template: inputs.template,
        pageLayout: page,
        templateId: inputs.template.id,
        templateVersion: inputs.template.version,
        pageId: page.pageId,
        scannerConfig: ScannerConfig(),
      ),
    ),
  );
}
