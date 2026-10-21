import '../core/ids/identifiers.dart';
import '../engines/template/domain/question_type.dart';
import '../engines/template/domain/template_definition.dart';
import '../engines/template/domain/template_option.dart';
import '../engines/template/domain/template_question.dart';
import '../engines/template/domain/template_section.dart';
import '../engines/template/domain/template_status.dart';

/// Twelve-question p14 fixture that deliberately crosses section boundaries
/// while remaining representative of a compact research form.
TemplateDefinition buildP14DenseFlowFixture() => TemplateDefinition(
  id: TemplateId('p14-adaptive-dense-flow'),
  version: TemplateVersion(1),
  name: 'P14 Adaptive Dense Flow',
  status: TemplateStatus.draft,
  sections: [
    TemplateSection(
      id: SectionId('p14-likert-a'),
      title: 'SECTION 1 - EXPERIENCE',
      questions: [
        for (var index = 1; index <= 4; index++)
          _likert('p14-q$index', 'Service statement $index'),
      ],
    ),
    TemplateSection(
      id: SectionId('p14-select-many'),
      title: 'SECTION 2 - SELECT MANY',
      questions: [
        _choice('p14-q5', QuestionType.multipleChoice),
        _choice('p14-q6', QuestionType.multipleChoice),
      ],
    ),
    TemplateSection(
      id: SectionId('p14-likert-b'),
      title: 'SECTION 3 - OUTCOMES',
      questions: [
        for (var index = 7; index <= 10; index++)
          _likert('p14-q$index', 'Outcome statement $index'),
      ],
    ),
    TemplateSection(
      id: SectionId('p14-true-false'),
      title: 'SECTION 4 - CONFIRMATION',
      questions: [
        _yesNo('p14-q11', 'The instructions were clear'),
        _yesNo('p14-q12', 'The form was easy to complete'),
      ],
    ),
  ],
);

/// Sixty-question mixed fixture used to exercise automatic multipage flow.
TemplateDefinition buildP14LargeMixedFixture({int questionCount = 60}) {
  final questions = <TemplateQuestion>[];
  for (var index = 1; index <= questionCount; index++) {
    final id = 'p14-large-q${index.toString().padLeft(2, '0')}';
    final prompt =
        'Research item $index asks for the participant response to this statement';
    questions.add(switch (index % 4) {
      0 => _yesNo(id, prompt),
      1 => _likert(id, prompt),
      2 => _choice(id, QuestionType.singleChoice, prompt: prompt),
      _ => _choice(id, QuestionType.multipleChoice, prompt: prompt),
    });
  }
  return TemplateDefinition(
    id: TemplateId('p14-large-mixed'),
    version: TemplateVersion(1),
    name: 'P14 Large Mixed Survey',
    status: TemplateStatus.draft,
    sections: [
      for (var sectionIndex = 0; sectionIndex < 6; sectionIndex++)
        TemplateSection(
          id: SectionId('p14-large-section-${sectionIndex + 1}'),
          title: 'SECTION ${sectionIndex + 1}',
          questions: questions
              .skip(sectionIndex * 10)
              .take(10)
              .toList(growable: false),
        ),
    ],
  );
}

TemplateQuestion _likert(String id, String prompt) => TemplateQuestion(
  id: QuestionId(id),
  type: QuestionType.likert,
  prompt: prompt,
  options: [
    for (var value = 1; value <= 5; value++)
      TemplateOption(id: OptionId('$id-$value'), label: '$value', value: value),
  ],
);

TemplateQuestion _choice(String id, QuestionType type, {String? prompt}) =>
    TemplateQuestion(
      id: QuestionId(id),
      type: type,
      prompt: prompt ?? 'Select every response that applies',
      options: [
        for (var index = 0; index < 4; index++)
          TemplateOption(
            id: OptionId('$id-${index + 1}'),
            label: String.fromCharCode(65 + index),
          ),
      ],
    );

TemplateQuestion _yesNo(String id, String prompt) => TemplateQuestion.yesNo(
  id: QuestionId(id),
  prompt: prompt,
  yesOptionId: OptionId('$id-yes'),
  noOptionId: OptionId('$id-no'),
);
