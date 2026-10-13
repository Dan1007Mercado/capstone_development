import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/core/result/validation.dart';
import 'package:capstone_development/engines/template/application/template_validator.dart';
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
  final validator = TemplateValidator();

  test('valid template returns no errors', () {
    final result = validator.validate(_validTemplate());

    expect(result.isValid, isTrue);
    expect(result.errors, isEmpty);
  });

  test('detects duplicate section IDs', () {
    final section = _section(id: 'duplicate');
    final result = validator.validate(_template(sections: [section, section]));

    _expectCode(result, 'DUPLICATE_SECTION_ID');
  });

  test('detects duplicate question IDs across sections', () {
    final first = _section(id: 'first', questionId: 'same-question');
    final second = _section(id: 'second', questionId: 'same-question');
    final result = validator.validate(_template(sections: [first, second]));

    _expectCode(result, 'DUPLICATE_QUESTION_ID');
  });

  test('detects duplicate option IDs within a question', () {
    final duplicateId = OptionId('same-option');
    final question = _question(
      options: [
        TemplateOption(id: duplicateId, label: 'First'),
        TemplateOption(id: duplicateId, label: 'Second'),
      ],
    );

    _expectCode(_validateQuestion(validator, question), 'DUPLICATE_OPTION_ID');
  });

  test('detects a blank template name', () {
    _expectCode(
      validator.validate(_template(name: '  ')),
      'TEMPLATE_NAME_EMPTY',
    );
  });

  test('detects a template with no sections', () {
    _expectCode(validator.validate(_template(sections: [])), 'NO_SECTIONS');
  });

  test('detects a blank section title', () {
    _expectCode(
      validator.validate(_template(sections: [_section(title: ' ')])),
      'SECTION_TITLE_EMPTY',
    );
  });

  test('detects a blank question prompt with a precise path', () {
    final result = _validateQuestion(validator, _question(prompt: '\t'));

    final issue = result.issues.singleWhere(
      (issue) => issue.code == 'QUESTION_PROMPT_EMPTY',
    );
    expect(issue.path, 'sections[0].questions[0].prompt');
  });

  test('detects a blank option label', () {
    final question = _question(
      options: [
        TemplateOption(id: OptionId('blank'), label: ' '),
        TemplateOption(id: OptionId('valid'), label: 'Valid'),
      ],
    );

    _expectCode(_validateQuestion(validator, question), 'OPTION_LABEL_EMPTY');
  });

  test('rejects single choice with one option', () {
    final question = _question(
      options: [TemplateOption(id: OptionId('only'), label: 'Only')],
    );

    _expectCode(
      _validateQuestion(validator, question),
      'INVALID_SINGLE_CHOICE',
    );
  });

  test('rejects multiple choice with one option', () {
    final question = _question(
      type: QuestionType.multipleChoice,
      options: [TemplateOption(id: OptionId('only'), label: 'Only')],
    );

    _expectCode(
      _validateQuestion(validator, question),
      'INVALID_MULTIPLE_CHOICE',
    );
  });

  test('rejects yes/no with an incorrect option count', () {
    final question = _question(
      type: QuestionType.yesNo,
      options: [TemplateOption(id: OptionId('yes'), label: 'Yes')],
    );

    _expectCode(_validateQuestion(validator, question), 'INVALID_YES_NO');
  });

  test('rejects Likert with fewer than two choices', () {
    final question = _question(
      type: QuestionType.likert,
      options: [TemplateOption(id: OptionId('one'), label: 'One', value: 1)],
    );

    _expectCode(_validateQuestion(validator, question), 'INVALID_LIKERT');
  });

  test('rejects inconsistent Likert semantic values', () {
    final question = _question(
      type: QuestionType.likert,
      options: [
        TemplateOption(id: OptionId('one'), label: 'One', value: 1),
        TemplateOption(id: OptionId('two'), label: 'Two'),
      ],
    );

    _expectCode(_validateQuestion(validator, question), 'INVALID_LIKERT');
  });

  test('rejects numeric grid with an invalid column count', () {
    final question = TemplateQuestion.numericGrid(
      id: QuestionId('grid'),
      prompt: 'Number',
      spec: NumericGridSpec(columnCount: 0),
    );

    _expectCode(_validateQuestion(validator, question), 'INVALID_NUMERIC_GRID');
  });

  test('rejects invalid numeric-grid allowed digits', () {
    final outOfRange = TemplateQuestion.numericGrid(
      id: QuestionId('grid'),
      prompt: 'Number',
      spec: NumericGridSpec(columnCount: 2, allowedDigits: [0, 10]),
    );
    final duplicates = TemplateQuestion.numericGrid(
      id: QuestionId('grid'),
      prompt: 'Number',
      spec: NumericGridSpec(columnCount: 2, allowedDigits: [0, 0]),
    );

    _expectCode(
      _validateQuestion(validator, outOfRange),
      'INVALID_NUMERIC_GRID',
    );
    _expectCode(
      _validateQuestion(validator, duplicates),
      'INVALID_NUMERIC_GRID',
    );
  });

  test('rejects inconsistent option structures', () {
    final gridWithOptions = TemplateQuestion(
      id: QuestionId('grid'),
      type: QuestionType.numericGrid,
      prompt: 'Number',
      options: [TemplateOption(id: OptionId('zero'), label: '0')],
      numericGridSpec: NumericGridSpec(columnCount: 2),
    );
    final choiceWithGrid = _question(
      numericGridSpec: NumericGridSpec(columnCount: 2),
    );

    _expectCode(
      _validateQuestion(validator, gridWithOptions),
      'INVALID_NUMERIC_GRID',
    );
    _expectCode(
      _validateQuestion(validator, choiceWithGrid),
      'INCONSISTENT_QUESTION_STRUCTURE',
    );
  });

  test('detects an invalid human-readable text field', () {
    final section = _section(
      textField: const HumanReadableTextField(label: ' '),
    );

    _expectCode(
      validator.validate(_template(sections: [section])),
      'TEXT_FIELD_LABEL_EMPTY',
    );
  });

  test('invalid published definitions receive a lifecycle issue', () {
    final result = validator.validate(
      _template(name: '', status: TemplateStatus.published),
    );

    _expectCode(result, 'TEMPLATE_NAME_EMPTY');
    _expectCode(result, 'INVALID_PUBLISHED_TEMPLATE');
  });

  test('warnings alone do not make a ValidationResult invalid', () {
    final result = ValidationResult([
      ValidationIssue(
        code: 'REVIEW_LABEL',
        message: 'Consider a clearer label.',
        severity: ValidationSeverity.warning,
      ),
    ]);

    expect(result.isValid, isTrue);
    expect(result.warnings, hasLength(1));
  });
}

