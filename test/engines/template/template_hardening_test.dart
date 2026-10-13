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
  group('nullable copyWith semantics', () {
    test('template description is preserved when omitted', () {
      final original = _template(description: 'Original description');

      final copied = original.copyWith();

      expect(copied.description, 'Original description');
      expect(original.description, 'Original description');
    });

    test('template description can be explicitly cleared', () {
      final original = _template(description: 'Original description');

      final copied = original.copyWith(description: null);

      expect(copied.description, isNull);
      expect(original.description, 'Original description');
    });

    test('question description is preserved when omitted', () {
      final original = _question(description: 'Original instruction');

      final copied = original.copyWith();

      expect(copied.description, 'Original instruction');
      expect(original.description, 'Original instruction');
    });

    test('question description can be explicitly cleared', () {
      final original = _question(description: 'Original instruction');

      final copied = original.copyWith(description: null);

      expect(copied.description, isNull);
      expect(original.description, 'Original instruction');
    });

    test('question numeric-grid specification can be explicitly cleared', () {
      final spec = NumericGridSpec(columnCount: 4);
      final original = _question(numericGridSpec: spec);

      final copied = original.copyWith(numericGridSpec: null);

      expect(copied.numericGridSpec, isNull);
      expect(original.numericGridSpec, same(spec));
    });

    test('section instruction can be explicitly cleared', () {
      final original = _section(instruction: 'Read carefully.');

      final copied = original.copyWith(instruction: null);

      expect(copied.instruction, isNull);
      expect(original.instruction, 'Read carefully.');
    });

    test('section human-readable field can be explicitly cleared', () {
      const field = HumanReadableTextField(label: 'Respondent name');
      final original = _section(humanReadableTextField: field);

      final copied = original.copyWith(humanReadableTextField: null);

      expect(copied.humanReadableTextField, isNull);
      expect(original.humanReadableTextField, same(field));
    });

    test('option semantic value can still be explicitly cleared', () {
      final original = TemplateOption(
        id: OptionId('rated'),
        label: 'Rated',
        value: 5,
      );

      final copied = original.copyWith(value: null);

      expect(copied.value, isNull);
      expect(original.value, 5);
    });
  });

  group('publication protection', () {
    test('draft copyWith preserves draft status', () {
      final draft = _template();

      expect(draft.copyWith(name: 'Updated').status, TemplateStatus.draft);
    });

    test('copyWith has no ordinary path that publishes a draft', () {
      final dynamic draft = _template();

      expect(
        () => draft.copyWith(status: TemplateStatus.published),
        throwsNoSuchMethodError,
      );
    });

    test('published template rejects ordinary copy edits', () {
      final published = _template(status: TemplateStatus.published);

      expect(() => published.copyWith(name: 'Changed'), throwsStateError);
    });

    test('published template creates a higher-version draft revision', () {
      final published = _template(status: TemplateStatus.published);

      final revision = published.createDraftRevision(TemplateVersion(2));

      expect(revision.id, published.id);
      expect(revision.version, TemplateVersion(2));
      expect(revision.status, TemplateStatus.draft);
      expect(published.status, TemplateStatus.published);
    });

    test('same and lower revision versions are rejected', () {
      final published = _template(version: 2, status: TemplateStatus.published);

      expect(
        () => published.createDraftRevision(TemplateVersion(2)),
        throwsArgumentError,
      );
      expect(
        () => published.createDraftRevision(TemplateVersion(1)),
        throwsArgumentError,
      );
    });
  });

  group('structural equality', () {
    test('equal numeric-grid specifications have equal hashes', () {
      final first = NumericGridSpec(columnCount: 3, allowedDigits: [0, 1, 2]);
      final second = NumericGridSpec(columnCount: 3, allowedDigits: [0, 1, 2]);

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('allowed-digit order affects numeric-grid equality', () {
      final first = NumericGridSpec(columnCount: 3, allowedDigits: [0, 1, 2]);
      final reordered = NumericGridSpec(
        columnCount: 3,
        allowedDigits: [2, 1, 0],
      );

      expect(first, isNot(reordered));
    });

    test('equal options have equal hashes and value affects equality', () {
      final first = TemplateOption(
        id: OptionId('option'),
        label: 'Option',
        value: 1,
      );
      final equal = TemplateOption(
        id: OptionId('option'),
        label: 'Option',
        value: 1,
      );
      final differentValue = TemplateOption(
        id: OptionId('option'),
        label: 'Option',
        value: 2,
      );

      expect(first, equal);
      expect(first.hashCode, equal.hashCode);
      expect(first, isNot(differentValue));
    });

    test('equal human-readable fields have equal hashes', () {
      const first = HumanReadableTextField(
        label: 'Name',
        instruction: 'Print clearly.',
      );
      const second = HumanReadableTextField(
        label: 'Name',
        instruction: 'Print clearly.',
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('equal questions have equal hashes', () {
      final first = _question();
      final second = _question();

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('option order affects question equality', () {
      final options = _options('q');
      final first = _question(options: options);
      final reordered = _question(options: options.reversed);

      expect(first, isNot(reordered));
    });

    test('equal sections have equal hashes', () {
      final first = _section();
      final second = _section();

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('question order affects section equality', () {
      final firstQuestion = _question(id: 'first');
      final secondQuestion = _question(id: 'second');
      final first = _section(questions: [firstQuestion, secondQuestion]);
      final reordered = _section(questions: [secondQuestion, firstQuestion]);

      expect(first, isNot(reordered));
    });

    test('equal template definitions have equal hashes', () {
      final first = _template(description: 'Description');
      final second = _template(description: 'Description');

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('section order affects template equality', () {
      final firstSection = _section(id: 'first');
      final secondSection = _section(id: 'second');
      final first = _template(sections: [firstSection, secondSection]);
      final reordered = _template(sections: [secondSection, firstSection]);

      expect(first, isNot(reordered));
    });
  });
}

List<TemplateOption> _options(String questionId) => [
  TemplateOption(id: OptionId('$questionId-a'), label: 'A', value: 1),
  TemplateOption(id: OptionId('$questionId-b'), label: 'B', value: 2),
];

TemplateQuestion _question({
  String id = 'q',
  String? description,
  Iterable<TemplateOption>? options,
  NumericGridSpec? numericGridSpec,
}) => TemplateQuestion(
  id: QuestionId(id),
  type: QuestionType.singleChoice,
  prompt: 'Question $id',
  options: options ?? _options(id),
  required: true,
  description: description,
  numericGridSpec: numericGridSpec,
);

TemplateSection _section({
  String id = 'section',
  String? instruction,
  HumanReadableTextField? humanReadableTextField,
  Iterable<TemplateQuestion>? questions,
}) => TemplateSection(
  id: SectionId(id),
  title: 'Section $id',
  questions: questions ?? [_question(id: '$id-question')],
  instruction: instruction,
  humanReadableTextField: humanReadableTextField,
);

TemplateDefinition _template({
  int version = 1,
  String? description,
  TemplateStatus status = TemplateStatus.draft,
  Iterable<TemplateSection>? sections,
}) => TemplateDefinition(
  id: TemplateId('survey'),
  version: TemplateVersion(version),
  name: 'Survey',
  description: description,
  status: status,
  sections: sections ?? [_section()],
);
