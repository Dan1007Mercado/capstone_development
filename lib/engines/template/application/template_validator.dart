import '../../../core/result/validation.dart';
import '../domain/numeric_grid_spec.dart';
import '../domain/question_type.dart';
import '../domain/template_definition.dart';
import '../domain/template_option.dart';
import '../domain/template_question.dart';
import '../domain/template_status.dart';

/// Validates cross-object rules for one semantic template version.
final class TemplateValidator {
  ValidationResult validate(TemplateDefinition template) {
    final issues = <ValidationIssue>[];

    if (template.name.trim().isEmpty) {
      issues.add(
        _error('TEMPLATE_NAME_EMPTY', 'Template name is required.', 'name'),
      );
    }
    if (template.sections.isEmpty) {
      issues.add(
        _error('NO_SECTIONS', 'At least one section is required.', 'sections'),
      );
    }

    final sectionIds = <Object>{};
    final questionIds = <Object>{};
    for (
      var sectionIndex = 0;
      sectionIndex < template.sections.length;
      sectionIndex++
    ) {
      final section = template.sections[sectionIndex];
      final sectionPath = 'sections[$sectionIndex]';

      if (!sectionIds.add(section.id)) {
        issues.add(
          _error(
            'DUPLICATE_SECTION_ID',
            'Section IDs must be unique within a template.',
            '$sectionPath.id',
          ),
        );
      }
      if (section.title.trim().isEmpty) {
        issues.add(
          _error(
            'SECTION_TITLE_EMPTY',
            'Section title is required.',
            '$sectionPath.title',
          ),
        );
      }
      final textField = section.humanReadableTextField;
      if (textField != null && textField.label.trim().isEmpty) {
        issues.add(
          _error(
            'TEXT_FIELD_LABEL_EMPTY',
            'Human-readable text field label is required.',
            '$sectionPath.humanReadableTextField.label',
          ),
        );
      }

      for (
        var questionIndex = 0;
        questionIndex < section.questions.length;
        questionIndex++
      ) {
        final question = section.questions[questionIndex];
        final questionPath = '$sectionPath.questions[$questionIndex]';

        if (!questionIds.add(question.id)) {
          issues.add(
            _error(
              'DUPLICATE_QUESTION_ID',
              'Question IDs must be unique across the template.',
              '$questionPath.id',
            ),
          );
        }
        _validateQuestion(question, questionPath, issues);
      }
    }

    if (template.status == TemplateStatus.published &&
        issues.any((issue) => issue.severity == ValidationSeverity.error)) {
      issues.add(
        _error(
          'INVALID_PUBLISHED_TEMPLATE',
          'A published template must satisfy all template rules.',
          'status',
        ),
      );
    }

    return ValidationResult(issues);
  }

  void _validateQuestion(
    TemplateQuestion question,
    String path,
    List<ValidationIssue> issues,
  ) {
    if (question.prompt.trim().isEmpty) {
      issues.add(
        _error(
          'QUESTION_PROMPT_EMPTY',
          'Question prompt is required.',
          '$path.prompt',
        ),
      );
    }

    final optionIds = <Object>{};
    for (
      var optionIndex = 0;
      optionIndex < question.options.length;
      optionIndex++
    ) {
      final option = question.options[optionIndex];
      final optionPath = '$path.options[$optionIndex]';
      if (!optionIds.add(option.id)) {
        issues.add(
          _error(
            'DUPLICATE_OPTION_ID',
            'Option IDs must be unique within a question.',
            '$optionPath.id',
          ),
        );
      }
      _validateOption(option, optionPath, issues);
    }

    switch (question.type) {
      case QuestionType.singleChoice:
        _requireMinimumOptions(question, path, issues, 'INVALID_SINGLE_CHOICE');
        _rejectNumericGridSpec(question, path, issues);
        break;
      case QuestionType.multipleChoice:
        _requireMinimumOptions(
          question,
          path,
          issues,
          'INVALID_MULTIPLE_CHOICE',
        );
        _rejectNumericGridSpec(question, path, issues);
        break;
      case QuestionType.likert:
        _validateLikert(question, path, issues);
        _rejectNumericGridSpec(question, path, issues);
        break;
      case QuestionType.yesNo:
        if (question.options.length != 2) {
          issues.add(
            _error(
              'INVALID_YES_NO',
              'Yes/no questions require exactly two options.',
              '$path.options',
            ),
          );
        }
        _rejectNumericGridSpec(question, path, issues);
        break;
      case QuestionType.numericGrid:
        _validateNumericGrid(question, path, issues);
        break;
    }
  }

  void _validateOption(
    TemplateOption option,
    String path,
    List<ValidationIssue> issues,
  ) {
    if (option.label.trim().isEmpty) {
      issues.add(
        _error(
          'OPTION_LABEL_EMPTY',
          'Option label is required.',
          '$path.label',
        ),
      );
    }
  }

  void _requireMinimumOptions(
    TemplateQuestion question,
    String path,
    List<ValidationIssue> issues,
    String code,
  ) {
    if (question.options.length < 2) {
      issues.add(
        _error(
          code,
          'Question requires at least two options.',
          '$path.options',
        ),
      );
    }
  }

  void _validateLikert(
    TemplateQuestion question,
    String path,
    List<ValidationIssue> issues,
  ) {
    if (question.options.length < 2) {
      issues.add(
        _error(
          'INVALID_LIKERT',
          'Likert questions require at least two ordered options.',
          '$path.options',
        ),
      );
      return;
    }

    final valuedOptions = question.options
        .where((option) => option.value != null)
        .toList(growable: false);
    if (valuedOptions.isNotEmpty &&
        valuedOptions.length != question.options.length) {
      issues.add(
        _error(
          'INVALID_LIKERT',
          'Likert semantic values must be supplied for all options or none.',
          '$path.options',
        ),
      );
    } else if (valuedOptions.length == question.options.length &&
        valuedOptions.map((option) => option.value).toSet().length !=
            valuedOptions.length) {
      issues.add(
        _error(
          'INVALID_LIKERT',
          'Likert semantic values must be unique.',
          '$path.options',
        ),
      );
    }
  }

  void _validateNumericGrid(
    TemplateQuestion question,
    String path,
    List<ValidationIssue> issues,
  ) {
    final spec = question.numericGridSpec;
    if (question.options.isNotEmpty ||
        spec == null ||
        !_isValidGridSpec(spec)) {
      issues.add(
        _error(
          'INVALID_NUMERIC_GRID',
          'Numeric grids require no options, a positive column count, and '
              'unique allowed digits from 0 through 9.',
          '$path.numericGridSpec',
        ),
      );
    }
  }

  bool _isValidGridSpec(NumericGridSpec spec) =>
      spec.columnCount > 0 &&
      spec.allowedDigits.isNotEmpty &&
      spec.allowedDigits.every((digit) => digit >= 0 && digit <= 9) &&
      spec.allowedDigits.toSet().length == spec.allowedDigits.length;

  void _rejectNumericGridSpec(
    TemplateQuestion question,
    String path,
    List<ValidationIssue> issues,
  ) {
    if (question.numericGridSpec != null) {
      issues.add(
        _error(
          'INCONSISTENT_QUESTION_STRUCTURE',
          'Only numeric-grid questions may define a numeric grid specification.',
          '$path.numericGridSpec',
        ),
      );
    }
  }

  ValidationIssue _error(String code, String message, String path) =>
      ValidationIssue(
        code: code,
        message: message,
        severity: ValidationSeverity.error,
        path: path,
      );
}