void _expectCode(ValidationResult result, String code) {
  expect(result.issues.map((issue) => issue.code), contains(code));
}

ValidationResult _validateQuestion(
  TemplateValidator validator,
  TemplateQuestion question,
) => validator.validate(
  _template(
    sections: [
      TemplateSection(
        id: SectionId('section'),
        title: 'Section',
        questions: [question],
      ),
    ],
  ),
);

TemplateDefinition _validTemplate() => _template(
  sections: [
    TemplateSection(
      id: SectionId('section'),
      title: 'Section',
      questions: [
        _question(),
        _question(id: 'multiple', type: QuestionType.multipleChoice),
        _question(
          id: 'likert',
          type: QuestionType.likert,
          options: [
            TemplateOption(id: OptionId('low'), label: 'Low', value: 1),
            TemplateOption(id: OptionId('high'), label: 'High', value: 2),
          ],
        ),
        TemplateQuestion.yesNo(
          id: QuestionId('yes-no'),
          prompt: 'Agree?',
          yesOptionId: OptionId('yes'),
          noOptionId: OptionId('no'),
        ),
        TemplateQuestion.numericGrid(
          id: QuestionId('grid'),
          prompt: 'Number',
          spec: NumericGridSpec(columnCount: 4),
        ),
      ],
    ),
  ],
);

TemplateQuestion _question({
  String id = 'question',
  QuestionType type = QuestionType.singleChoice,
  String prompt = 'Question',
  Iterable<TemplateOption>? options,
  NumericGridSpec? numericGridSpec,
}) => TemplateQuestion(
  id: QuestionId(id),
  type: type,
  prompt: prompt,
  options:
      options ??
      [
        TemplateOption(id: OptionId('$id-a'), label: 'A'),
        TemplateOption(id: OptionId('$id-b'), label: 'B'),
      ],
  numericGridSpec: numericGridSpec,
);

TemplateSection _section({
  String id = 'section',
  String title = 'Section',
  String questionId = 'question',
  HumanReadableTextField? textField,
}) => TemplateSection(
  id: SectionId(id),
  title: title,
  questions: [_question(id: questionId)],
  humanReadableTextField: textField,
);

TemplateDefinition _template({
  String name = 'Survey',
  TemplateStatus status = TemplateStatus.draft,
  Iterable<TemplateSection>? sections,
}) => TemplateDefinition(
  id: TemplateId('survey'),
  version: TemplateVersion(1),
  name: name,
  status: status,
  sections: sections ?? [_section()],
);
