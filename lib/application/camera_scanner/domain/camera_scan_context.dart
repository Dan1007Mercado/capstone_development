import '../../../core/errors/engine_error.dart';
import '../../../core/ids/identifiers.dart';
import '../../../engines/layout/domain/page_layout.dart';
import '../../../engines/scanner/domain/scanner_config.dart';
import '../../../engines/template/domain/template_definition.dart';

final class CameraScanContext {
  const CameraScanContext({
    required this.template,
    required this.pageLayout,
    required this.templateId,
    required this.templateVersion,
    required this.pageId,
    required this.scannerConfig,
  });

  final TemplateDefinition template;
  final PageLayout pageLayout;
  final TemplateId templateId;
  final TemplateVersion templateVersion;
  final PageId pageId;
  final ScannerConfig scannerConfig;

  EngineError? validate() {
    if (template.id != templateId ||
        template.version != templateVersion ||
        pageLayout.templateId != templateId ||
        pageLayout.templateVersion != templateVersion ||
        pageLayout.pageId != pageId) {
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
