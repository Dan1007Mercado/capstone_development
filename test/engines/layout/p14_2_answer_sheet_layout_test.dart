import 'package:capstone_development/application/camera_scanner/domain/camera_scan_context.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/layout/application/layout_engine.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/layout/domain/layout_regions.dart';
import 'package:capstone_development/engines/pdf/application/pdf_engine.dart';
import 'package:capstone_development/engines/pdf/domain/pdf_render_plan.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config.dart';
import 'package:capstone_development/engines/template/domain/numeric_grid_spec.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/domain/template_option.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:capstone_development/engines/template/domain/template_section.dart';
import 'package:capstone_development/engines/template/domain/template_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final engine = LayoutEngine();

  test('answer sheet groups consecutive schemas and omits prompts', () {
    final template = _mixedAnswerTemplate();
    final result = engine.build(template, LayoutConfig.a4AnswerSheet());

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    final document = result.value;
    final questions = document.pages
        .expand((page) => page.questionRegions)
        .toList(growable: false);
    expect(questions.map((question) => question.questionNumber), [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
    ]);
    expect(questions.map((question) => question.questionId.value), [
      'likert-1',
      'likert-2',
      'single-4-a',
      'single-4-b',
      'single-5',
      'yes-no',
      'multiple',
    ]);
    expect(questions.map((question) => question.answerGroupLabel), [
      'LIKERT SCALE 1–5',
      null,
      'SINGLE CHOICE A–D',
      null,
      'SINGLE CHOICE A–E',
      'YES / NO',
      'MULTIPLE CHOICE A–D — MARK ALL THAT APPLY',
    ]);
    expect(
      questions.every(
        (question) =>
            question.renderMode == QuestionRenderMode.answerSheetHorizontal,
      ),
      isTrue,
    );
    expect(
      document.pages
          .expand((page) => page.sectionRegions)
          .where((section) => section.titleRegion != null)
          .length,
      1,
    );

    final plan = PdfEngine().buildPlan(template, document).value;
    for (var index = 0; index < document.pages.length; index++) {
      expect(plan.pages[index].layout, document.pages[index]);
      expect(plan.pages[index].bubbles, document.pages[index].bubbleRegions);
    }
    final text = plan.pages.expand((page) => page.text).toList();
    expect(
      text.where((command) => command.role == PdfTextRole.questionPrompt),
      isEmpty,
    );
    expect(
      text.where((command) => command.role == PdfTextRole.questionNumber),
      hasLength(7),
    );
    for (final prompt in template.sections.first.questions.map(
      (q) => q.prompt,
    )) {
      expect(text.any((command) => command.text.contains(prompt)), isFalse);
    }
    expect(
      text
          .where((command) => command.role == PdfTextRole.answerGroupHeading)
          .map((command) => command.text),
      containsAll([
        'LIKERT SCALE 1–5',
        'SINGLE CHOICE A–D',
        'SINGLE CHOICE A–E',
        'YES / NO',
        'MULTIPLE CHOICE A–D — MARK ALL THAT APPLY',
      ]),
    );
    final bubbleLabels = text
        .where((command) => command.role == PdfTextRole.bubbleLabel)
        .toList();
    expect(
      bubbleLabels,
      hasLength(document.pages.expand((p) => p.bubbleRegions).length),
    );
    expect(
      bubbleLabels.map((command) => command.text),
      containsAll(['1', '5', 'A', 'E', 'Y', 'N']),
    );
    for (final command in bubbleLabels) {
      final bubble = document.pages
          .expand((page) => page.bubbleRegions)
          .singleWhere((candidate) => candidate.optionId == command.optionId);
      expect(command.bounds, bubble.physicalBounds);
    }
  });

  test('2, 3, and 4-column answer sheets keep scanner-safe geometry', () {
    final template = _uniformFourOptionTemplate(36);
    for (final columns in [2, 3, 4]) {
      final result = engine.build(
        template,
        LayoutConfig.a4AnswerSheet().withFixedColumnCount(columns),
      );
      expect(
        result.isSuccess,
        isTrue,
        reason: 'columns=$columns ${result.errorOrNull}',
      );
      final document = result.value;
      expect(
        document.pages.every(
          (page) => page.contentColumnRegions.length == columns,
        ),
        isTrue,
      );
      for (final page in document.pages) {
        expect(
          page.bubbleRegions.every(
            (bubble) => bubble.physicalDiameter.millimeters == 5,
          ),
          isTrue,
        );
        expect(
          page.bubbleRegions.every((bubble) => bubble.printedLabel != null),
          isTrue,
        );
        expect(
          page.bubbleRegions.every(
            (bubble) => bubble.measurementCenterExclusionRatio == 0.5,
          ),
          isTrue,
        );
        expect(
          CameraScanContext(
            template: template,
            pageLayout: page,
            templateId: template.id,
            templateVersion: template.version,
            pageId: page.pageId,
            scannerConfig: ScannerConfig(),
            candidatePageLayouts: document.pages,
          ).validate(),
          isNull,
        );
        for (final bubble in page.bubbleRegions) {
          expect(page.safeBounds.containsRect(bubble.physicalBounds), isTrue);
          expect(bubble.normalizedBounds.left.value, inInclusiveRange(0, 1));
          expect(bubble.normalizedBounds.top.value, inInclusiveRange(0, 1));
          expect(bubble.normalizedBounds.right.value, inInclusiveRange(0, 1));
          expect(bubble.normalizedBounds.bottom.value, inInclusiveRange(0, 1));
          expect(
            page.markerRegions.any(
              (marker) =>
                  marker.physicalBounds.intersects(bubble.physicalBounds),
            ),
            isFalse,
          );
        }
      }
    }
  });

  test('adaptive answer sheet is deterministic and prefers three columns', () {
    final template = _uniformFourOptionTemplate(24);
    final first = engine.build(template, LayoutConfig.a4AnswerSheet()).value;
    final second = engine.build(template, LayoutConfig.a4AnswerSheet()).value;

    expect(first, second);
    expect(first.selectionDiagnostics!.selectedColumnCount, 3);
    expect(
      first.selectionDiagnostics!.candidates.map(
        (candidate) => candidate.columnCount,
      ),
      [2, 3, 4],
    );
  });

  test('numeric grid omits its prompt and prints digits inside bubbles', () {
    final template = TemplateDefinition(
      id: TemplateId('p14-2-numeric'),
      version: TemplateVersion(1),
      name: 'Numeric Answer Sheet',
      status: TemplateStatus.draft,
      sections: [
        TemplateSection(
          id: SectionId('numeric'),
          title: 'IDENTITY',
          questions: [
            TemplateQuestion.numericGrid(
              id: QuestionId('student-number'),
              prompt: 'Student number prompt must not print.',
              spec: NumericGridSpec(columnCount: 3),
            ),
          ],
        ),
      ],
    );
    final document = engine
        .build(template, LayoutConfig.a4AnswerSheet().withFixedColumnCount(2))
        .value;
    final question = document.pages.single.questionRegions.single;
    final plan = PdfEngine().buildPlan(template, document).value.pages.single;

    expect(question.renderMode, QuestionRenderMode.answerSheetNumericGrid);
    expect(question.answerGroupLabel, 'NUMERIC GRID 0–9');
    expect(
      question.bubbleRegions.map((bubble) => bubble.printedLabel).toSet(),
      {for (var digit = 0; digit <= 9; digit++) '$digit'},
    );
    expect(
      plan.text.any(
        (command) => command.text.contains('Student number prompt'),
      ),
      isFalse,
    );
  });
}

