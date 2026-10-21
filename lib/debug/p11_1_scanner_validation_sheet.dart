import 'dart:typed_data';

import '../core/ids/identifiers.dart';
import '../core/result/engine_result.dart';
import '../engines/layout/application/layout_engine.dart';
import '../engines/layout/domain/layout_config.dart';
import '../engines/layout/domain/page_layout.dart';
import '../engines/pdf/application/pdf_engine.dart';
import '../engines/template/application/template_validator.dart';
import '../engines/template/domain/numeric_grid_spec.dart';
import '../engines/template/domain/question_type.dart';
import '../engines/template/domain/template_definition.dart';
import '../engines/template/domain/template_option.dart';
import '../engines/template/domain/template_question.dart';
import '../engines/template/domain/template_section.dart';
import '../engines/template/domain/template_status.dart';

const p11ScannerValidationSheetOutputPath =
    'debug_output/p11_1_scanner_validation_sheet.pdf';

({TemplateDefinition template, LayoutDocument layout})
buildP11ScannerValidationSheetInputs() {
  final template = buildP11ScannerValidationTemplate();
  final validation = TemplateValidator().validate(template);
  if (!validation.isValid) {
    throw StateError(
      'P11.1 validation template is invalid: '
      '${validation.errors.map((issue) => issue.code).toList()}',
    );
  }
  final layoutResult = LayoutEngine().build(template, LayoutConfig.a4Default());
  if (layoutResult.isFailure) {
    throw StateError(
      '${layoutResult.error.code}: ${layoutResult.error.message}',
    );
  }
  return (template: template, layout: layoutResult.value);
}

TemplateDefinition buildP11ScannerValidationTemplate() => TemplateDefinition(
  id: TemplateId('p11-1-scanner-validation'),
  version: TemplateVersion(1),
  name: 'P11.1 Scanner Validation Sheet',
  description: 'Performance and multi-semantics physical scanner fixture.',
  status: TemplateStatus.draft,
  sections: [
    TemplateSection(
      id: SectionId('section-likert'),
      title: 'SECTION A - Likert',
      questions: [
        _choice('q1', QuestionType.likert, 'Q1: Rate statement one', 5),
        _choice('q2', QuestionType.likert, 'Q2: Rate statement two', 5),
        _choice('q3', QuestionType.likert, 'Q3: Rate statement three', 5),
      ],
    ),
    TemplateSection(
      id: SectionId('section-single'),
      title: 'SECTION B - Single Choice',
      questions: [
        _choice('q4', QuestionType.singleChoice, 'Q4: Select one option', 4),
        _choice('q5', QuestionType.singleChoice, 'Q5: Select one option', 4),
      ],
    ),
    TemplateSection(
      id: SectionId('section-multiple'),
      title: 'SECTION C - Multiple Choice / Checklist',
      questions: [
        _choice(
          'q6',
          QuestionType.multipleChoice,
          'Q6: Select all that apply',
          5,
        ),
        _choice(
          'q7',
          QuestionType.multipleChoice,
          'Q7: Select all that apply',
          5,
        ),
      ],
    ),
    TemplateSection(
      id: SectionId('section-yes-no'),
      title: 'SECTION D - Yes / No',
      questions: [
        TemplateQuestion.yesNo(
          id: QuestionId('q8'),
          prompt: 'Q8: Confirm YES or NO',
          yesOptionId: OptionId('q8-yes'),
          noOptionId: OptionId('q8-no'),
        ),
        TemplateQuestion.yesNo(
          id: QuestionId('q9'),
          prompt: 'Q9: Confirm YES or NO',
          yesOptionId: OptionId('q9-yes'),
          noOptionId: OptionId('q9-no'),
        ),
      ],
    ),
    TemplateSection(
      id: SectionId('section-numeric'),
      title: 'SECTION E - Numeric Grid',
      questions: [
        TemplateQuestion.numericGrid(
          id: QuestionId('q10'),
          prompt: 'Q10: Fill one digit in each column',
          spec: NumericGridSpec(columnCount: 3),
        ),
      ],
    ),
  ],
);

TemplateQuestion _choice(
  String id,
  QuestionType type,
  String prompt,
  int optionCount,
) => TemplateQuestion(
  id: QuestionId(id),
  type: type,
  prompt: prompt,
  options: List.generate(
    optionCount,
    (index) => TemplateOption(
      id: OptionId('$id-${index + 1}'),
      label: String.fromCharCode(65 + index),
      value: type == QuestionType.likert ? index + 1 : null,
    ),
  ),
);

Future<EngineResult<Uint8List>> renderP11ScannerValidationSheetPdf() {
  final inputs = buildP11ScannerValidationSheetInputs();
  return PdfEngine().render(inputs.template, inputs.layout);
}
