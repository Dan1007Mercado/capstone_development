import 'dart:async';
import 'dart:typed_data';

import 'package:capstone_development/application/template_builder/template_builder_controller.dart';
import 'package:capstone_development/application/template_builder/template_pdf_exporter.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/debug/p12_template_builder_fixture.dart';
import 'package:capstone_development/debug/p12_template_builder_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('screen keeps controller draft and exposes P12 actions', (
    tester,
  ) async {
    final controller = TemplateBuilderController();
    await tester.pumpWidget(
      MaterialApp(home: P12TemplateBuilderScreen(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('add-section')));
    await tester.pump();
    final sectionId = controller.snapshot.definition.sections.single.id;
    await tester.tap(find.byKey(Key('add-question-${sectionId.value}')));
    await tester.pump();

    expect(
      controller.snapshot.definition.sections.single.questions,
      hasLength(1),
    );
    expect(find.text('Question 1'), findsOneWidget);
    expect(find.text('Single Choice'), findsOneWidget);
  });

  testWidgets('mixed demo validates and previews through LayoutEngine', (
    tester,
  ) async {
    final controller = buildP12MixedTemplateDemo();
    await tester.pumpWidget(
      MaterialApp(home: P12TemplateBuilderScreen(controller: controller)),
    );

    await tester.dragUntilVisible(
      find.byKey(const Key('preview-layout')),
      find.byType(ListView),
      const Offset(0, -500),
    );
    await tester.tap(find.byKey(const Key('preview-layout')));
    await tester.pump();
    await tester.dragUntilVisible(
      find.byKey(const Key('layout-preview-panel')),
      find.byType(ListView),
      const Offset(0, -400),
    );

    expect(find.text('Template is valid.'), findsOneWidget);
    expect(find.textContaining('Layout preview:'), findsOneWidget);
  });

  testWidgets('generate PDF displays selectable exported path diagnostics', (
    tester,
  ) async {
    final controller = TemplateBuilderController(name: 'Résumé Survey');
    final section = controller.addSection();
    controller.addQuestion(section);
    final exporter = _RecordingExporter();
    final preview = controller.previewLayout().value;
    final artifact = TemplatePdfArtifact(
      definition: preview.definition,
      layout: preview.layout,
      bytes: Uint8List.fromList([37, 80, 68, 70, 45]),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: P12TemplateBuilderScreen(
          controller: controller,
          exporter: exporter,
          pdfGenerator: () async => EngineResult.success(artifact),
        ),
      ),
    );

    await tester.dragUntilVisible(
      find.byKey(const Key('generate-pdf')),
      find.byType(ListView),
      const Offset(0, -500),
    );
    await tester.tap(find.byKey(const Key('generate-pdf')));
    await tester.pump();
    await tester.runAsync(exporter.waitForExport);
    await tester.pump();
    await tester.dragUntilVisible(
      find.byKey(const Key('pdf-export-result')),
      find.byType(ListView),
      const Offset(0, -300),
    );

    final success = find.textContaining('PDF exported successfully');
    expect(success, findsOneWidget);
    expect(find.textContaining('resume-survey-v1.pdf'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });
}

final class _RecordingExporter implements TemplatePdfExporter {
  final Completer<void> _exported = Completer<void>();

  Future<void> waitForExport() =>
      _exported.future.timeout(const Duration(seconds: 15));

  @override
  Future<EngineResult<ExportedPdfFile>> export({
    required Uint8List bytes,
    required String suggestedFileName,
  }) async {
    if (!_exported.isCompleted) _exported.complete();
    return EngineResult.success(
      ExportedPdfFile(
        path: '/app/cache/exports/$suggestedFileName',
        fileName: suggestedFileName,
        byteCount: bytes.length,
      ),
    );
  }
}
