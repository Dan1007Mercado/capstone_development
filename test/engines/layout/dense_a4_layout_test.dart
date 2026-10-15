import 'dart:convert';

import 'package:capstone_development/core/geometry/geometry_converter.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/application/camera_scanner/domain/camera_scan_context.dart';
import 'package:capstone_development/debug/p13_6_dense_validation_sheet.dart';
import 'package:capstone_development/engines/layout/application/layout_engine.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/layout/domain/layout_regions.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/pdf/application/pdf_engine.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config.dart';
import 'package:capstone_development/engines/template/domain/numeric_grid_spec.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_test_fixtures.dart';

void main() {
  test('profile factories are explicit and default values are unchanged', () {
    final comfortable = LayoutConfig.a4Default();
    final dense = LayoutConfig.a4Dense();

    expect(comfortable.profile, LayoutProfile.comfortable);
    expect(comfortable.columnCount, 1);
    expect(comfortable.bubbleDiameterMm, 5);
    expect(comfortable.questionVerticalGapMm, 6);
    expect(comfortable.identityRegionHeightMm, 12);
    expect(dense.profile, LayoutProfile.dense);
    expect(dense.columnCount, 2);
    expect(dense.bubbleDiameterMm, 5);
  });

  test('dense 40-question fixture is deterministic and denser', () {
    final template = buildP13_6DenseValidationTemplate();
    final engine = LayoutEngine();
    final first = engine.build(template, LayoutConfig.a4Dense()).value;
    final second = engine.build(template, LayoutConfig.a4Dense()).value;
    final comfortable = engine.build(template, LayoutConfig.a4Default()).value;

    expect(first, second);
    expect(first.pages, hasLength(1));
    expect(comfortable.pages, hasLength(4));
    expect(first.pages.length, lessThanOrEqualTo(comfortable.pages.length));
    expect(first.pages.single.questionRegions, hasLength(40));
    expect(first.pages.single.contentColumnRegions, hasLength(2));
  });

  test(
    'dense columns transition deterministically at the section boundary',
    () {
      final page = buildP13_6DenseValidationInputs().layout.pages.single;
      final firstColumn = page.questionRegions
          .where((question) => question.columnIndex == 0)
          .toList();
      final secondColumn = page.questionRegions
          .where((question) => question.columnIndex == 1)
          .toList();

      expect(firstColumn, hasLength(20));
      expect(secondColumn, hasLength(20));
      expect(firstColumn.first.questionId, QuestionId('dense-q01'));
      expect(firstColumn.last.questionId, QuestionId('dense-q20'));
      expect(secondColumn.first.questionId, QuestionId('dense-q21'));
      expect(secondColumn.last.questionId, QuestionId('dense-q40'));
      expect(page.sectionRegions.map((section) => section.columnIndex), [0, 1]);
    },
  );

  test('overflow transitions to the next page with compact continuation', () {
    final inputs = buildP13_6DenseValidationInputs(questionCount: 41);

    expect(inputs.layout.pages, hasLength(2));
    expect(
      inputs.layout.pages.last.questionRegions.single.questionId,
      QuestionId('dense-q41'),
    );
    expect(
      inputs.layout.pages.last.markerRegions.map((marker) => marker.markerId),
      [14, 15, 16, 17],
    );
    final continuation = inputs.layout.pages.last.sectionRegions.single;
    expect(continuation.titleRegion, isNull);
    expect(continuation.instructionRegion, isNull);
    expect(continuation.humanReadableFieldRegion, isNull);
  });

  test('long prompt and wide grid use safe full-width placement', () {
    final longPrompt = List.filled(80, 'x').join();
    final template = templateWithQuestions([
      choiceQuestion('long', prompt: longPrompt, optionCount: 4),
      TemplateQuestion.numericGrid(
        id: QuestionId('wide-grid'),
        prompt: 'Fill the wide numeric grid',
        spec: NumericGridSpec(columnCount: 15),
      ),
    ]);
    final layout = LayoutEngine().build(template, LayoutConfig.a4Dense()).value;

    expect(layout.pages, hasLength(2));
    for (final page in layout.pages) {
      final question = page.questionRegions.single;
      expect(question.columnIndex, isNull);
      expect(question.physicalBounds.left, page.safeBounds.left);
      expect(question.physicalBounds.right, page.safeBounds.right);
      expect(page.safeBounds.containsRect(question.physicalBounds), isTrue);
    }
  });

  test('dense geometry has no content, question, or bubble overlap', () {
    final document = buildP13_6DenseValidationInputs().layout;

    for (final page in document.pages) {
      _expectNoOverlap(page);
    }
  });

  test('mixed dense fixture supports compact question semantics', () {
    final template = buildP13_6DenseMixedValidationTemplate();
    final layout = LayoutEngine().build(template, LayoutConfig.a4Dense()).value;

    expect(layout.pages, hasLength(1));
    expect(layout.pages.single.questionRegions, hasLength(8));
    expect(
      layout.pages.single.questionRegions.map(
        (question) => question.questionType,
      ),
      template.sections
          .expand((section) => section.questions)
          .map((question) => question.type),
    );
    _expectNoOverlap(layout.pages.single);
  });

  test('dense bubbles preserve 5 mm diameter, centers, and option order', () {
    final inputs = buildP13_6DenseValidationInputs();
    final page = inputs.layout.pages.single;

    for (final question in page.questionRegions) {
      final semantic = inputs.template.sections
          .expand((section) => section.questions)
          .singleWhere((candidate) => candidate.id == question.questionId);
      expect(
        question.bubbleRegions.map((bubble) => bubble.optionId),
        semantic.options.map((option) => option.id),
      );
      for (final bubble in question.bubbleRegions) {
        expect(bubble.physicalDiameter.millimeters, 5);
        expect(bubble.physicalBounds.center, bubble.physicalCenter);
        expect(
          bubble.normalizedCenter,
          GeometryConverter.physicalPointToNormalized(
            bubble.physicalCenter,
            page.pageSpec.size,
          ),
        );
      }
    }
  });

  test('dense marker IDs and registration geometry remain unchanged', () {
    final dense = buildP13_6DenseValidationInputs().layout.pages.single;
    final comfortable = buildLayout(
      buildP13_6DenseValidationTemplate(),
      config: LayoutConfig.a4Default(),
    ).pages.first;

    expect(dense.markerRegions.map((marker) => marker.markerId), [
      10,
      11,
      12,
      13,
    ]);
    for (var index = 0; index < dense.markerRegions.length; index++) {
      expect(
        dense.markerRegions[index].physicalBounds,
        comfortable.markerRegions[index].physicalBounds,
      );
      expect(
        dense.markerRegions[index].physicalMarkerBounds,
        comfortable.markerRegions[index].physicalMarkerBounds,
      );
      expect(
        dense.markerRegions[index].physicalRegistrationPoint,
        comfortable.markerRegions[index].physicalRegistrationPoint,
      );
    }
  });

  test('stress fixture contains every question and bubble exactly once', () {
    final inputs = buildP13_6DenseValidationInputs();
    final questions = inputs.layout.pages
        .expand((page) => page.questionRegions)
        .toList();
    final bubbles = inputs.layout.pages.expand((page) => page.bubbleRegions);
    final expectedIds = inputs.template.sections
        .expand((section) => section.questions)
        .map((question) => question.id)
        .toList();

    expect(questions.map((question) => question.questionId), expectedIds);
    expect(
      questions.map((question) => question.questionId).toSet(),
      hasLength(40),
    );
    expect(bubbles, hasLength(160));
  });

  test('PDF plan consumes exact dense PageLayout bubble geometry', () {
    final inputs = buildP13_6DenseValidationInputs();
    final plan = PdfEngine().buildPlan(inputs.template, inputs.layout).value;
    final scannerContext = CameraScanContext(
      template: inputs.template,
      pageLayout: inputs.layout.pages.single,
      templateId: inputs.template.id,
      templateVersion: inputs.template.version,
      pageId: inputs.layout.pages.single.pageId,
      scannerConfig: ScannerConfig(),
      candidatePageLayouts: inputs.layout.pages,
    );

    expect(plan.pages, hasLength(inputs.layout.pages.length));
    for (var index = 0; index < plan.pages.length; index++) {
      expect(plan.pages[index].layout, same(inputs.layout.pages[index]));
      expect(
        plan.pages[index].bubbles,
        inputs.layout.pages[index].bubbleRegions,
      );
    }
    expect(scannerContext.pageLayout, same(inputs.layout.pages.single));
    expect(scannerContext.pageLayout.bubbleRegions, plan.pages.single.bubbles);
  });

  test(
    'dense validation PDF generation succeeds with matching page count',
    () async {
      final inputs = buildP13_6DenseValidationInputs();
      final result = await PdfEngine().render(inputs.template, inputs.layout);

      expect(result.isSuccess, isTrue);
      expect(result.value, isNotEmpty);
      expect(inputs.layout.pages, hasLength(1));
      expect(_pdfPageCount(result.value), inputs.layout.pages.length);
    },
  );
}

