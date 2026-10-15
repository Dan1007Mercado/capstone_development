import 'package:capstone_development/application/camera_scanner/domain/camera_scan_context.dart';
import 'package:capstone_development/application/real_scanner/scanner_identity_validation.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/debug/p5_native_validation_fixture.dart';
import 'package:capstone_development/engines/pdf/domain/template_page_identity_codec.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CameraScanContext context;

  setUp(() {
    final template = buildP5NativeValidationTemplate();
    final page = buildP5NativeValidationPage();
    context = CameraScanContext(
      template: template,
      pageLayout: page,
      templateId: template.id,
      templateVersion: template.version,
      pageId: page.pageId,
      scannerConfig: ScannerConfig(),
    );
  });

  test('exact printed identity is accepted', () {
    final result = validateCapturedPageIdentity(
      TemplatePageIdentity(
        templateId: context.templateId,
        templateVersion: context.templateVersion,
        pageId: context.pageId,
      ),
      context,
    );

    expect(result.isSuccess, isTrue);
  });

  test('wrong template, version, and page have distinct typed failures', () {
    final wrongTemplate = validateCapturedPageIdentity(
      TemplatePageIdentity(
        templateId: TemplateId('another-template'),
        templateVersion: context.templateVersion,
        pageId: context.pageId,
      ),
      context,
    );
    final wrongVersion = validateCapturedPageIdentity(
      TemplatePageIdentity(
        templateId: context.templateId,
        templateVersion: TemplateVersion(context.templateVersion.value + 1),
        pageId: context.pageId,
      ),
      context,
    );
    final wrongPage = validateCapturedPageIdentity(
      TemplatePageIdentity(
        templateId: context.templateId,
        templateVersion: context.templateVersion,
        pageId: PageId('another-page'),
      ),
      context,
    );

    expect(wrongTemplate.error.code, 'SCAN_TEMPLATE_ID_MISMATCH');
    expect(wrongVersion.error.code, 'SCAN_TEMPLATE_VERSION_MISMATCH');
    expect(wrongPage.error.code, 'SCAN_PAGE_ID_MISMATCH');
  });
}
