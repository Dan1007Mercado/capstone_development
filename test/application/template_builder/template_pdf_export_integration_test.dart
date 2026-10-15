import 'dart:convert';
import 'dart:io';

import 'package:capstone_development/application/template_builder/template_pdf_exporter.dart';
import 'package:capstone_development/debug/p12_template_builder_fixture.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'mixed builder pipeline renders Unicode and exports the exact artifact',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'talaan-builder-export-integration-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });

      final controller = buildP12MixedTemplateDemo();
      controller.updateName('Résumé – Survey');
      final firstSection = controller.snapshot.definition.sections.first;
      controller.updateSectionTitle(
        firstSection.id,
        'Impormasyon ng Respondent',
      );
      final firstQuestion = firstSection.questions.first;
      controller.updateQuestionPrompt(
        firstSection.id,
        firstQuestion.id,
        'Masaya ka ba sa serbisyo? ✓',
      );
      controller.updateOptionLabel(
        firstSection.id,
        firstQuestion.id,
        firstQuestion.options.first.id,
        'Oo – mahusay',
      );

      final artifactResult = await controller.generatePdf();
      expect(
        artifactResult.isSuccess,
        isTrue,
        reason: artifactResult.errorOrNull?.toString(),
      );
      final artifact = artifactResult.value;
      final definitionBeforeExport = artifact.definition;
      final layoutBeforeExport = artifact.layout;
      final exportResult =
          await IoTemplatePdfExporter(
            directoryProvider: () async => directory,
          ).export(
            bytes: artifact.bytes,
            suggestedFileName: templatePdfFileName(
              artifact.definition.name,
              artifact.definition.version,
            ),
          );

      expect(exportResult.isSuccess, isTrue);
      expect(exportResult.value.fileName, 'resume-survey-v1.pdf');
      expect(exportResult.value.byteCount, artifact.bytes.length);
      expect(await File(exportResult.value.path).exists(), isTrue);
      expect(await File(exportResult.value.path).readAsBytes(), artifact.bytes);
      expect(ascii.decode(artifact.bytes.take(5).toList()), '%PDF-');
      expect(artifact.definition, definitionBeforeExport);
      expect(artifact.layout, layoutBeforeExport);
      expect(
        artifact.layout.pages.expand(
          (page) => page.markerRegions.map((marker) => marker.markerId),
        ),
        everyElement(isIn([10, 11, 12, 13])),
      );
      for (final page in artifact.layout.pages) {
        expect(page.markerRegions.map((marker) => marker.markerId), [
          10,
          11,
          12,
          13,
        ]);
      }
    },
  );
}
