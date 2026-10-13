import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/template/domain/numeric_grid_spec.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:capstone_development/engines/template/domain/template_section.dart';
import 'package:capstone_development/engines/template/domain/template_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_test_fixtures.dart';

void main() {
  for (final type in [
    QuestionType.singleChoice,
    QuestionType.multipleChoice,
    QuestionType.likert,
  ]) {
    test('${type.name} bubbles preserve semantic option order', () {
      final question = choiceQuestion('ordered', type: type, optionCount: 4);
      final layout = buildLayout(templateWithQuestions([question]));
      final region = layout.pages.first.questionRegions.single;

      expect(
        region.bubbleRegions.map((bubble) => bubble.optionId),
        question.options.map((option) => option.id),
      );
    });
  }

  test('yes/no produces exactly two ordered option bubbles', () {
    final question = TemplateQuestion.yesNo(
      id: QuestionId('yes-no'),
      prompt: 'Agree?',
      yesOptionId: OptionId('yes'),
      noOptionId: OptionId('no'),
    );
    final region = buildLayout(
      templateWithQuestions([question]),
    ).pages.first.questionRegions.single;

    expect(region.bubbleRegions, hasLength(2));
    expect(region.bubbleRegions.map((bubble) => bubble.optionId), [
      OptionId('yes'),
      OptionId('no'),
    ]);
  });

  test('numeric grid creates columns times allowed digits bubbles', () {
    final question = TemplateQuestion.numericGrid(
      id: QuestionId('grid'),
      prompt: 'Code',
      spec: NumericGridSpec(columnCount: 4, allowedDigits: [1, 3, 5]),
    );
    final region = buildLayout(
      templateWithQuestions([question]),
    ).pages.first.questionRegions.single;

    expect(region.bubbleRegions, hasLength(12));
  });

  test('numeric grid uses deterministic column-major semantic mappings', () {
    final question = TemplateQuestion.numericGrid(
      id: QuestionId('grid'),
      prompt: 'Code',
      spec: NumericGridSpec(columnCount: 2, allowedDigits: [2, 4, 8]),
    );
    final bubbles = buildLayout(
      templateWithQuestions([question]),
    ).pages.first.bubbleRegions;

    expect(
      bubbles.map(
        (bubble) => (bubble.numericColumnIndex, bubble.numericDigitValue),
      ),
      [(0, 2), (0, 4), (0, 8), (1, 2), (1, 4), (1, 8)],
    );
  });

  test('question regions contain all their bubbles', () {
    final document = buildLayout(fullTemplate());

    for (final page in document.pages) {
      for (final question in page.questionRegions) {
        for (final bubble in question.bubbleRegions) {
          expect(
            question.physicalBounds.containsRect(bubble.physicalBounds),
            isTrue,
          );
        }
      }
    }
  });

  test('section and question order is preserved', () {
    final first = TemplateSection(
      id: SectionId('first'),
      title: 'First',
      questions: [choiceQuestion('q1'), choiceQuestion('q2')],
    );
    final second = TemplateSection(
      id: SectionId('second'),
      title: 'Second',
      questions: [choiceQuestion('q3')],
    );
    final template = TemplateDefinition(
      id: TemplateId('ordered'),
      version: TemplateVersion(1),
      name: 'Ordered',
      status: TemplateStatus.draft,
      sections: [first, second],
    );
    final pages = buildLayout(template).pages;

    expect(
      pages
          .expand((page) => page.sectionRegions)
          .map((region) => region.sectionId),
      [SectionId('first'), SectionId('second')],
    );
    expect(
      pages
          .expand((page) => page.questionRegions)
          .map((region) => region.questionId),
      [QuestionId('q1'), QuestionId('q2'), QuestionId('q3')],
    );
  });

  test('no bubble overlaps a marker', () {
    final document = buildLayout(fullTemplate());

    for (final page in document.pages) {
      for (final bubble in page.bubbleRegions) {
        for (final marker in page.markerRegions) {
          expect(
            bubble.physicalBounds.intersects(marker.physicalBounds),
            isFalse,
          );
        }
      }
    }
  });

  test('no two bubble regions overlap', () {
    final document = buildLayout(fullTemplate());

    for (final page in document.pages) {
      for (var first = 0; first < page.bubbleRegions.length; first++) {
        for (
          var second = first + 1;
          second < page.bubbleRegions.length;
          second++
        ) {
          expect(
            page.bubbleRegions[first].physicalBounds.intersects(
              page.bubbleRegions[second].physicalBounds,
            ),
            isFalse,
          );
        }
      }
    }
  });

  test('all bubbles remain inside safe and printable bounds', () {
    final document = buildLayout(fullTemplate());

    for (final page in document.pages) {
      for (final bubble in page.bubbleRegions) {
        expect(page.safeBounds.containsRect(bubble.physicalBounds), isTrue);
        expect(
          page.printableBounds.containsRect(bubble.physicalBounds),
          isTrue,
        );
      }
    }
  });

  test('every bubble maps to exactly one semantic target kind', () {
    final document = buildLayout(fullTemplate());

    for (final bubble in document.pages.expand((page) => page.bubbleRegions)) {
      expect(bubble.isOptionTarget ^ bubble.isNumericCellTarget, isTrue);
      expect(bubble.questionId.value, isNotEmpty);
    }
  });

  test('every bubble exposes physical and normalized scanner geometry', () {
    final bubbles = buildLayout(
      fullTemplate(),
    ).pages.expand((page) => page.bubbleRegions);

    for (final bubble in bubbles) {
      expect(bubble.physicalBounds.width.millimeters, greaterThan(0));
      expect(bubble.physicalDiameter.millimeters, greaterThan(0));
      expect(bubble.normalizedBounds.width.value, greaterThan(0));
      expect(bubble.normalizedCenter.x.value, inInclusiveRange(0, 1));
    }
  });
}
