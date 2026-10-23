import 'package:capstone_development/application/camera_scanner/domain/camera_scan_context.dart';
import 'package:capstone_development/core/geometry/geometry_converter.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/debug/p13_6_dense_validation_sheet.dart';
import 'package:capstone_development/debug/p14_adaptive_dense_layout_fixture.dart';
import 'package:capstone_development/engines/layout/application/layout_engine.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/layout/domain/layout_regions.dart';
import 'package:capstone_development/engines/pdf/application/pdf_engine.dart';
import 'package:capstone_development/engines/pdf/domain/pdf_render_plan.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_option.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_test_fixtures.dart';

void main() {
  final engine = LayoutEngine();

  test('dense ordinary questions always place prompt above bubble row', () {
    final template = templateWithQuestions([
      TemplateQuestion.yesNo(
        id: QuestionId('yes-no'),
        prompt: "Who's the commander of something?",
        yesOptionId: OptionId('yes'),
        noOptionId: OptionId('no'),
      ),
      TemplateQuestion(
        id: QuestionId('likert'),
        type: QuestionType.likert,
        prompt: 'The application was easy to use.',
        options: [
          for (var value = 1; value <= 5; value++)
            TemplateOption(
              id: OptionId('likert-$value'),
              label: '$value',
              value: value,
            ),
        ],
      ),
    ]);
    final config = LayoutConfig.a4Dense().withFixedColumnCount(3);
    final page = engine.build(template, config).value.pages.single;

    for (final question in page.questionRegions) {
      expect(question.renderMode, QuestionRenderMode.stackedHorizontal);
      expect(
        question.promptRegion.physicalBounds.top,
        question.physicalBounds.top,
      );
      expect(
        question.bubbleRegions.every(
          (bubble) =>
              bubble.physicalBounds.top.millimeters >=
              question.promptRegion.physicalBounds.bottom.millimeters +
                  config.minimumContentGapMm,
        ),
        isTrue,
      );
      expect(
        question.bubbleRegions
            .map((bubble) => bubble.physicalBounds.top)
            .toSet(),
        hasLength(1),
      );
    }
  });

  test('numbering prefix participates in prompt measurement', () {
    final template = templateWithQuestions([
      for (var index = 1; index <= 10; index++)
        TemplateQuestion.yesNo(
          id: QuestionId('numbered-$index'),
          prompt: index < 9 ? 'x' : List.filled(19, 'x').join(),
          yesOptionId: OptionId('numbered-$index-y'),
          noOptionId: OptionId('numbered-$index-n'),
        ),
    ]);
    final questions = engine
        .build(template, LayoutConfig.a4Dense().withFixedColumnCount(3))
        .value
        .pages
        .expand((page) => page.questionRegions)
        .toList();

    expect(questions[8].questionNumber, 9);
    expect(questions[8].promptLineCount, 1);
    expect(questions[9].questionNumber, 10);
    expect(questions[9].promptLineCount, 2);
  });

  test('global numbering remains exact across sections columns and pages', () {
    final document = engine
        .build(
          buildP14LargeMixedFixture(questionCount: 80),
          LayoutConfig.a4Dense(),
        )
        .value;
    final questions = document.pages
        .expand((page) => page.questionRegions)
        .toList(growable: false);

    expect(questions.map((question) => question.questionNumber), [
      for (var number = 1; number <= 80; number++) number,
    ]);
    expect(document.pages.length, greaterThan(1));
  });

  test('compact layout prefers three columns with tighter safe gap', () {
    final config = LayoutConfig.a4Dense();
    final document = engine
        .build(buildP13_6DenseValidationTemplate(), config)
        .value;
    final diagnostics = document.selectionDiagnostics!;
    final selected = diagnostics.candidates.singleWhere(
      (candidate) => candidate.columnCount == diagnostics.selectedColumnCount,
    );

    expect(diagnostics.selectedColumnCount, 3);
    expect(config.columnGapMm, 4.5);
    expect(
      config.columnGapMm,
      greaterThanOrEqualTo(config.selectionPolicy.minimumColumnGapMm),
    );
    expect(selected.columnWidthMm, greaterThanOrEqualTo(34));
    expect(selected.columnGapMm, 4.5);
    expect(selected.bubbleDiameterMm, 5);
    expect(selected.fullWidthFallbackCount, 0);
  });

  test('wide mixed fixture selects two columns before narrow fallback', () {
    final diagnostics = engine
        .build(buildP14LargeMixedFixture(), LayoutConfig.a4Dense())
        .value
        .selectionDiagnostics!;

    expect(diagnostics.selectedColumnCount, 2);
    final selected = diagnostics.candidates.singleWhere(
      (candidate) => candidate.columnCount == 2,
    );
    final three = diagnostics.candidates.singleWhere(
      (candidate) => candidate.columnCount == 3,
    );
    expect(selected.isValid, isTrue);
    expect(three.isValid, isFalse);
    expect(three.rejectedReasons, isNotEmpty);
  });

  test('PDF prints the exact globally numbered measured prompt', () {
    final template = buildP14DenseFlowFixture();
    final document = engine.build(template, LayoutConfig.a4Dense()).value;
    final plan = PdfEngine().buildPlan(template, document).value;

    for (var pageIndex = 0; pageIndex < document.pages.length; pageIndex++) {
      for (final question in document.pages[pageIndex].questionRegions) {
        final semantic = template.sections
            .expand((section) => section.questions)
            .singleWhere((candidate) => candidate.id == question.questionId);
        final command = plan.pages[pageIndex].text.singleWhere(
          (candidate) =>
              candidate.role == PdfTextRole.questionPrompt &&
              candidate.questionId == question.questionId,
        );
        expect(
          command.text,
          startsWith('${question.questionNumber}. ${semantic.prompt}'),
        );
        expect(command.bounds, question.promptRegion.physicalBounds);
      }
    }
  });

  test('every p14.1 page validates as the exact camera geometry', () {
    final template = buildP14LargeMixedFixture(questionCount: 80);
    final document = engine.build(template, LayoutConfig.a4Dense()).value;

    for (final page in document.pages) {
      final context = CameraScanContext(
        template: template,
        pageLayout: page,
        templateId: template.id,
        templateVersion: template.version,
        pageId: page.pageId,
        scannerConfig: ScannerConfig(),
        candidatePageLayouts: document.pages,
      );
      expect(context.validate(), isNull);
      expect(context.pageLayout, same(page));
      expect(context.pageLayout.bubbleRegions, same(page.bubbleRegions));
      for (final bubble in context.pageLayout.bubbleRegions) {
        expect(
          bubble.normalizedBounds,
          GeometryConverter.physicalRectToNormalized(
            bubble.physicalBounds,
            page.pageSpec.size,
          ),
        );
      }
    }
  });

  test('old dense golden remains 40 questions and 160 five-mm bubbles', () {
    final inputs = buildP13_6DenseValidationInputs();

    expect(inputs.layout.pages.single.contentColumnRegions, hasLength(2));
    expect(inputs.layout.pages.single.questionRegions, hasLength(40));
    expect(inputs.layout.pages.single.bubbleRegions, hasLength(160));
    expect(
      inputs.layout.pages.single.bubbleRegions.every(
        (bubble) => bubble.physicalDiameter.millimeters == 5,
      ),
      isTrue,
    );
  });

  test('p14.1 dense PDF generation succeeds with shared page count', () async {
    final template = buildP14LargeMixedFixture();
    final document = engine.build(template, LayoutConfig.a4Dense()).value;
    final result = await PdfEngine().render(template, document);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(result.value, isNotEmpty);
    expect(
      PdfEngine().buildPlan(template, document).value.pages,
      hasLength(document.pages.length),
    );
  });
}
