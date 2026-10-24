import '../../../core/errors/engine_error.dart';
import '../../../core/ids/identifiers.dart';
import '../../../engines/layout/domain/page_layout.dart';
import '../../../engines/scanner/domain/scanner_config.dart';
import '../../../engines/scanner/domain/packet_scan_identity.dart';
import '../../../engines/template/domain/template_definition.dart';

final class CameraScanContext {
  const CameraScanContext({
    required this.template,
    required this.pageLayout,
    required this.templateId,
    required this.templateVersion,
    required this.pageId,
    required this.scannerConfig,
    this.candidatePageLayouts = const [],
    this.packetScanContext,
  });

  final TemplateDefinition template;
  final PageLayout pageLayout;
  final TemplateId templateId;
  final TemplateVersion templateVersion;
  final PageId pageId;
  final ScannerConfig scannerConfig;
  final List<PageLayout> candidatePageLayouts;
  final PacketScanContext? packetScanContext;

  List<PageLayout> get availablePages =>
      candidatePageLayouts.isEmpty ? [pageLayout] : candidatePageLayouts;

  CameraScanContext withPage(PageLayout page) => CameraScanContext(
    template: template,
    pageLayout: page,
    templateId: templateId,
    templateVersion: templateVersion,
    pageId: page.pageId,
    scannerConfig: scannerConfig,
    candidatePageLayouts: availablePages,
    packetScanContext: packetScanContext,
  );

  EngineError? validate() {
    if (template.id != templateId ||
        template.version != templateVersion ||
        pageLayout.templateId != templateId ||
        pageLayout.templateVersion != templateVersion ||
        pageLayout.pageId != pageId ||
        availablePages.any(
          (page) =>
              page.templateId != templateId ||
              page.templateVersion != templateVersion,
        )) {
      return EngineError(
        code: 'CAPTURE_SCAN_CONTEXT_INVALID',
        message: 'The expected template identity and PageLayout do not match.',
        details: {
          'templateId': templateId.value,
          'templateVersion': templateVersion.value,
          'pageId': pageId.value,
        },
      );
    }
    return null;
  }
}
