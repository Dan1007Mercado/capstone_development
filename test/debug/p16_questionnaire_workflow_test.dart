import 'dart:typed_data';

import 'package:capstone_development/application/published_templates/in_memory_published_template_artifact_repository.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact_service.dart';
import 'package:capstone_development/application/template_builder/template_builder_controller.dart';
import 'package:capstone_development/application/template_builder/template_pdf_exporter.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/debug/p12_template_builder_screen.dart';
import 'package:capstone_development/debug/packet_pdf_preview_screen.dart';
import 'package:capstone_development/engines/pdf/domain/pdf_units.dart';
import 'package:capstone_development/engines/pdf/domain/questionnaire_pdf_plan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'published questionnaire generates, previews, and saves offline',
    (tester) async {
      final controller = TemplateBuilderController(name: 'Field Survey');
      final section = controller.addSection(title: 'General');
      controller.addQuestion(section, prompt: 'Choose one answer.');
      final publicationService = PublishedTemplateArtifactService(
        repository: InMemoryPublishedTemplateArtifactRepository(),
        pdfRenderer: (_, _) async =>
            EngineResult.success(Uint8List.fromList([37, 80, 68, 70])),
      );
      final renderer = _RecordingQuestionnaireRenderer();
      final previewer = _RecordingPreviewer();
      final exporter = _RecordingExporter();

      await tester.pumpWidget(
        MaterialApp(
          home: P12TemplateBuilderScreen(
            controller: controller,
            answerSheetPublicationService: publicationService,
            questionnaireRenderer: renderer.call,
            packetPreviewer: previewer,
            exporter: exporter,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _tapVisible(tester, const Key('publish-answer-sheet'));
      await tester.pumpAndSettle();
      await _tapVisible(tester, const Key('generate-questionnaire'));
      await tester.pumpAndSettle();

      expect(renderer.artifact, isNotNull);
      expect(
        find.byKey(const Key('questionnaire-generation-result')),
        findsOneWidget,
      );

      await _tapVisible(tester, const Key('preview-questionnaire'));
      expect(previewer.bytes, renderer.bytes);
      expect(previewer.fileName, 'field-survey-questionnaire-v1.pdf');

      await _tapVisible(tester, const Key('save-questionnaire'));
      await tester.pumpAndSettle();
      expect(exporter.bytes, renderer.bytes);
      expect(exporter.fileName, 'field-survey-questionnaire-v1.pdf');
      expect(
        find.byKey(const Key('questionnaire-save-outcome')),
        findsOneWidget,
      );
    },
  );
}

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key, skipOffstage: false);
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

final class _RecordingQuestionnaireRenderer {
  PublishedTemplateArtifact? artifact;
  final Uint8List bytes = Uint8List.fromList([37, 80, 68, 70, 45, 49, 54]);

  Future<EngineResult<QuestionnairePdfArtifact>> call(
    PublishedTemplateArtifact artifact,
  ) async {
    this.artifact = artifact;
    return EngineResult.success(
      QuestionnairePdfArtifact(
        plan: QuestionnairePdfPlan(
          templateId: artifact.templateId,
          templateVersion: artifact.templateVersion,
          pages: [
            QuestionnairePagePlan(
              pageNumber: 1,
              totalPageCount: 1,
              pageWidthPoints: 595,
              pageHeightPoints: 842,
              headerBounds: const PdfPointRect(
                left: 36,
                top: 36,
                width: 523,
                height: 50,
              ),
              footerBounds: const PdfPointRect(
                left: 36,
                top: 790,
                width: 523,
                height: 16,
              ),
              columns: const [
                PdfPointRect(left: 36, top: 92, width: 253, height: 690),
                PdfPointRect(left: 306, top: 92, width: 253, height: 690),
              ],
              text: const [],
            ),
          ],
        ),
        bytes: bytes,
      ),
    );
  }
}

final class _RecordingPreviewer implements PacketPdfPreviewer {
  Uint8List? bytes;
  String? fileName;

  @override
  Future<void> preview(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
    required String title,
  }) async {
    this.bytes = bytes;
    this.fileName = fileName;
  }
}

final class _RecordingExporter implements TemplatePdfExporter {
  Uint8List? bytes;
  String? fileName;

  @override
  Future<EngineResult<PdfExportOutcome>> export({
    required Uint8List bytes,
    required String suggestedFileName,
  }) async {
    this.bytes = bytes;
    fileName = suggestedFileName;
    return EngineResult.success(
      PdfExportOutcome.saved(
        fileName: suggestedFileName,
        byteCount: bytes.length,
        method: PdfExportMethod.systemSaveDialog,
        locationUri: Uri.parse('content://questionnaires/$suggestedFileName'),
      ),
    );
  }
}
