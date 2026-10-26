import 'dart:collection';
import 'dart:typed_data';

import '../../../core/ids/identifiers.dart';
import 'pdf_units.dart';

enum QuestionnaireTextRole {
  title,
  documentInstruction,
  documentIdentity,
  sectionTitle,
  sectionInstruction,
  humanReadableField,
  questionPrompt,
  questionDescription,
  option,
  numericInstruction,
}

final class QuestionnaireTextPlacement {
  const QuestionnaireTextPlacement({
    required this.role,
    required this.text,
    required this.bounds,
    required this.fontSizePoints,
    required this.bold,
    this.sectionId,
    this.questionId,
    this.optionId,
    this.questionNumber,
    this.startsSection = false,
    this.startsQuestion = false,
  });

  final QuestionnaireTextRole role;
  final String text;
  final PdfPointRect bounds;
  final double fontSizePoints;
  final bool bold;
  final SectionId? sectionId;
  final QuestionId? questionId;
  final OptionId? optionId;
  final int? questionNumber;
  final bool startsSection;
  final bool startsQuestion;
}

final class QuestionnairePagePlan {
  QuestionnairePagePlan({
    required this.pageNumber,
    required this.totalPageCount,
    required this.pageWidthPoints,
    required this.pageHeightPoints,
    required this.headerBounds,
    required this.footerBounds,
    required Iterable<PdfPointRect> columns,
    required Iterable<QuestionnaireTextPlacement> text,
  }) : columns = UnmodifiableListView(List.of(columns)),
       text = UnmodifiableListView(List.of(text));

  final int pageNumber;
  final int totalPageCount;
  final double pageWidthPoints;
  final double pageHeightPoints;
  final PdfPointRect headerBounds;
  final PdfPointRect footerBounds;
  final List<PdfPointRect> columns;
  final List<QuestionnaireTextPlacement> text;
}

final class QuestionnairePdfPlan {
  QuestionnairePdfPlan({
    required this.templateId,
    required this.templateVersion,
    required Iterable<QuestionnairePagePlan> pages,
  }) : pages = UnmodifiableListView(List.of(pages));

  final TemplateId templateId;
  final TemplateVersion templateVersion;
  final List<QuestionnairePagePlan> pages;
}

final class QuestionnairePdfArtifact {
  QuestionnairePdfArtifact({required this.plan, required Uint8List bytes})
    : _bytes = Uint8List.fromList(bytes) {
    if (plan.pages.isEmpty || _bytes.isEmpty) {
      throw ArgumentError('Questionnaire artifacts require pages and bytes.');
    }
  }

  final QuestionnairePdfPlan plan;
  final Uint8List _bytes;

  TemplateId get templateId => plan.templateId;
  TemplateVersion get templateVersion => plan.templateVersion;
  Uint8List get bytes => Uint8List.fromList(_bytes);
}
