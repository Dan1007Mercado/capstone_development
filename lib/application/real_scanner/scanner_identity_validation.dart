import '../../core/errors/engine_error.dart';
import '../../core/result/engine_result.dart';
import '../../engines/pdf/domain/template_page_identity_codec.dart';
import '../../engines/scanner/domain/scan_result.dart';
import '../camera_scanner/domain/camera_scan_context.dart';

EngineResult<bool> validateCapturedPageIdentity(
  TemplatePageIdentity actual,
  CameraScanContext expected,
) {
  if (actual.templateId != expected.templateId) {
    return _identityFailure(
      code: 'SCAN_TEMPLATE_ID_MISMATCH',
      message: 'The captured sheet belongs to a different template.',
      actual: actual,
      expected: expected,
    );
  }
  if (actual.templateVersion != expected.templateVersion) {
    return _identityFailure(
      code: 'SCAN_TEMPLATE_VERSION_MISMATCH',
      message: 'The captured sheet belongs to a different template version.',
      actual: actual,
      expected: expected,
    );
  }
  if (actual.pageId != expected.pageId) {
    return _identityFailure(
      code: 'SCAN_PAGE_ID_MISMATCH',
      message: 'The captured sheet is not the expected page.',
      actual: actual,
      expected: expected,
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

EngineResult<bool> _identityFailure({
  required String code,
  required String message,
  required TemplatePageIdentity actual,
  required CameraScanContext expected,
}) => EngineResult.failure(
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
