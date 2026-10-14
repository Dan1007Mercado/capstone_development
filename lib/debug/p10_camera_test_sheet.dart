import 'dart:typed_data';

import '../core/result/engine_result.dart';
import '../engines/layout/domain/page_layout.dart';
import '../engines/pdf/application/pdf_engine.dart';
import '../engines/template/domain/template_definition.dart';
import 'p5_native_validation_fixture.dart';

const p10CameraTestSheetOutputPath = 'debug_output/p10_camera_test_sheet.pdf';

({TemplateDefinition template, LayoutDocument layout})
buildP10CameraTestSheetInputs() {
  final template = buildP5NativeValidationTemplate(
    name: 'P10 Camera Validation Sheet',
  );
  final page = buildP5NativeValidationPage();
  return (
    template: template,
    layout: LayoutDocument(
      templateId: page.templateId,
      templateVersion: page.templateVersion,
      pages: [page],
    ),
  );
}

Future<EngineResult<Uint8List>> renderP10CameraTestSheetPdf() {
  final inputs = buildP10CameraTestSheetInputs();
  return PdfEngine().render(inputs.template, inputs.layout);
}
