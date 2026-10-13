import 'dart:collection';

import '../../../core/ids/identifiers.dart';
import 'template_content.dart';
import 'template_question.dart';

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
    String? instruction,
    HumanReadableTextField? humanReadableTextField,
  }) => TemplateSection(
    id: id,
    title: title ?? this.title,
    questions: questions ?? this.questions,
    instruction: instruction ?? this.instruction,
    humanReadableTextField:
        humanReadableTextField ?? this.humanReadableTextField,
  );
}
