import 'dart:async';
import 'dart:typed_data';

import 'package:capstone_development/application/template_builder/template_builder_controller.dart';
import 'package:capstone_development/application/template_builder/template_pdf_exporter.dart';
import 'package:capstone_development/application/published_templates/in_memory_published_template_artifact_repository.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact_service.dart';
import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/debug/p12_template_builder_fixture.dart';
import 'package:capstone_development/debug/p12_template_builder_screen.dart';
import 'package:capstone_development/debug/p11_1_scanner_validation_sheet.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/pdf/application/pdf_engine.dart';
import 'package:capstone_development/engines/pdf/domain/pdf_render_fonts.dart';
import 'package:capstone_development/engines/template/application/template_publication_service.dart';
import 'package:capstone_development/engines/template/infrastructure/in_memory_template_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  testWidgets('screen keeps controller draft and exposes P12 actions', (
    tester,
  ) async {
    final controller = TemplateBuilderController();
    await tester.pumpWidget(
      MaterialApp(
        home: P12TemplateBuilderScreen(
          controller: controller,
          showDeveloperControls: true,
        ),
      ),
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
    await tester.scrollUntilVisible(
      find.byKey(const Key('generate-p14-1-dense-preview-pdf')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.byKey(const Key('generate-p14-1-dense-preview-pdf')),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('preview-answer-sheet')),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('preview-answer-sheet')), findsOneWidget);
  });

  testWidgets('mixed demo validates and previews through LayoutEngine', (
    tester,
  ) async {
    final controller = buildP12MixedTemplateDemo();
    await tester.pumpWidget(
      MaterialApp(
        home: P12TemplateBuilderScreen(
          controller: controller,
          showDeveloperControls: true,
        ),
      ),
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

  testWidgets('p14.1 dense preview renders the current builder template', (
    tester,
  ) async {
    final controller = TemplateBuilderController(
      templateId: TemplateId('current-user-template'),
      name: 'Current User Template',
      pdfEngine: PdfEngine(fontLoader: const _StandardPdfFontLoader()),
    );
    final section = controller.addSection(title: 'Current Answers');
    for (var index = 1; index <= 12; index++) {
      controller.addQuestion(section, prompt: 'Current response $index');
    }
    await tester.pumpWidget(
      MaterialApp(
        home: P12TemplateBuilderScreen(
          controller: controller,
          showDeveloperControls: true,
        ),
      ),
    );

    await _tapVisible(tester, const Key('generate-p14-1-dense-preview-pdf'));

    expect(
      find.byKey(const Key('layout-preview-panel'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('Selected columns: 3', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('current-user-template-v1-p1', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('p13-6-dense-a4-validation', skipOffstage: false),
      findsNothing,
    );
    await tester.dragUntilVisible(
      find.byKey(const Key('pdf-export-result')),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(
      find.byKey(const Key('pdf-export-result'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('current-user-template-v1.pdf', skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byKey(const Key('save-pdf'), skipOffstage: false), findsOne);
  });

  testWidgets('p14.1 dense preview exposes validation errors', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: P12TemplateBuilderScreen(showDeveloperControls: true),
      ),
    );

    await _tapVisible(tester, const Key('generate-p14-1-dense-preview-pdf'));

    expect(
      find.textContaining('BUILDER_TEMPLATE_INVALID', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('pdf-export-result'), skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('p14.2 answer sheet renders the current builder template', (
    tester,
  ) async {
    final controller = TemplateBuilderController(
      templateId: TemplateId('current-answer-template'),
      name: 'Current Answer Template',
      pdfEngine: PdfEngine(fontLoader: const _StandardPdfFontLoader()),
    );
    final section = controller.addSection(title: 'Current Answers');
    for (var index = 1; index <= 8; index++) {
      controller.addQuestion(section, prompt: 'Current answer $index');
    }
    await tester.pumpWidget(
      MaterialApp(
        home: P12TemplateBuilderScreen(
          controller: controller,
          showDeveloperControls: true,
        ),
      ),
    );

    await _tapVisible(tester, const Key('preview-answer-sheet'));

    expect(
      find.byKey(const Key('layout-preview-panel'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('Selected columns: 3', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('current-answer-template-v1-p1', skipOffstage: false),
      findsOneWidget,
    );
    await tester.dragUntilVisible(
      find.byKey(const Key('pdf-export-result')),
      find.byType(ListView),
      const Offset(0, -300),
    );
    expect(
      find.textContaining(
        'current-answer-template-v1.pdf',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('save-pdf'), skipOffstage: false), findsOne);
  });

  testWidgets('p14.2 answer sheet exposes validation errors', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: P12TemplateBuilderScreen(showDeveloperControls: true),
      ),
    );

    await _tapVisible(tester, const Key('preview-answer-sheet'));

    expect(
      find.textContaining('BUILDER_TEMPLATE_INVALID', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('pdf-export-result'), skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets(
    'p14.2 publication stores current template and exposes exact artifact',
    (tester) async {
      final repository = InMemoryPublishedTemplateArtifactRepository();
      final renderCompleter = Completer<EngineResult<Uint8List>>();
      final controller = TemplateBuilderController(
        templateId: TemplateId('current-published-answer-sheet'),
        name: 'Current Published Answer Sheet',
      );
      final section = controller.addSection(title: 'Current Answers');
      controller.addQuestion(section, prompt: 'Current response');
      await tester.pumpWidget(
        MaterialApp(
          home: P12TemplateBuilderScreen(
            controller: controller,
            showDeveloperControls: true,
            answerSheetPublicationService: PublishedTemplateArtifactService(
              repository: repository,
              pdfRenderer: (_, _) => renderCompleter.future,
            ),
          ),
        ),
      );

      final finder = find.byKey(const Key('publish-answer-sheet'));
      await tester.scrollUntilVisible(
        finder,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(finder, findsOneWidget);
      final publishButton = tester.widget<FilledButton>(finder);
      expect(publishButton.onPressed, isNotNull);
      publishButton.onPressed!();
      await tester.pump();

      expect(find.text('Publishing...'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('preview-answer-sheet')))
            .onPressed,
        isNull,
      );

      final bytes = Uint8List.fromList([37, 80, 68, 70, 45, 2, 1]);
      renderCompleter.complete(EngineResult.success(bytes));
      await tester.pumpAndSettle();

      final stored = (await repository.list()).value.single;
      expect(stored.templateId.value, 'current-published-answer-sheet');
      expect(stored.template.name, 'Current Published Answer Sheet');
      expect(stored.layoutProfile, LayoutProfile.answerSheet);
      expect(stored.pdfBytes, bytes);
      expect(
        stored.layout.pages
            .expand((page) => page.bubbleRegions)
            .every((bubble) => bubble.printedLabel != null),
        isTrue,
      );
      expect(
        find.byKey(
          const Key('answer-sheet-publication-result'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Answer Sheet v1 published locally with exact PDF and PageLayout.',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('layout-preview-panel'), skipOffstage: false),
        findsOneWidget,
      );
      await tester.dragUntilVisible(
        find.byKey(const Key('pdf-export-result')),
        find.byType(ListView),
        const Offset(0, -300),
      );
      expect(
        find.byKey(const Key('pdf-export-result'), skipOffstage: false),
        findsOneWidget,
      );
      expect(find.byKey(const Key('save-pdf'), skipOffstage: false), findsOne);
      await _scrollToTop(tester);
      expect(find.textContaining('Status: published'), findsOneWidget);
    },
  );

  testWidgets('p14.2 publication errors do not expose PDF or preview', (
    tester,
  ) async {
    final repository = InMemoryPublishedTemplateArtifactRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: P12TemplateBuilderScreen(
          controller: TemplateBuilderController(name: ''),
          showDeveloperControls: true,
          answerSheetPublicationService: PublishedTemplateArtifactService(
            repository: repository,
          ),
        ),
      ),
    );

    await _tapVisible(tester, const Key('publish-answer-sheet'));

    expect(
      find.textContaining('TEMPLATE_PUBLICATION_INVALID', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('layout-preview-panel'), skipOffstage: false),
      findsNothing,
    );
    expect(
      find.byKey(const Key('pdf-export-result'), skipOffstage: false),
      findsNothing,
    );
    expect((await repository.list()).value, isEmpty);
  });

  testWidgets('save action receives exact generated bytes and updates UI', (
    tester,
  ) async {
    final controller = TemplateBuilderController(name: 'Résumé Survey');
    final section = controller.addSection();
    controller.addQuestion(section);
    final exporter = _RecordingExporter(
      result: EngineResult.success(
        PdfExportOutcome.saved(
          fileName: 'resume-survey-v1.pdf',
          byteCount: 5,
          method: PdfExportMethod.systemSaveDialog,
          locationUri: Uri.parse('content://documents/resume-survey-v1.pdf'),
        ),
      ),
    );
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
          showDeveloperControls: true,
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
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.byKey(const Key('pdf-export-result')),
      find.byType(ListView),
      const Offset(0, -300),
    );

    expect(find.textContaining('PDF generated successfully'), findsOneWidget);
    expect(exporter.callCount, 0);
    await tester.drag(find.byType(ListView), const Offset(0, -100));
    await tester.pump();
    await tester.tap(find.byKey(const Key('save-pdf')));
    await tester.pumpAndSettle();

    expect(exporter.callCount, 1);
    expect(exporter.bytes, same(artifact.bytes));
    expect(exporter.fileName, 'resume-survey-v1.pdf');
    expect(find.textContaining('PDF saved successfully'), findsOneWidget);
    expect(find.textContaining('content://documents/'), findsOneWidget);
    expect(find.textContaining('resume-survey-v1.pdf'), findsNWidgets(2));
  });

  testWidgets('dense validation PDF action exposes the dense artifact', (
    tester,
  ) async {
    final controller = TemplateBuilderController();
    final denseController = TemplateBuilderController(
      name: 'Dense Validation',
      layoutConfig: LayoutConfig.a4Dense(),
    );
    final section = denseController.addSection(title: 'Dense');
    denseController.addQuestion(section, prompt: 'Dense question');
    final preview = denseController.previewLayout().value;
    final artifact = TemplatePdfArtifact(
      definition: preview.definition,
      layout: preview.layout,
      bytes: Uint8List.fromList([37, 80, 68, 70, 45]),
    );
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: P12TemplateBuilderScreen(
          controller: controller,
          showDeveloperControls: true,
          densePdfGenerator: () async {
            calls++;
            return EngineResult.success(artifact);
          },
        ),
      ),
    );

    await _tapVisible(tester, const Key('generate-dense-validation-pdf'));
    await _revealVisible(tester, const Key('pdf-export-result'));

    expect(calls, 1);
    expect(
      find.textContaining('PDF generated successfully', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Pages: ${artifact.layout.pages.length}',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('dense publication stores the exact versioned artifact', (
    tester,
  ) async {
    final repository = InMemoryPublishedTemplateArtifactRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: P12TemplateBuilderScreen(
          showDeveloperControls: true,
          densePublicationService: PublishedTemplateArtifactService(
            repository: repository,
            pdfRenderer: (_, _) async =>
                EngineResult.success(Uint8List.fromList([37, 80, 68, 70, 45])),
          ),
        ),
      ),
    );

    final publishButton = tester.widget<FilledButton>(
      find.byKey(const Key('publish-dense-template-v1')),
    );
    expect(publishButton.onPressed, isNotNull);
    publishButton.onPressed!();
    await tester.pumpAndSettle();

    final stored = await repository.list();
    expect(stored.value, hasLength(1));
    await tester.dragUntilVisible(
      find.byKey(const Key('dense-publication-result')),
      find.byType(ListView),
      const Offset(0, -250),
    );
    final publicationResult = find.byKey(
      const Key('dense-publication-result'),
      skipOffstage: false,
    );
    expect(publicationResult, findsOneWidget);
    expect(
      tester.widget<SelectableText>(publicationResult).data,
      contains('Dense Template v1 saved locally'),
    );
    expect(stored.value.single.layout.pages, hasLength(1));
    expect(
      stored.value.single.layout.pages.single.bubbleRegions,
      hasLength(160),
    );
  });

  testWidgets('multi-page PDF action exposes the exact three-page fixture', (
    tester,
  ) async {
    final inputs = buildP11ScannerValidationSheetInputs();
    final artifact = TemplatePdfArtifact(
      definition: inputs.template,
      layout: inputs.layout,
      bytes: Uint8List.fromList([37, 80, 68, 70, 45]),
    );
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: P12TemplateBuilderScreen(
          showDeveloperControls: true,
          multiPagePdfGenerator: () async {
            calls++;
            return EngineResult.success(artifact);
          },
        ),
      ),
    );

    await _tapVisible(tester, const Key('generate-multi-page-validation-pdf'));
    await tester.dragUntilVisible(
      find.byKey(const Key('pdf-export-result')),
      find.byType(ListView),
      const Offset(0, -300),
    );

    expect(calls, 1);
    expect(
      find.byKey(const Key('pdf-export-result'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byKey(const Key('save-pdf'), skipOffstage: false), findsOne);
  });

  testWidgets('multi-page publication stores exact identities and signatures', (
    tester,
  ) async {
    final repository = InMemoryPublishedTemplateArtifactRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: P12TemplateBuilderScreen(
          showDeveloperControls: true,
          densePublicationService: PublishedTemplateArtifactService(
            repository: repository,
            pdfRenderer: (_, _) async =>
                EngineResult.success(Uint8List.fromList([37, 80, 68, 70, 45])),
          ),
        ),
      ),
    );

    await _tapVisible(tester, const Key('publish-multi-page-template-v1'));

    final stored = await repository.list();
    expect(stored.value, hasLength(1));
    expect(stored.value.single.templateId.value, 'p11-1-scanner-validation');
    expect(stored.value.single.layout.pages, hasLength(3));
    expect(
      stored.value.single.layout.pages.map(
        (page) => page.markerRegions
            .map((marker) => marker.markerId)
            .toList(growable: false),
      ),
      [
        [10, 11, 12, 13],
        [14, 15, 16, 17],
        [18, 19, 20, 21],
      ],
    );
    expect(
      find.byKey(
        const Key('multi-page-publication-result'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('save cancellation keeps the generated PDF without an error', (
    tester,
  ) async {
    final setup = _buildGeneratedPdfSetup(
      EngineResult.success(
        const PdfExportOutcome.cancelled(
          fileName: 'survey-v1.pdf',
          byteCount: 5,
          method: PdfExportMethod.systemSaveDialog,
        ),
      ),
    );
    await tester.pumpWidget(setup.widget);

    await _generateAndSave(tester);

    expect(find.textContaining('Save cancelled.'), findsOneWidget);
    expect(find.byKey(const Key('save-pdf')), findsOneWidget);
    expect(find.textContaining('PDF_EXPORT_'), findsNothing);
  });

  testWidgets('structured save failure is visible and can be retried', (
    tester,
  ) async {
    final setup = _buildGeneratedPdfSetup(
      EngineResult.failure(
        EngineError(
          code: 'PDF_EXPORT_PICKER_FAILED',
          message: 'Unable to open the save dialog.',
        ),
      ),
    );
    await tester.pumpWidget(setup.widget);

    await _generateAndSave(tester);

    expect(find.textContaining('PDF_EXPORT_PICKER_FAILED'), findsOneWidget);
    expect(find.byKey(const Key('save-pdf')), findsOneWidget);
  });

  testWidgets('publish locks editing and revision restores editable v2', (
    tester,
  ) async {
    final repository = InMemoryTemplateRepository();
    final publication = TemplatePublicationService(repository: repository);
    final controller = TemplateBuilderController(
      templateId: TemplateId('template-1'),
      name: 'Lifecycle Survey',
    );
    final section = controller.addSection(title: 'Section');
    controller.addQuestion(section, prompt: 'Question');
    await tester.pumpWidget(
      MaterialApp(
        home: P12TemplateBuilderScreen(
          controller: controller,
          showDeveloperControls: true,
          publicationService: publication,
        ),
      ),
    );

    expect(find.textContaining('Version: 1'), findsOneWidget);
    expect(find.textContaining('Status: draft'), findsOneWidget);
    await _tapVisible(tester, const Key('publish-template'));
    await _scrollToTop(tester);

    expect(find.textContaining('Status: published'), findsOneWidget);
    expect(find.textContaining('Published successfully: v1'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('name-template-1-v1')),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('add-section')))
          .onPressed,
      isNull,
    );

    await _tapVisible(tester, const Key('create-revision'));
    await _scrollToTop(tester);
    expect(find.textContaining('Version: 2'), findsOneWidget);
    expect(find.textContaining('Status: draft'), findsOneWidget);
    expect(
      find.textContaining('Created editable revision: v2'),
      findsOneWidget,
    );
    final v2Name = find.byKey(const ValueKey('name-template-1-v2'));
    expect(tester.widget<TextFormField>(v2Name).enabled, isTrue);
    await tester.ensureVisible(v2Name);
    await tester.enterText(v2Name, 'Lifecycle Survey Revised');
    await tester.pump();

    await _tapVisible(tester, const Key('publish-template'));
    await _scrollToTop(tester);

    expect(find.textContaining('Published successfully: v2'), findsOneWidget);
    expect(find.textContaining('Published versions: v1, v2'), findsOneWidget);
    final history = await publication.listPublishedVersions(
      controller.snapshot.definition.id,
    );
    expect(history.value.map((item) => item.version.value), [1, 2]);
    expect(history.value.first.name, 'Lifecycle Survey');
    expect(history.value.last.name, 'Lifecycle Survey Revised');

    await _tapVisible(tester, const Key('view-published-v1'));
    await _tapVisible(tester, const Key('preview-layout'));
    await _revealVisible(tester, const Key('layout-preview-panel'));
    expect(
      find.textContaining('template-1-v1-p1', skipOffstage: false),
      findsOneWidget,
    );
    await _scrollToTop(tester);
    await _tapVisible(tester, const Key('view-published-v2'));
    await _tapVisible(tester, const Key('preview-layout'));
    await _revealVisible(tester, const Key('layout-preview-panel'));
    expect(
      find.textContaining('template-1-v2-p1', skipOffstage: false),
      findsOneWidget,
    );
  });
}

final class _StandardPdfFontLoader implements PdfRenderFontLoader {
  const _StandardPdfFontLoader();

  @override
  Future<EngineResult<PdfRenderFonts>> load() async => EngineResult.success(
    PdfRenderFonts(regular: pw.Font.helvetica(), bold: pw.Font.helveticaBold()),
  );
}

final class _RecordingExporter implements TemplatePdfExporter {
  _RecordingExporter({required this.result});

  final EngineResult<PdfExportOutcome> result;
  int callCount = 0;
  Uint8List? bytes;
  String? fileName;

  @override
  Future<EngineResult<PdfExportOutcome>> export({
    required Uint8List bytes,
    required String suggestedFileName,
  }) async {
    callCount++;
    this.bytes = bytes;
    fileName = suggestedFileName;
    return result;
  }
}

({Widget widget, _RecordingExporter exporter}) _buildGeneratedPdfSetup(
  EngineResult<PdfExportOutcome> exportResult,
) {
  final controller = TemplateBuilderController(name: 'Survey');
  final section = controller.addSection();
  controller.addQuestion(section);
  final preview = controller.previewLayout().value;
  final artifact = TemplatePdfArtifact(
    definition: preview.definition,
    layout: preview.layout,
    bytes: Uint8List.fromList([37, 80, 68, 70, 45]),
  );
  final exporter = _RecordingExporter(result: exportResult);
  return (
    widget: MaterialApp(
      home: P12TemplateBuilderScreen(
        controller: controller,
        showDeveloperControls: true,
        exporter: exporter,
        pdfGenerator: () async => EngineResult.success(artifact),
      ),
    ),
    exporter: exporter,
  );
}

Future<void> _generateAndSave(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.byKey(const Key('generate-pdf')),
    find.byType(ListView),
    const Offset(0, -500),
  );
  await tester.tap(find.byKey(const Key('generate-pdf')));
  await tester.pumpAndSettle();
  await tester.dragUntilVisible(
    find.byKey(const Key('save-pdf')),
    find.byType(ListView),
    const Offset(0, -300),
  );
  await tester.drag(find.byType(ListView), const Offset(0, -100));
  await tester.pump();
  await tester.tap(find.byKey(const Key('save-pdf')));
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _revealVisible(WidgetTester tester, Key key) async {
  await tester.scrollUntilVisible(
    find.byKey(key),
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _scrollToTop(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, 3000));
  await tester.pumpAndSettle();
}
