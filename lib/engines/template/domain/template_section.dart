import 'dart:collection';

import '../../../core/ids/identifiers.dart';
import 'template_content.dart';
import 'template_question.dart';
import 'value_equality.dart';

/// An ordered semantic group of questions and minimal non-OMR content.
final class TemplateSection {
  TemplateSection({
    required this.id,
    required this.title,
    Iterable<TemplateQuestion> questions = const [],
    this.instruction,
    this.humanReadableTextField,
  }) : questions = UnmodifiableListView(List.of(questions));

  final SectionId id;
  final String title;
  final List<TemplateQuestion> questions;
  final String? instruction;
  final HumanReadableTextField? humanReadableTextField;

  TemplateSection copyWith({
    String? title,
    Iterable<TemplateQuestion>? questions,
    Object? instruction = _unchanged,
    Object? humanReadableTextField = _unchanged,
  }) => TemplateSection(
    id: id,
    title: title ?? this.title,
    questions: questions ?? this.questions,
    instruction: identical(instruction, _unchanged)
        ? this.instruction
        : instruction as String?,
    humanReadableTextField: identical(humanReadableTextField, _unchanged)
        ? this.humanReadableTextField
        : humanReadableTextField as HumanReadableTextField?,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemplateSection &&
          other.id == id &&
          other.title == title &&
          listEqualsByValue(other.questions, questions) &&
          other.instruction == instruction &&
          other.humanReadableTextField == humanReadableTextField;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    Object.hashAll(questions),
    instruction,
    humanReadableTextField,
  );

  static const Object _unchanged = Object();
}
