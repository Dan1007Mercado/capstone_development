import '../../core/result/engine_result.dart';
import '../../engines/pdf/domain/template_page_identity_codec.dart';
import '../../engines/scanner/domain/scan_result.dart';
import '../../engines/scanner/domain/scanner_identity.dart';
import '../camera_scanner/domain/camera_scan_context.dart';

EngineResult<bool> validateCapturedPageIdentity(
  TemplatePageIdentity actual,
  CameraScanContext expected,
) => validateTemplatePageIdentity(
  actual: actual,
  expectedTemplateId: expected.templateId,
  expectedTemplateVersion: expected.templateVersion,
  expectedPageId: expected.pageId,
);

EngineResult<bool> validateScanResultIdentity(
  ScanResult actual,
  CameraScanContext expected,
) => validateCapturedPageIdentity(
  TemplatePageIdentity(
    templateId: actual.templateId,
    templateVersion: actual.templateVersion,
    pageId: actual.pageId,
  ),
  expected,
);
