import 'package:capstone_development/core/geometry/page_spec.dart';
import 'package:capstone_development/core/geometry/physical_geometry.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/layout/application/layout_engine.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/template/domain/numeric_grid_spec.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/domain/template_option.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:capstone_development/engines/template/domain/template_section.dart';
import 'package:capstone_development/engines/template/domain/template_status.dart';

TemplateOption option(String id, [String? label]) =>
    TemplateOption(id: OptionId(id), label: label ?? id.toUpperCase());

TemplateQuestion choiceQuestion(
  String id, {
  QuestionType type = QuestionType.singleChoice,
  int optionCount = 3,
  String? prompt,
}) => TemplateQuestion(
  id: QuestionId(id),
  type: type,
  prompt: prompt ?? 'Question $id',
  options: [
    for (var index = 0; index < optionCount; index++)
      option('$id-option-$index'),
  ],
);

TemplateDefinition templateWithQuestions(
  List<TemplateQuestion> questions, {
  String templateId = 'survey',
  int version = 1,
}) => TemplateDefinition(
  id: TemplateId(templateId),
  version: TemplateVersion(version),
  name: 'Layout Survey',
  status: TemplateStatus.draft,
  sections: [
    TemplateSection(
      id: SectionId('section-1'),
      title: 'Section 1',
      questions: questions,
    ),
  ],
);

TemplateDefinition fullTemplate() => templateWithQuestions([
  choiceQuestion('single'),
  choiceQuestion('multiple', type: QuestionType.multipleChoice),
  TemplateQuestion(
    id: QuestionId('likert'),
    type: QuestionType.likert,
    prompt: 'Rate the service',
    options: [
      TemplateOption(id: OptionId('likert-1'), label: 'Low', value: 1),
      TemplateOption(id: OptionId('likert-2'), label: 'Medium', value: 2),
      TemplateOption(id: OptionId('likert-3'), label: 'High', value: 3),
    ],
  ),
  TemplateQuestion.yesNo(
    id: QuestionId('yes-no'),
    prompt: 'Do you agree?',
    yesOptionId: OptionId('yes'),
    noOptionId: OptionId('no'),
  ),
  TemplateQuestion.numericGrid(
    id: QuestionId('numeric'),
    prompt: 'Student number',
    spec: NumericGridSpec(columnCount: 4),
  ),
]);

LayoutConfig testConfig({
  PageSpec? pageSpec,
  PageMargins? margins,
  CanonicalPageSpec? canonicalPageSpec,
  double? markerSizeMm,
  double? markerInsetMm,
  MarkerIds? markerIds,
  double? bubbleDiameterMm,
  double? bubbleHorizontalGapMm,
  double? bubbleVerticalGapMm,
  double? optionCellWidthMm,
  double? questionVerticalGapMm,
  double? sectionGapMm,
  double? headerHeightMm,
  double? identityRegionHeightMm,
  double? minimumContentGapMm,
  double? estimatedLineHeightMm,
  int? estimatedCharactersPerLine,
  double? humanReadableFieldHeightMm,
}) {
  final defaults = LayoutConfig.a4Default();
  return LayoutConfig(
    pageSpec: pageSpec ?? defaults.pageSpec,
    margins: margins ?? defaults.margins,
    canonicalPageSpec: canonicalPageSpec ?? defaults.canonicalPageSpec,
    markerSizeMm: markerSizeMm ?? defaults.markerSizeMm,
    markerInsetMm: markerInsetMm ?? defaults.markerInsetMm,
    markerIds: markerIds ?? defaults.markerIds,
    bubbleDiameterMm: bubbleDiameterMm ?? defaults.bubbleDiameterMm,
    bubbleHorizontalGapMm:
        bubbleHorizontalGapMm ?? defaults.bubbleHorizontalGapMm,
    bubbleVerticalGapMm: bubbleVerticalGapMm ?? defaults.bubbleVerticalGapMm,
    optionCellWidthMm: optionCellWidthMm ?? defaults.optionCellWidthMm,
    questionVerticalGapMm:
        questionVerticalGapMm ?? defaults.questionVerticalGapMm,
    sectionGapMm: sectionGapMm ?? defaults.sectionGapMm,
    headerHeightMm: headerHeightMm ?? defaults.headerHeightMm,
    identityRegionHeightMm:
        identityRegionHeightMm ?? defaults.identityRegionHeightMm,
    minimumContentGapMm: minimumContentGapMm ?? defaults.minimumContentGapMm,
    estimatedLineHeightMm:
        estimatedLineHeightMm ?? defaults.estimatedLineHeightMm,
    estimatedCharactersPerLine:
        estimatedCharactersPerLine ?? defaults.estimatedCharactersPerLine,
    humanReadableFieldHeightMm:
        humanReadableFieldHeightMm ?? defaults.humanReadableFieldHeightMm,
  );
}

LayoutDocument buildLayout(
  TemplateDefinition template, {
  LayoutConfig? config,
}) => LayoutEngine().build(template, config ?? testConfig()).value;

TemplateDefinition longTemplate(int questionCount) => templateWithQuestions([
  for (var index = 0; index < questionCount; index++) choiceQuestion('q$index'),
]);

PageMargins impossibleMargins() => PageMargins(
  top: PhysicalLength(20),
  right: PhysicalLength(120),
  bottom: PhysicalLength(20),
  left: PhysicalLength(120),
);
