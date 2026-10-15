import '../application/camera_scanner/application/camera_scanner_coordinator.dart';
import '../application/camera_scanner/domain/camera_scan_context.dart';
import '../application/camera_scanner/infrastructure/camera_scan_adapters.dart';
import '../engines/aruco/infrastructure/opencv_aruco_vision_backend.dart';
import '../engines/camera/application/camera_engine.dart';
import '../engines/camera/infrastructure/flutter_camera_backend.dart';
import '../engines/camera/infrastructure/isolate_camera_analysis_worker.dart';
import '../engines/preprocessing/infrastructure/dart_image_preprocessing_backend.dart';
import '../engines/scanner/domain/scanner_config.dart';
import '../engines/scanner/infrastructure/offline_scanner_composition.dart';
import 'p10_camera_test_sheet.dart';

final class P11CameraScannerRuntime {
  const P11CameraScannerRuntime({
    required this.backend,
    required this.coordinator,
  });

  final FlutterCameraBackend backend;
  final CameraScannerCoordinator coordinator;
}

P11CameraScannerRuntime createP11CameraScannerRuntime() {
  final inputs = buildP10CameraTestSheetInputs();
  final page = inputs.layout.pages.single;
  final backend = FlutterCameraBackend();
  final cameraEngine = CameraEngine(
    backend: backend,
    analyzer: IsolateCameraAnalysisWorker(),
  );
  final scanner = OfflineScannerComposition.create(
    alignmentBackend: const OpenCvArucoVisionBackend(),
    preprocessingBackend: const DartImagePreprocessingBackend(),
  );
  return P11CameraScannerRuntime(
    backend: backend,
    coordinator: CameraScannerCoordinator(
      camera: CameraEngineScanAdapter(cameraEngine),
      imageLoader: const InMemoryCapturedImageBytesLoader(),
      scanner: OfflineScannerRunnerAdapter(scanner),
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
