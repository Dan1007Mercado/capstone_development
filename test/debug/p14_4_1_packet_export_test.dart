import 'package:capstone_development/application/answer_sheet_packets/in_memory_packet_response_repository.dart';
import 'package:capstone_development/application/answer_sheet_packets/packet_generation_service.dart';
import 'package:capstone_development/application/published_templates/in_memory_published_template_artifact_repository.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact_service.dart';
import 'package:capstone_development/application/template_builder/template_pdf_exporter.dart';
import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/debug/p12_template_builder_fixture.dart';
import 'package:capstone_development/debug/p12_template_builder_screen.dart';
import 'package:capstone_development/debug/packet_pdf_preview_screen.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('normal builder hides legacy phase controls', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: P12TemplateBuilderScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('preview-answer-sheet')), findsOneWidget);
    expect(find.byKey(const Key('publish-answer-sheet')), findsOneWidget);
    expect(
      find.byKey(
        const Key('generate-p14-1-dense-preview-pdf'),
        skipOffstage: false,
      ),
      findsNothing,
    );
    expect(
      find.byKey(const Key('generate-dense-validation'), skipOffstage: false),
      findsNothing,
    );
    expect(
      find.byKey(
        const Key('generate-multipage-validation'),
        skipOffstage: false,
      ),
      findsNothing,
    );
  });

  testWidgets(
    'persisted published sheet generates, previews, and saves packet',
    (tester) async {
      final controller = buildP12MixedTemplateDemo();
      final artifactRepository = InMemoryPublishedTemplateArtifactRepository();
      final publicationService = PublishedTemplateArtifactService(
        repository: artifactRepository,
        pdfRenderer: (_, _) async =>
            EngineResult.success(Uint8List.fromList([37, 80, 68, 70, 1])),
      );
      final published = await publicationService.publish(
        draft: controller.buildDefinition(),
        layoutConfig: LayoutConfig.a4AnswerSheet(),
      );
      expect(published.isSuccess, isTrue);

      final packetBytes = Uint8List.fromList([37, 80, 68, 70, 45, 9, 8, 7]);
      final packetRepository = InMemoryPacketResponseRepository();
      final packetService = PacketGenerationService(
        repository: packetRepository,
        pdfRenderer: (_, _) async => EngineResult.success(packetBytes),
        batchPdfRenderer: (_, _) async =>
            EngineResult.success(Uint8List.fromList([37, 80, 68, 70, 45, 66])),
      );
      final previewer = _RecordingPreviewer();
      final exporter = _RecordingExporter();

      await tester.pumpWidget(
        MaterialApp(
          home: P12TemplateBuilderScreen(
            controller: controller,
            answerSheetPublicationService: publicationService,
            packetGenerationService: packetService,
            packetPreviewer: previewer,
            exporter: exporter,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _selectArtifact(tester, published.value);
      final generate = find.byKey(const Key('generate-answer-sheet-packets'));
      await _reveal(tester, generate);

      expect(
        find.byKey(const Key('selected-answer-sheet'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('packet-count')))
            .controller!
            .text,
        '1',
      );
      expect(tester.widget<FilledButton>(generate).onPressed, isNotNull);

      await _tapVisible(tester, generate);
      await tester.pumpAndSettle();
      expect(find.textContaining('Generated packets: 1'), findsOneWidget);
      expect(
        find.byKey(const Key('packet-generation-success')),
        findsOneWidget,
      );

      await _tapVisible(
        tester,
        find.byKey(const Key('generated-packet-inspection')),
      );
      final packetId = PacketId.fromSequence(0).value;
      final previewButton = tester.widget<TextButton>(
        find.byKey(ValueKey('preview-packet-$packetId')),
      );
      previewButton.onPressed!();
      await tester.pumpAndSettle();
      expect(listEquals(previewer.bytes, packetBytes), isTrue);
      expect(previewer.title, 'Packet $packetId');

      final saveButton = tester.widget<TextButton>(
        find.byKey(ValueKey('save-packet-$packetId')),
      );
      saveButton.onPressed!();
      await tester.pumpAndSettle();
      expect(listEquals(exporter.bytes, packetBytes), isTrue);
      expect(
        exporter.fileName,
        contains('packet-${packetId.toLowerCase()}-v1.pdf'),
      );
      expect(
        find.byKey(ValueKey('packet-save-outcome-$packetId')),
        findsOneWidget,
      );
    },
  );

  testWidgets('restart reloads packet metadata and keeps sequence monotonic', (
    tester,
  ) async {
    final artifactRepository = InMemoryPublishedTemplateArtifactRepository();
    final publicationService = PublishedTemplateArtifactService(
      repository: artifactRepository,
      pdfRenderer: (_, _) async =>
          EngineResult.success(Uint8List.fromList([37, 80, 68, 70, 2])),
    );
    final firstController = buildP12MixedTemplateDemo();
    final published = await publicationService.publish(
      draft: firstController.buildDefinition(),
      layoutConfig: LayoutConfig.a4AnswerSheet(),
    );
    expect(published.isSuccess, isTrue);
    final packetRepository = InMemoryPacketResponseRepository();
    PacketGenerationService service() => PacketGenerationService(
      repository: packetRepository,
      pdfRenderer: (_, packet) async => EngineResult.success(
        Uint8List.fromList([37, 80, 68, 70, packet.packetId.sequence]),
      ),
      batchPdfRenderer: (_, packets) async => EngineResult.success(
        Uint8List.fromList([37, 80, 68, 70, packets.length]),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: P12TemplateBuilderScreen(
          controller: firstController,
          answerSheetPublicationService: publicationService,
          packetGenerationService: service(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectArtifact(tester, published.value);
    await _tapVisible(
      tester,
      find.byKey(const Key('generate-answer-sheet-packets')),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      MaterialApp(
        home: P12TemplateBuilderScreen(
          controller: buildP12MixedTemplateDemo(),
          answerSheetPublicationService: publicationService,
          packetGenerationService: service(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('selected-answer-sheet'), skipOffstage: false),
      findsNothing,
    );
    await _selectArtifact(tester, published.value);
    final generate = find.byKey(const Key('generate-answer-sheet-packets'));
    await _reveal(tester, generate);

    expect(
      find.byKey(const Key('selected-answer-sheet'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('Generated packets: 1', skipOffstage: false),
      findsOneWidget,
    );
    await _tapVisible(tester, generate);
    await tester.pumpAndSettle();
    expect(find.textContaining('Generated packets: 2'), findsOneWidget);

    final packets = (await packetRepository.listPackets()).value;
    expect(packets.map((packet) => packet.packetId), [
      PacketId.fromSequence(0),
      PacketId.fromSequence(1),
    ]);
  });

  testWidgets('packet rendering failure is visible with its error code', (
    tester,
  ) async {
    final controller = buildP12MixedTemplateDemo();
    final artifactRepository = InMemoryPublishedTemplateArtifactRepository();
    final publicationService = PublishedTemplateArtifactService(
      repository: artifactRepository,
      pdfRenderer: (_, _) async =>
          EngineResult.success(Uint8List.fromList([37, 80, 68, 70, 3])),
    );
    final published = await publicationService.publish(
      draft: controller.buildDefinition(),
      layoutConfig: LayoutConfig.a4AnswerSheet(),
    );
    final packetService = PacketGenerationService(
      repository: InMemoryPacketResponseRepository(),
      batchPdfRenderer: (_, _) async => EngineResult.failure(
        EngineError(
          code: 'PACKET_RENDER_FAILED',
          message: 'Unable to render packet bytes.',
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: P12TemplateBuilderScreen(
          controller: controller,
          answerSheetPublicationService: publicationService,
          packetGenerationService: packetService,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectArtifact(tester, published.value);
    await _tapVisible(
      tester,
      find.byKey(const Key('generate-answer-sheet-packets')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('packet-generation-error'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('PACKET_RENDER_FAILED', skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.textContaining('Generated packets: 0', skipOffstage: false),
      findsOneWidget,
    );
  });

  test('packet filename includes sanitized packet identity and version', () {
    expect(
      packetPdfFileName(
        'Community Survey',
        PacketId.fromSequence(12),
        TemplateVersion(3),
      ),
      'community-survey-packet-p012-b44c-v3.pdf',
    );
  });
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

Future<void> _selectArtifact(
  WidgetTester tester,
  PublishedTemplateArtifact artifact,
) async {
  final finder = find.byKey(const Key('published-answer-sheet-selector'));
  await _reveal(tester, finder);
  tester
      .widget<DropdownButtonFormField<PublishedTemplateArtifact>>(finder)
      .onChanged!(artifact);
  await tester.pumpAndSettle();
}

final class _RecordingPreviewer implements PacketPdfPreviewer {
  Uint8List? bytes;
  String? fileName;
  String? title;

  @override
  Future<void> preview(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
    required String title,
  }) async {
    this.bytes = Uint8List.fromList(bytes);
    this.fileName = fileName;
    this.title = title;
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
    this.bytes = Uint8List.fromList(bytes);
    fileName = suggestedFileName;
    return EngineResult.success(
      PdfExportOutcome.saved(
        fileName: suggestedFileName,
        byteCount: bytes.length,
        method: PdfExportMethod.internalFileSystem,
        locationUri: Uri.file('/tmp/$suggestedFileName'),
      ),
    );
  }
}
