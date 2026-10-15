import 'dart:convert';

import 'package:capstone_development/application/camera_scanner/domain/camera_scan_context.dart';
import 'package:capstone_development/debug/p11_1_scanner_validation_sheet.dart';
import 'package:capstone_development/engines/pdf/application/pdf_engine.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rich fixture has deterministic intended question mix and order', () {
    final first = buildP11ScannerValidationSheetInputs();
    final second = buildP11ScannerValidationSheetInputs();
    final questions = first.template.sections.expand(
      (section) => section.questions,
    );

    expect(first.template, second.template);
    expect(first.layout, second.layout);
    expect(first.layout.pages, hasLength(3));
    expect(first.layout.pages.first.pageId.value, endsWith('-p1'));
    expect(first.template.sections.map((section) => section.id.value), [
      'section-likert',
      'section-single',
      'section-multiple',
      'section-yes-no',
      'section-numeric',
    ]);
    expect(questions.map((question) => question.id.value), [
      'q1',
      'q2',
      'q3',
      'q4',
      'q5',
      'q6',
      'q7',
      'q8',
      'q9',
      'q10',
    ]);
    expect(questions.map((question) => question.type), [
      QuestionType.likert,
      QuestionType.likert,
      QuestionType.likert,
      QuestionType.singleChoice,
      QuestionType.singleChoice,
      QuestionType.multipleChoice,
      QuestionType.multipleChoice,
      QuestionType.yesNo,
      QuestionType.yesNo,
      QuestionType.numericGrid,
    ]);
  });

  test(
    'PDF plan and scanner context share exact authoritative pages',
    () async {
      final inputs = buildP11ScannerValidationSheetInputs();
      final plan = PdfEngine().buildPlan(inputs.template, inputs.layout).value;
      final rendered = await renderP11ScannerValidationSheetPdf();

      expect(plan.pages.map((page) => page.layout), inputs.layout.pages);
      for (final page in inputs.layout.pages) {
        expect(page.markerRegions.map((marker) => marker.markerId), [
          10,
          11,
          12,
          13,
        ]);
        final context = CameraScanContext(
          template: inputs.template,
          pageLayout: page,
          templateId: inputs.template.id,
          templateVersion: inputs.template.version,
          pageId: page.pageId,
          scannerConfig: ScannerConfig(),
        );
        expect(context.pageLayout, same(page));
        expect(context.validate(), isNull);
      }
      expect(rendered.isSuccess, isTrue);
      expect(_pdfPageCount(rendered.value), inputs.layout.pages.length);
    },
  );
}

int _pdfPageCount(List<int> bytes) => RegExp(
  r'/Type\s*/Page(?!s)',
).allMatches(latin1.decode(bytes, allowInvalid: true)).length;
