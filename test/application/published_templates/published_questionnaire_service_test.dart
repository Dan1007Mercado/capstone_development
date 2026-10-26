import 'dart:typed_data';

import 'package:capstone_development/application/published_templates/published_questionnaire_service.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/engines/layout/application/layout_engine.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/pdf/application/questionnaire_pdf_engine.dart';
import 'package:capstone_development/engines/pdf/domain/pdf_render_fonts.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/domain/template_option.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:capstone_development/engines/template/domain/template_section.dart';
import 'package:capstone_development/engines/template/domain/template_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  test(
    'questionnaire is bound to the exact published answer-sheet version',
    () async {
      final template = _publishedTemplate();
      final config = LayoutConfig.a4AnswerSheet();
      final layout = LayoutEngine().build(template, config).value;
      final published = PublishedTemplateArtifact(
        template: template,
        layoutProfile: config.profile,
        layout: layout,
        pdfBytes: Uint8List.fromList([37, 80, 68, 70]),
      );
      final service = PublishedQuestionnaireService(
        engine: QuestionnairePdfEngine(fontLoader: const _TestFontLoader()),
      );

      final result = await service.generate(published);

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      expect(result.value.templateId, published.templateId);
      expect(result.value.templateVersion, published.templateVersion);
      expect(result.value.plan.pages, isNotEmpty);
      expect(published.layout, same(layout));
      expect(published.pdfBytes, [37, 80, 68, 70]);
    },
  );
}

TemplateDefinition _publishedTemplate() => TemplateDefinition(
  id: TemplateId('publication-bound-questionnaire'),
  version: TemplateVersion(7),
  name: 'Published Questionnaire',
  status: TemplateStatus.published,
  sections: [
    TemplateSection(
      id: SectionId('published-section'),
      title: 'Published Section',
      questions: [
        TemplateQuestion(
          id: QuestionId('published-question'),
          type: QuestionType.singleChoice,
          prompt: 'Choose one response.',
          options: [
            TemplateOption(id: OptionId('published-a'), label: 'First'),
            TemplateOption(id: OptionId('published-b'), label: 'Second'),
          ],
        ),
      ],
    ),
  ],
);

final class _TestFontLoader implements PdfRenderFontLoader {
  const _TestFontLoader();

  @override
  Future<EngineResult<PdfRenderFonts>> load() async => EngineResult.success(
    PdfRenderFonts(regular: pw.Font.helvetica(), bold: pw.Font.helveticaBold()),
  );
}
