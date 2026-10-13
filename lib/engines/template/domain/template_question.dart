import 'dart:collection';

import '../../../core/ids/identifiers.dart';
import 'numeric_grid_spec.dart';
import 'question_type.dart';
import 'template_option.dart';
import 'value_equality.dart';

/// One immutable semantic question, independent of page geometry.
final class TemplateQuestion {
  TemplateQuestion({
    required this.id,
    required this.type,
    required this.prompt,
    Iterable<TemplateOption> options = const [],
    this.required = false,
    this.description,
    this.numericGridSpec,
  }) : options = UnmodifiableListView(List.of(options));

  factory TemplateQuestion.yesNo({
    required QuestionId id,
    required String prompt,
    required OptionId yesOptionId,
    required OptionId noOptionId,
    bool required = false,
    String yesLabel = 'Yes',
    String noLabel = 'No',
    String? description,
  }) => TemplateQuestion(
    id: id,
    type: QuestionType.yesNo,
    prompt: prompt,
    required: required,
    description: description,
    options: [
      TemplateOption(id: yesOptionId, label: yesLabel, value: true),
      TemplateOption(id: noOptionId, label: noLabel, value: false),
    ],
  );

  factory TemplateQuestion.numericGrid({
    required QuestionId id,
    required String prompt,
    required NumericGridSpec spec,
    bool required = false,
    String? description,
  }) => TemplateQuestion(
    id: id,
    type: QuestionType.numericGrid,
    prompt: prompt,
    required: required,
    description: description,
    numericGridSpec: spec,
  );

  final QuestionId id;
  final QuestionType type;
  final String prompt;
  final List<TemplateOption> options;
  final bool required;
  final String? description;
  final NumericGridSpec? numericGridSpec;

  TemplateQuestion copyWith({
    QuestionType? type,
    String? prompt,
    Iterable<TemplateOption>? options,
    bool? required,
    Object? description = _unchanged,
    Object? numericGridSpec = _unchanged,
  }) => TemplateQuestion(
    id: id,
    type: type ?? this.type,
    prompt: prompt ?? this.prompt,
    options: options ?? this.options,
    required: required ?? this.required,
    description: identical(description, _unchanged)
        ? this.description
        : description as String?,
    numericGridSpec: identical(numericGridSpec, _unchanged)
        ? this.numericGridSpec
        : numericGridSpec as NumericGridSpec?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemplateQuestion &&
          other.id == id &&
          other.type == type &&
          other.prompt == prompt &&
          listEqualsByValue(other.options, options) &&
          other.required == required &&
          other.description == description &&
          other.numericGridSpec == numericGridSpec;

  @override
  int get hashCode => Object.hash(
    id,
    type,
    prompt,
    Object.hashAll(options),
    required,
    description,
    numericGridSpec,
  );

  static const Object _unchanged = Object();
}
