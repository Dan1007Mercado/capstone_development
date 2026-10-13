import 'dart:io';

import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/template/domain/numeric_grid_spec.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_content.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/domain/template_option.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:capstone_development/engines/template/domain/template_section.dart';
import 'package:capstone_development/engines/template/domain/template_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('question construction', () {
    test('creates a valid single-choice question', () {
      final question = _choiceQuestion(
        id: 'single',
        type: QuestionType.singleChoice,
      );

      expect(question.type, QuestionType.singleChoice);
      expect(question.options, hasLength(2));
    });

    test('creates a valid multiple-choice question', () {
      final question = _choiceQuestion(
        id: 'multiple',
        type: QuestionType.multipleChoice,
      );

      expect(question.type, QuestionType.multipleChoice);
      expect(question.required, isFalse);
    });

    test('creates an ordered Likert question with semantic values', () {
      final question = TemplateQuestion(
        id: QuestionId('likert'),
        type: QuestionType.likert,
        prompt: 'Rate this service.',
        options: [
          TemplateOption(id: OptionId('low'), label: 'Low', value: 1),
          TemplateOption(id: OptionId('high'), label: 'High', value: 5),
        ],
      );

      expect(question.options.map((option) => option.value), [1, 5]);
    });

    test('creates yes/no options safely', () {
      final question = TemplateQuestion.yesNo(
        id: QuestionId('yes-no'),
        prompt: 'Do you agree?',
        yesOptionId: OptionId('yes'),
        noOptionId: OptionId('no'),
      );

      expect(question.type, QuestionType.yesNo);
      expect(question.options.map((option) => option.label), ['Yes', 'No']);
      expect(question.options.map((option) => option.value), [true, false]);
    });

    test('creates a semantic numeric grid without physical cells', () {
      final question = TemplateQuestion.numericGrid(
        id: QuestionId('student-number'),
        prompt: 'Student number',
        spec: NumericGridSpec(columnCount: 8),
      );

      expect(question.type, QuestionType.numericGrid);
      expect(question.options, isEmpty);
      expect(question.numericGridSpec!.columnCount, 8);
      expect(question.numericGridSpec!.allowedDigits, [
        0,
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
      ]);
    });

    test('preserves option order', () {
      final question = _choiceQuestion(
        id: 'ordered',
        type: QuestionType.singleChoice,
      );

      expect(question.options.map((option) => option.id.value), [
        'ordered-a',
        'ordered-b',
      ]);
    });

    test('rejects mutable or non-finite semantic values', () {
      expect(
        () => TemplateOption(
          id: OptionId('bad'),
          label: 'Bad',
          value: <String>[],
        ),
        throwsArgumentError,
      );
      expect(
        () => TemplateOption(
          id: OptionId('nan'),
          label: 'NaN',
          value: double.nan,
        ),
        throwsArgumentError,
      );
    });
  });

  group('ordering and immutability', () {
    test('preserves question order', () {
      final first = _choiceQuestion(id: 'q1', type: QuestionType.singleChoice);
      final second = _choiceQuestion(
        id: 'q2',
        type: QuestionType.multipleChoice,
      );
      final section = TemplateSection(
        id: SectionId('section'),
        title: 'Section',
        questions: [first, second],
      );

      expect(section.questions.map((question) => question.id.value), [
        'q1',
        'q2',
      ]);
    });

    test('preserves section order', () {
      final template = _template(
        sections: [_section('first', 'First'), _section('second', 'Second')],
      );

      expect(template.sections.map((section) => section.id.value), [
        'first',
        'second',
      ]);
    });

    test('defensively copies every exposed collection', () {
      final options = <TemplateOption>[
        TemplateOption(id: OptionId('a'), label: 'A'),
        TemplateOption(id: OptionId('b'), label: 'B'),
      ];
      final question = TemplateQuestion(
        id: QuestionId('q'),
        type: QuestionType.singleChoice,
        prompt: 'Question',
        options: options,
      );
      final questions = <TemplateQuestion>[question];
      final section = TemplateSection(
        id: SectionId('section'),
        title: 'Section',
        questions: questions,
      );
      final sections = <TemplateSection>[section];
      final template = _template(sections: sections);
      final digits = <int>[0, 1];
      final grid = NumericGridSpec(columnCount: 2, allowedDigits: digits);

      options.clear();
      questions.clear();
      sections.clear();
      digits.clear();

      expect(question.options, hasLength(2));
      expect(section.questions, hasLength(1));
      expect(template.sections, hasLength(1));
      expect(grid.allowedDigits, [0, 1]);
      expect(
        () =>
            question.options.add(TemplateOption(id: OptionId('c'), label: 'C')),
        throwsUnsupportedError,
      );
      expect(() => section.questions.clear(), throwsUnsupportedError);
      expect(() => template.sections.clear(), throwsUnsupportedError);
      expect(() => grid.allowedDigits.add(2), throwsUnsupportedError);
    });
  });

  group('template lifecycle', () {
    test('copying a draft preserves the original', () {
      final original = _template(name: 'Original');
      final updated = original.copyWith(name: 'Updated');

      expect(original.name, 'Original');
      expect(updated.name, 'Updated');
      expect(updated.id, original.id);
      expect(updated.version, original.version);
    });

    test('TemplateId and TemplateVersion identify stable versions', () {
      final first = _template(version: 1);
      final second = _template(version: 2);

      expect(first.id, second.id);
      expect(first.version, isNot(second.version));
    });

    test('supports draft and published statuses', () {
      expect(_template().status, TemplateStatus.draft);
      expect(
        _template(status: TemplateStatus.published).status,
        TemplateStatus.published,
      );
    });

    test('published definitions require a higher-version draft revision', () {
      final published = _template(status: TemplateStatus.published);

      expect(() => published.copyWith(name: 'Changed'), throwsStateError);
      expect(
        () => published.createDraftRevision(TemplateVersion(1)),
        throwsArgumentError,
      );

      final revision = published.createDraftRevision(TemplateVersion(2));
      expect(revision.id, published.id);
      expect(revision.version, TemplateVersion(2));
      expect(revision.status, TemplateStatus.draft);
      expect(published.status, TemplateStatus.published);
    });

    test('supports minimal non-question section content', () {
      final field = HumanReadableTextField(
        label: 'Respondent name',
        instruction: 'Write clearly.',
      );
      final section = TemplateSection(
        id: SectionId('identity'),
        title: 'Identity',
        instruction: 'Complete before answering.',
        humanReadableTextField: field,
      );

      expect(section.instruction, 'Complete before answering.');
      expect(section.humanReadableTextField, same(field));
    });
  });

  test('template domain source has no geometry or platform dependencies', () {
    final domainFiles = Directory(
      'lib/engines/template/domain',
    ).listSync().whereType<File>();
    final source = domainFiles
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(source, isNot(contains('core/geometry')));
    expect(source, isNot(contains('package:flutter')));
    expect(source, isNot(contains('firebase')));
    expect(source, isNot(contains('opencv')));
    expect(source, isNot(contains('camera')));
  });
}

TemplateQuestion _choiceQuestion({
  required String id,
  required QuestionType type,
}) => TemplateQuestion(
  id: QuestionId(id),
  type: type,
  prompt: 'Question $id',
  options: [
    TemplateOption(id: OptionId('$id-a'), label: 'A'),
    TemplateOption(id: OptionId('$id-b'), label: 'B'),
  ],
);

TemplateSection _section(String id, String title) => TemplateSection(
  id: SectionId(id),
  title: title,
  questions: [
    _choiceQuestion(id: '$id-question', type: QuestionType.singleChoice),
  ],
);

TemplateDefinition _template({
  String name = 'Survey',
  int version = 1,
  TemplateStatus status = TemplateStatus.draft,
  Iterable<TemplateSection>? sections,
}) => TemplateDefinition(
  id: TemplateId('survey'),
  version: TemplateVersion(version),
  name: name,
  status: status,
  sections: sections ?? [_section('section', 'Section')],
);