TemplateDefinition _mixedAnswerTemplate() => TemplateDefinition(
  id: TemplateId('p14-2-mixed'),
  version: TemplateVersion(1),
  name: 'P14.2 Mixed Answer Sheet',
  status: TemplateStatus.draft,
  sections: [
    TemplateSection(
      id: SectionId('experience'),
      title: 'SECTION 1 — EXPERIENCE',
      instruction: 'This full instruction belongs in the questionnaire.',
      questions: [
        _likert('likert-1'),
        _likert('likert-2'),
        _choice('single-4-a', QuestionType.singleChoice, 4),
        _choice('single-4-b', QuestionType.singleChoice, 4),
        _choice('single-5', QuestionType.singleChoice, 5),
        TemplateQuestion.yesNo(
          id: QuestionId('yes-no'),
          prompt: 'This yes/no prompt must not print.',
          yesOptionId: OptionId('yes'),
          noOptionId: OptionId('no'),
        ),
        _choice('multiple', QuestionType.multipleChoice, 4),
      ],
    ),
  ],
);

TemplateQuestion _likert(String id) => TemplateQuestion(
  id: QuestionId(id),
  type: QuestionType.likert,
  prompt: 'Full prompt for $id must not print.',
  options: [
    for (var value = 1; value <= 5; value++)
      TemplateOption(id: OptionId('$id-$value'), label: '$value', value: value),
  ],
);

TemplateQuestion _choice(String id, QuestionType type, int count) =>
    TemplateQuestion(
      id: QuestionId(id),
      type: type,
      prompt: 'Full prompt for $id must not print.',
      options: [
        for (var index = 0; index < count; index++)
          TemplateOption(
            id: OptionId('$id-$index'),
            label: 'Long semantic option $index',
          ),
      ],
    );

TemplateDefinition _uniformFourOptionTemplate(int count) => TemplateDefinition(
  id: TemplateId('p14-2-uniform-$count'),
  version: TemplateVersion(1),
  name: 'Uniform Answer Sheet',
  status: TemplateStatus.draft,
  sections: [
    TemplateSection(
      id: SectionId('uniform'),
      title: 'UNIFORM',
      questions: [
        for (var index = 0; index < count; index++)
          _choice('q$index', QuestionType.singleChoice, 4),
      ],
    ),
  ],
);
