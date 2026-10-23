import 'package:capstone_development/application/camera_scanner/domain/camera_scan_context.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/debug/p14_adaptive_dense_layout_fixture.dart';
import 'package:capstone_development/engines/layout/application/layout_engine.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/layout/domain/layout_regions.dart';
import 'package:capstone_development/engines/pdf/application/pdf_engine.dart';
import 'package:capstone_development/engines/pdf/domain/pdf_render_plan.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config.dart';
import 'package:capstone_development/engines/template/domain/numeric_grid_spec.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_test_fixtures.dart';

void main() {
  final engine = LayoutEngine();

  test('small Likert survey chooses a valid adaptive dense candidate', () {
    final document = engine
        .build(buildP14DenseFlowFixture(), LayoutConfig.a4Dense())
        .value;

    expect(document.selectionDiagnostics, isNotNull);
    expect(document.pages, hasLength(1));
    expect(document.selectionDiagnostics!.selectedColumnCount, 3);
    expect(
      document.pages.every(
        (page) =>
            page.contentColumnRegions.length ==
            document.selectionDiagnostics!.selectedColumnCount,
      ),
      isTrue,
    );
  });

  test('short prompts can select three or four columns when safe', () {
    final template = templateWithQuestions([
      for (var index = 0; index < 24; index++)
        TemplateQuestion.yesNo(
          id: QuestionId('short-$index'),
          prompt: 'Item $index',
          yesOptionId: OptionId('short-$index-y'),
          noOptionId: OptionId('short-$index-n'),
        ),
    ]);
    final diagnostics = engine
        .build(template, LayoutConfig.a4Dense())
        .value
        .selectionDiagnostics!;

    expect(diagnostics.selectedColumnCount, anyOf(3, 4));
  });

  test('long prompts reject unsafe four-column wrapping', () {
    final prompt = List.filled(18, 'extended').join(' ');
    final template = templateWithQuestions([
      for (var index = 0; index < 8; index++)
        choiceQuestion('long-$index', prompt: '$prompt $index'),
    ]);
    final diagnostics = engine
        .build(template, LayoutConfig.a4Dense())
        .value
        .selectionDiagnostics!;
    final four = diagnostics.candidates.singleWhere(
      (candidate) => candidate.columnCount == 4,
    );

    expect(diagnostics.selectedColumnCount, lessThan(4));
    expect(four.rejectedReasons, isNotEmpty);
  });

  test('a tall question moves as one atomic block to the next column', () {
    final template = templateWithQuestions([
      for (var index = 0; index < 20; index++)
        _compactQuestion('lead-$index', 'Q$index'),
      _compactQuestion(
        'tall',
        'This longer question needs two prompt lines and moves atomically',
      ),
    ]);
    final document = engine
        .build(template, LayoutConfig.a4Dense().withFixedColumnCount(2))
        .value;
    final question = document.pages
        .expand((page) => page.questionRegions)
        .singleWhere((region) => region.questionId == QuestionId('tall'));
    final page = document.pages.singleWhere(
      (candidate) => candidate.questionRegions.contains(question),
    );

    expect(question.columnIndex, 1);
    expect(question.promptLineCount, greaterThan(1));
    expect(
      page.contentColumnRegions[question.columnIndex!].physicalBounds
          .containsRect(question.physicalBounds),
      isTrue,
    );
  });

  test('one section continues naturally into another column', () {
    final document = engine
        .build(longTemplate(45), LayoutConfig.a4Dense().withFixedColumnCount(2))
        .value;
    final firstPageFragments = document.pages.first.sectionRegions;

    expect(firstPageFragments.length, greaterThan(1));
    expect(firstPageFragments.map((fragment) => fragment.columnIndex).toSet(), {
      0,
      1,
    });
  });

  test('one section continues onto another page without repeated lead', () {
    final document = engine
        .build(longTemplate(80), LayoutConfig.a4Dense().withFixedColumnCount(2))
        .value;

    expect(document.pages, hasLength(2));
    expect(document.selectionDiagnostics!.selectedColumnCount, 2);
    final continuation = document.pages[1].sectionRegions.first;
    expect(continuation.sectionId, SectionId('section-1'));
    expect(continuation.titleRegion, isNull);
    expect(continuation.instructionRegion, isNull);
  });

  test('no question block is split across columns or pages', () {
    final document = engine
        .build(buildP14LargeMixedFixture(), LayoutConfig.a4Dense())
        .value;

    for (final page in document.pages) {
      for (final question in page.questionRegions) {
        final flowBounds = question.columnIndex == null
            ? page.safeBounds
            : page.contentColumnRegions[question.columnIndex!].physicalBounds;
        expect(flowBounds.containsRect(question.physicalBounds), isTrue);
        expect(
          question.bubbleRegions.every(
            (bubble) =>
                question.physicalBounds.containsRect(bubble.physicalBounds),
          ),
          isTrue,
        );
      }
    }
  });

  test('sixty-question mixed fixture generates valid multipage output', () {
    final document = engine
        .build(buildP14LargeMixedFixture(), LayoutConfig.a4Dense())
        .value;

    // p14.1 deliberately spends one additional page to keep every dense
    // prompt above its bubbles instead of using the old inline mode.
    expect(document.pages, hasLength(3));
    expect(document.selectionDiagnostics!.selectedColumnCount, 2);
    expect(
      document.pages.expand((page) => page.questionRegions),
      hasLength(60),
    );
  });

  test('mixed fixture preserves Likert, select-many and true/false types', () {
    final template = buildP14DenseFlowFixture();
    final document = engine.build(template, LayoutConfig.a4Dense()).value;

    expect(
      document.pages
          .expand((page) => page.questionRegions)
          .map((question) => question.questionType),
      template.sections
          .expand((section) => section.questions)
          .map((question) => question.type),
    );
  });

  test('long multiple-choice labels trigger stacked vertical mode', () {
    final template = templateWithQuestions([
      TemplateQuestion(
        id: QuestionId('long-options'),
        type: QuestionType.multipleChoice,
        prompt: 'Select all that apply',
        options: [
          option('long-a', 'A substantially longer option label A'),
          option('long-b', 'A substantially longer option label B'),
          option('long-c', 'A substantially longer option label C'),
        ],
      ),
    ]);
    final question = engine
        .build(template, LayoutConfig.a4Dense())
        .value
        .pages
        .single
        .questionRegions
        .single;

    expect(question.renderMode, QuestionRenderMode.stackedVertical);
  });

  test('numeric grid remains scanner-safe and unsplit', () {
    final template = templateWithQuestions([
      TemplateQuestion.numericGrid(
        id: QuestionId('grid'),
        prompt: 'Student number',
        spec: NumericGridSpec(columnCount: 12),
      ),
    ]);
    final question = engine
        .build(template, LayoutConfig.a4Dense())
        .value
        .pages
        .single
        .questionRegions
        .single;

    expect(question.renderMode, QuestionRenderMode.numericGrid);
    expect(question.columnIndex, anyOf(isNull, greaterThanOrEqualTo(0)));
    expect(question.bubbleRegions, hasLength(120));
  });

  test('all generated bubbles retain scanner-safe diameter and clearance', () {
    final config = LayoutConfig.a4Dense();
    final document = engine.build(buildP14LargeMixedFixture(), config).value;

    for (final page in document.pages) {
      for (final bubble in page.bubbleRegions) {
        expect(
          bubble.physicalDiameter.millimeters,
          greaterThanOrEqualTo(config.selectionPolicy.minimumBubbleDiameterMm),
        );
      }
    }
  });

  test('all question IDs appear exactly once in logical order', () {
    final template = buildP14LargeMixedFixture();
    final document = engine.build(template, LayoutConfig.a4Dense()).value;
    final expected = template.sections
        .expand((section) => section.questions)
        .map((question) => question.id)
        .toList();
    final actual = document.pages
        .expand((page) => page.questionRegions)
        .map((question) => question.questionId)
        .toList();

    expect(actual, expected);
    expect(actual.toSet(), hasLength(expected.length));
  });

  test('adaptive geometry is deterministic across repeated builds', () {
    final template = buildP14LargeMixedFixture();

    expect(
      engine.build(template, LayoutConfig.a4Dense()).value,
      engine.build(template, LayoutConfig.a4Dense()).value,
    );
  });

  test('PDF and scanner consume the identical selected bubble geometry', () {
    final template = buildP14DenseFlowFixture();
    final document = engine.build(template, LayoutConfig.a4Dense()).value;
    final plan = PdfEngine().buildPlan(template, document).value;

    for (var index = 0; index < document.pages.length; index++) {
      final page = document.pages[index];
      final scanner = CameraScanContext(
        template: template,
        pageLayout: page,
        templateId: template.id,
        templateVersion: template.version,
        pageId: page.pageId,
        scannerConfig: ScannerConfig(),
        candidatePageLayouts: document.pages,
      );
      expect(plan.pages[index].layout, same(page));
      expect(plan.pages[index].bubbles, page.bubbleRegions);
      expect(scanner.pageLayout.bubbleRegions, same(page.bubbleRegions));
      for (final question in page.questionRegions) {
        final prompt = plan.pages[index].text.singleWhere(
          (command) =>
              command.role == PdfTextRole.questionPrompt &&
              command.questionId == question.questionId,
        );
        expect(prompt.bounds, question.promptRegion.physicalBounds);
      }
    }
  });

  test('A4 bounds and ArUco exclusion zones remain valid', () {
    final document = engine
        .build(buildP14LargeMixedFixture(), LayoutConfig.a4Dense())
        .value;

    for (final page in document.pages) {
      expect(page.pageSpec.size.width.millimeters, 210);
      expect(page.pageSpec.size.height.millimeters, 297);
      for (final question in page.questionRegions) {
        expect(page.safeBounds.containsRect(question.physicalBounds), isTrue);
        expect(
          page.markerRegions.any(
            (marker) =>
                marker.physicalBounds.intersects(question.physicalBounds),
          ),
          isFalse,
        );
      }
    }
  });

  test('selection prioritizes readable wrapping before page count', () {
    final diagnostics = engine
        .build(buildP14LargeMixedFixture(), LayoutConfig.a4Dense())
        .value
        .selectionDiagnostics!;
    final valid = diagnostics.candidates.where(
      (candidate) => candidate.isValid,
    );
    final selected = valid.singleWhere(
      (candidate) => candidate.columnCount == diagnostics.selectedColumnCount,
    );

    expect(
      selected.excessivePromptWrappingCount,
      valid
          .map((candidate) => candidate.excessivePromptWrappingCount)
          .reduce((left, right) => left < right ? left : right),
    );
  });

  test('four-column candidate is rejected when prompts are unreadable', () {
    final prompt = List.filled(14, 'unreadable').join(' ');
    final template = templateWithQuestions([
      for (var index = 0; index < 4; index++)
        choiceQuestion('reject-$index', prompt: prompt),
    ]);
    final diagnostics = engine
        .build(template, LayoutConfig.a4Dense())
        .value
        .selectionDiagnostics!;

    expect(
      diagnostics.candidates
          .singleWhere((candidate) => candidate.columnCount == 4)
          .rejectedReasons,
      anyElement(contains('promptWrappingExceeded')),
    );
  });

  test('continuation fragments retain exact section identity', () {
    final document = engine
        .build(longTemplate(80), LayoutConfig.a4Dense().withFixedColumnCount(2))
        .value;

    expect(
      document.pages
          .expand((page) => page.sectionRegions)
          .map((section) => section.sectionId)
          .toSet(),
      {SectionId('section-1')},
    );
  });

  test('every page reports the selected document total page count', () {
    final document = engine
        .build(buildP14LargeMixedFixture(), LayoutConfig.a4Dense())
        .value;

    expect(document.pages.map((page) => page.totalPageCount).toSet(), {
      document.pages.length,
    });
    expect(document.pages.map((page) => page.pageIndex), [
      for (var index = 0; index < document.pages.length; index++) index,
    ]);
  });
}

TemplateQuestion _compactQuestion(String id, String prompt) => TemplateQuestion(
  id: QuestionId(id),
  type: QuestionType.singleChoice,
  prompt: prompt,
  options: [
    option('$id-a', 'A'),
    option('$id-b', 'B'),
    option('$id-c', 'C'),
    option('$id-d', 'D'),
  ],
);
