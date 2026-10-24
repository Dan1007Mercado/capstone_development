import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/layout/application/layout_engine.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/domain/template_option.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:capstone_development/engines/template/domain/template_section.dart';
import 'package:capstone_development/engines/template/domain/template_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('answer rows keep a compact, non-overlapping number lane', () {
    final layout = LayoutEngine()
        .build(_mappingTemplate(), LayoutConfig.a4AnswerSheet())
        .value;

    for (final region in layout.pages.expand((page) => page.questionRegions)) {
      final firstBubble = region.bubbleRegions.first.physicalBounds;
      final numberBounds = region.promptRegion.physicalBounds;
      final gap = firstBubble.left.millimeters - numberBounds.right.millimeters;

      expect(gap, closeTo(1.5, 1e-9));
      expect(gap, inInclusiveRange(1.0, 2.0));
      expect(firstBubble.intersects(numberBounds), isFalse);
      expect(
        region.bubbleRegions.every(
          (bubble) => bubble.physicalDiameter.millimeters == 5,
        ),
        isTrue,
      );
    }
  });

  test('group transition preserves Q1-Q8 identity and numbering', () {
    final layout = LayoutEngine()
        .build(_mappingTemplate(), LayoutConfig.a4AnswerSheet())
        .value;
    final regions = layout.pages
        .expand((page) => page.questionRegions)
        .toList(growable: false);

    expect(regions.map((region) => region.questionNumber), [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
    ]);
    expect(regions[6].questionId, QuestionId('q7'));
    expect(regions[6].questionNumber, 7);
    expect(regions[7].questionId, QuestionId('q8'));
    expect(regions[7].questionNumber, 8);
    expect(
      regions.where((region) => region.answerGroupLabel != null),
      hasLength(2),
    );
    expect(regions[6].answerGroupLabel, isNull);
    expect(regions[7].answerGroupLabel, contains('MULTIPLE CHOICE'));
  });

  test('question numbering remains continuous across answer-sheet pages', () {
    final layout = LayoutEngine()
        .build(_largeTemplate(240), LayoutConfig.a4AnswerSheet())
        .value;
    final regions = layout.pages
        .expand((page) => page.questionRegions)
        .toList(growable: false);

    expect(layout.pages.length, greaterThan(1));
    expect(regions.map((region) => region.questionNumber), [
      for (var number = 1; number <= 240; number++) number,
    ]);
    for (final page in layout.pages.skip(1)) {
      final first = page.questionRegions.first;
      expect(first.questionId.value, 'q${first.questionNumber}');
      final previousPage = layout.pages[page.pageIndex - 1];
      expect(
        first.questionNumber,
        previousPage.questionRegions.last.questionNumber + 1,
      );
    }
  });
}

TemplateDefinition _mappingTemplate() => TemplateDefinition(
  id: TemplateId('p14-3-mapping'),
  version: TemplateVersion(1),
  name: 'P14.3 mapping regression',
  status: TemplateStatus.draft,
  sections: [
    TemplateSection(
      id: SectionId('responses'),
      title: 'RESPONSES',
      questions: [
        for (var number = 1; number <= 7; number++)
          _question(number, QuestionType.singleChoice),
        _question(8, QuestionType.multipleChoice),
      ],
    ),
  ],
);

TemplateDefinition _largeTemplate(int count) => TemplateDefinition(
  id: TemplateId('p14-3-multipage'),
  version: TemplateVersion(1),
  name: 'P14.3 multipage numbering',
  status: TemplateStatus.draft,
  sections: [
    TemplateSection(
      id: SectionId('responses'),
      title: 'RESPONSES',
      questions: [
        for (var number = 1; number <= count; number++)
          _question(number, QuestionType.singleChoice),
      ],
    ),
  ],
);

TemplateQuestion _question(int number, QuestionType type) => TemplateQuestion(
  id: QuestionId('q$number'),
  type: type,
  prompt: 'Question $number',
  options: [
    TemplateOption(id: OptionId('q$number-a'), label: 'A'),
    TemplateOption(id: OptionId('q$number-b'), label: 'B'),
  ],
);
