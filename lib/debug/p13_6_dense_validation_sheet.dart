import 'dart:typed_data';

import '../core/ids/identifiers.dart';
import '../core/result/engine_result.dart';
import '../engines/layout/application/layout_engine.dart';
import '../engines/layout/domain/layout_config.dart';
import '../engines/layout/domain/page_layout.dart';
import '../engines/pdf/application/pdf_engine.dart';
import '../engines/template/application/template_validator.dart';
import '../engines/template/domain/question_type.dart';
import '../engines/template/domain/template_definition.dart';
import '../engines/template/domain/template_option.dart';
import '../engines/template/domain/template_question.dart';
import '../engines/template/domain/template_section.dart';
import '../engines/template/domain/template_status.dart';

const p13_6DenseValidationQuestionCount = 40;
const p13_6DenseValidationOutputPath =
    'debug_output/p13_6_dense_a4_validation.pdf';

TemplateDefinition buildP13_6DenseValidationTemplate({
  int questionCount = p13_6DenseValidationQuestionCount,
}) {
  final firstSectionCount = (questionCount / 2).ceil();
  return TemplateDefinition(
    id: TemplateId('p13-6-dense-a4-validation'),
    version: TemplateVersion(1),
    name: 'P13.6 Dense A4 Validation',
    description: 'Printable two-column OMR density validation fixture.',
    status: TemplateStatus.draft,
    sections: [
      TemplateSection(
        id: SectionId('dense-section-a'),
        title: 'SECTION A',
        questions: [
          for (var index = 0; index < firstSectionCount; index++)
            _denseQuestion(index),
        ],
      ),
      if (firstSectionCount < questionCount)
        TemplateSection(
          id: SectionId('dense-section-b'),
          title: 'SECTION B',
          questions: [
            for (var index = firstSectionCount; index < questionCount; index++)
              _denseQuestion(index),
          ],
        ),
    ],
  );
}

TemplateDefinition buildP13_6DenseMixedValidationTemplate() =>
    TemplateDefinition(
      id: TemplateId('p13-6-dense-mixed-validation'),
      version: TemplateVersion(1),
      name: 'P13.6 Dense Mixed Validation',
      description: 'Dense profile coverage for common compact question types.',
      status: TemplateStatus.draft,
      sections: [
        TemplateSection(
          id: SectionId('mixed-selection'),
          title: 'SELECTION',
          questions: [
            _typedQuestion('mixed-single-1', QuestionType.singleChoice, 4),
            _typedQuestion('mixed-single-2', QuestionType.singleChoice, 4),
            _typedQuestion('mixed-multiple-1', QuestionType.multipleChoice, 4),
            _typedQuestion('mixed-multiple-2', QuestionType.multipleChoice, 4),
          ],
        ),
        TemplateSection(
          id: SectionId('mixed-scales'),
          title: 'SCALES',
          questions: [
            _typedQuestion('mixed-likert-1', QuestionType.likert, 5),
            _typedQuestion('mixed-likert-2', QuestionType.likert, 5),
            TemplateQuestion.yesNo(
              id: QuestionId('mixed-yes-no-1'),
              prompt: 'Confirm the statement',
              yesOptionId: OptionId('mixed-yes-no-1-yes'),
              noOptionId: OptionId('mixed-yes-no-1-no'),
            ),
            TemplateQuestion.yesNo(
              id: QuestionId('mixed-yes-no-2'),
              prompt: 'Confirm the response',
              yesOptionId: OptionId('mixed-yes-no-2-yes'),
              noOptionId: OptionId('mixed-yes-no-2-no'),
            ),
          ],
        ),
      ],
    );

({TemplateDefinition template, LayoutDocument layout})
buildP13_6DenseValidationInputs({
  int questionCount = p13_6DenseValidationQuestionCount,
}) {
  final template = buildP13_6DenseValidationTemplate(
    questionCount: questionCount,
  );
  final validation = TemplateValidator().validate(template);
  if (!validation.isValid) {
    throw StateError(
      'P13.6 dense template is invalid: '
      '${validation.errors.map((issue) => issue.code).toList()}',
    );
  }
  // Keep the original dense-debug sheet as a stable two-column golden
  // reference even though production dense selection now prefers three.
  final layout = LayoutEngine().build(
    template,
    LayoutConfig.a4Dense().withFixedColumnCount(2),
  );
  if (layout.isFailure) {
    throw StateError('${layout.error.code}: ${layout.error.message}');
  }
  return (template: template, layout: layout.value);
}

Future<EngineResult<Uint8List>> renderP13_6DenseValidationPdf() {
  final inputs = buildP13_6DenseValidationInputs();
  return PdfEngine().render(inputs.template, inputs.layout);
}

TemplateQuestion _denseQuestion(int zeroBasedIndex) {
  final number = zeroBasedIndex + 1;
  final id = 'dense-q${number.toString().padLeft(2, '0')}';
  return TemplateQuestion(
    id: QuestionId(id),
    type: QuestionType.singleChoice,
    prompt: 'Q${number.toString().padLeft(2, '0')}: Select one response',
    options: [
      for (var optionIndex = 0; optionIndex < 4; optionIndex++)
        TemplateOption(
          id: OptionId('$id-${optionIndex + 1}'),
          label: String.fromCharCode(65 + optionIndex),
        ),
    ],
  );
}

TemplateQuestion _typedQuestion(
  String id,
  QuestionType type,
  int optionCount,
) => TemplateQuestion(
  id: QuestionId(id),
  type: type,
  prompt: 'Select the appropriate response',
  options: [
    for (var index = 0; index < optionCount; index++)
      TemplateOption(
        id: OptionId('$id-${index + 1}'),
        label: String.fromCharCode(65 + index),
        value: type == QuestionType.likert ? index + 1 : null,
      ),
  ],
);