void _expectNoOverlap(PageLayout page) {
  final leadRegions = page.sectionRegions.expand(
    (section) => [
      section.titleRegion,
      section.instructionRegion,
      section.humanReadableFieldRegion,
    ].whereType<ContentRegion>(),
  );
  for (var first = 0; first < page.questionRegions.length; first++) {
    final question = page.questionRegions[first];
    expect(page.safeBounds.containsRect(question.physicalBounds), isTrue);
    for (
      var second = first + 1;
      second < page.questionRegions.length;
      second++
    ) {
      expect(
        question.physicalBounds.intersects(
          page.questionRegions[second].physicalBounds,
        ),
        isFalse,
      );
    }
    for (final marker in page.markerRegions) {
      expect(
        question.physicalBounds.intersects(marker.physicalBounds),
        isFalse,
      );
    }
    for (final lead in leadRegions) {
      expect(question.physicalBounds.intersects(lead.physicalBounds), isFalse);
    }
  }
  for (var first = 0; first < page.bubbleRegions.length; first++) {
    for (var second = first + 1; second < page.bubbleRegions.length; second++) {
      expect(
        page.bubbleRegions[first].physicalBounds.intersects(
          page.bubbleRegions[second].physicalBounds,
        ),
        isFalse,
      );
    }
  }
}

int _pdfPageCount(List<int> bytes) => RegExp(
  r'/Type\s*/Page\b',
).allMatches(latin1.decode(bytes, allowInvalid: true)).length;
