import '../../core/result/engine_result.dart';
import '../../core/errors/engine_error.dart';
import '../../engines/pdf/domain/template_page_identity_codec.dart';
import '../../engines/scanner/domain/scan_result.dart';
import '../camera_scanner/domain/camera_scan_context.dart';

EngineResult<bool> validateCapturedPageIdentity(
  TemplatePageIdentity actual,
  CameraScanContext expected,
) {
  if (actual.templateId != expected.templateId) {
    return _failure(
      'SCAN_TEMPLATE_ID_MISMATCH',
      'The captured sheet belongs to a different template.',
      actual,
      expected,
    );
  }
  if (actual.templateVersion != expected.templateVersion) {
    return _failure(
      'SCAN_TEMPLATE_VERSION_MISMATCH',
      'The captured sheet belongs to a different template version.',
      actual,
      expected,
    );
  }
  if (actual.pageId != expected.pageId) {
    return _failure(
      'SCAN_PAGE_ID_MISMATCH',
      'The captured sheet is not the expected page.',
      actual,
      expected,
    );
  }
  return EngineResult.success(true);
}

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

EngineResult<bool> _failure(
  String code,
  String message,
  TemplatePageIdentity actual,
  CameraScanContext expected,
) => EngineResult.failure(
  EngineError(
    code: code,
    message: message,
    details: {
      'expectedTemplateId': expected.templateId.value,
      'actualTemplateId': actual.templateId.value,
      'expectedTemplateVersion': expected.templateVersion.value,
      'actualTemplateVersion': actual.templateVersion.value,
      'expectedPageId': expected.pageId.value,
      'actualPageId': actual.pageId.value,
    },
  ),
);
