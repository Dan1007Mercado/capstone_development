import '../application/camera_scanner/application/camera_scanner_coordinator.dart';
import '../application/camera_scanner/domain/camera_scan_context.dart';
import '../application/camera_scanner/infrastructure/camera_scan_adapters.dart';
import '../application/camera_scanner/infrastructure/isolate_offline_scanner_runner.dart';
import '../engines/camera/application/camera_engine.dart';
import '../engines/camera/infrastructure/flutter_camera_backend.dart';
import '../engines/camera/infrastructure/isolate_camera_analysis_worker.dart';
import '../engines/layout/domain/page_layout.dart';
import '../engines/scanner/domain/scanner_config.dart';
import '../engines/template/domain/template_definition.dart';
import 'p11_1_scanner_validation_sheet.dart';

final class P11CameraScannerRuntime {
  const P11CameraScannerRuntime({
    required this.backend,
    required this.coordinator,
    required this.template,
    required this.layout,
    required this.scannerConfig,
  });

  final FlutterCameraBackend backend;
  final CameraScannerCoordinator coordinator;
  final TemplateDefinition template;
  final LayoutDocument layout;
  final ScannerConfig scannerConfig;

  CameraScanContext contextForPage(int pageIndex) {
    return buildP11CameraScanContext(
      template: template,
      layout: layout,
      scannerConfig: scannerConfig,
      pageIndex: pageIndex,
    );
  }
}

CameraScanContext buildP11CameraScanContext({
  required TemplateDefinition template,
  required LayoutDocument layout,
  required ScannerConfig scannerConfig,
  required int pageIndex,
}) {
  final page = layout.pages[pageIndex];
  return CameraScanContext(
    template: template,
    pageLayout: page,
    templateId: template.id,
    templateVersion: template.version,
    pageId: page.pageId,
    scannerConfig: scannerConfig,
  );
}

P11CameraScannerRuntime createP11CameraScannerRuntime() {
  final inputs = buildP11ScannerValidationSheetInputs();
  final page = inputs.layout.pages.first;
  final scannerConfig = ScannerConfig();
  final backend = FlutterCameraBackend();
  final cameraEngine = CameraEngine(
    backend: backend,
    analyzer: IsolateCameraAnalysisWorker(),
  );
  return P11CameraScannerRuntime(
    backend: backend,
    template: inputs.template,
    layout: inputs.layout,
    scannerConfig: scannerConfig,
    coordinator: CameraScannerCoordinator(
      camera: CameraEngineScanAdapter(cameraEngine),
      imageLoader: const InMemoryCapturedImageBytesLoader(),
      scanner: IsolateOfflineScannerRunner(),
      context: buildP11CameraScanContext(
        template: inputs.template,
        layout: inputs.layout,
        scannerConfig: scannerConfig,
        pageIndex: page.pageIndex,
      ),
    ),
  );
}
