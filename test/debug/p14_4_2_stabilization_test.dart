import 'package:capstone_development/application/answer_sheet_packets/in_memory_packet_response_repository.dart';
import 'package:capstone_development/application/answer_sheet_packets/packet_generation_service.dart';
import 'package:capstone_development/application/published_templates/in_memory_published_template_artifact_repository.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact_service.dart';
import 'package:capstone_development/application/template_builder/template_builder_controller.dart';
import 'package:capstone_development/application/template_builder/template_id_generator.dart';
import 'package:capstone_development/application/template_builder/template_pdf_exporter.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/debug/p12_template_builder_screen.dart';
import 'package:capstone_development/debug/packet_pdf_preview_screen.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('published template then New Template creates a blank new ID', (
    tester,
  ) async {
    final repository = InMemoryPublishedTemplateArtifactRepository();
    final publication = _publicationService(repository);
    final controller = _validController('tmpl-a', 'Template A');

    await tester.pumpWidget(
      MaterialApp(
        home: P12TemplateBuilderScreen(
          controller: controller,
          templateIdGenerator: _SequenceTemplateIdGenerator(['tmpl-b']),
          answerSheetPublicationService: publication,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _tapVisible(tester, const Key('publish-answer-sheet'));
    expect((await repository.list()).value, hasLength(1));

    await tester.drag(find.byType(ListView), const Offset(0, 5000));
    await tester.pumpAndSettle();
    await _tapVisible(tester, const Key('new-template'));

    expect(find.textContaining('Template ID: tmpl-b'), findsOneWidget);
    expect(find.textContaining('Status: draft'), findsOneWidget);
    expect(
      find.text('Add a section to begin building the template.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('name-tmpl-b-v1')), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('name-tmpl-b-v1')))
          .initialValue,
      'Untitled Template',
    );
    expect(
      find.byKey(const Key('selected-answer-sheet'), skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('restart stays fresh and persisted template requires selection', (
    tester,
  ) async {
    final repository = InMemoryPublishedTemplateArtifactRepository();
    final publication = _publicationService(repository);
    final artifact = await publication.publish(
      draft: _validController('tmpl-a', 'Template A').buildDefinition(),
      layoutConfig: LayoutConfig.a4AnswerSheet(),
    );
    expect(artifact.isSuccess, isTrue);
    final generator = _SequenceTemplateIdGenerator(['tmpl-c', 'tmpl-d']);

    await tester.pumpWidget(
      MaterialApp(
        home: P12TemplateBuilderScreen(
          templateIdGenerator: generator,
          answerSheetPublicationService: publication,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Template ID: tmpl-c'), findsOneWidget);
    expect(find.byKey(const ValueKey('name-tmpl-c-v1')), findsOneWidget);
    expect(
      find.byKey(const Key('selected-answer-sheet'), skipOffstage: false),
      findsNothing,
    );
    await _tapVisible(tester, const Key('new-template'));
    expect(find.textContaining('Template ID: tmpl-d'), findsOneWidget);
    expect(find.byKey(const ValueKey('name-tmpl-d-v1')), findsOneWidget);
  });

  testWidgets('batch preview and export receive exact combined bytes', (
    tester,
  ) async {
    final artifactRepository = InMemoryPublishedTemplateArtifactRepository();
    final publication = _publicationService(artifactRepository);
    final controller = _validController('tmpl-batch', 'Batch Survey');
    final published = await publication.publish(
      draft: controller.buildDefinition(),
      layoutConfig: LayoutConfig.a4AnswerSheet(),
    );
    expect(published.isSuccess, isTrue);
    final packetRepository = InMemoryPacketResponseRepository();
    final packetBytes = Uint8List.fromList([37, 80, 68, 70, 1]);
    final batchBytes = Uint8List.fromList([37, 80, 68, 70, 66, 5]);
    final previewer = _RecordingPreviewer();
    final exporter = _RecordingExporter();

    await tester.pumpWidget(
      MaterialApp(
        home: P12TemplateBuilderScreen(
          controller: controller,
          answerSheetPublicationService: publication,
          packetGenerationService: PacketGenerationService(
            repository: packetRepository,
            pdfRenderer: (_, _) async => EngineResult.success(packetBytes),
            batchPdfRenderer: (_, packets) async {
              expect(packets, hasLength(5));
              return EngineResult.success(batchBytes);
            },
          ),
          packetPreviewer: previewer,
          exporter: exporter,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _selectArtifact(tester, published.value);
    final count = find.byKey(const Key('packet-count'));
    await _reveal(tester, count);
    await tester.enterText(count, '5');
    await tester.pump();
    await _tapVisible(tester, const Key('generate-answer-sheet-packets'));

    expect(find.textContaining('Generated packets: 5'), findsOneWidget);
    expect(find.textContaining('Responses: 0'), findsOneWidget);
    expect(find.byKey(const Key('generated-packet-batch')), findsOneWidget);
    expect((await packetRepository.listPackets()).value, hasLength(5));
    expect((await packetRepository.listResponses()).value, isEmpty);

    final preview = tester.widget<FilledButton>(
      find.byKey(const Key('preview-packet-batch')),
    );
    preview.onPressed!();
    await tester.pumpAndSettle();
    expect(listEquals(previewer.bytes, batchBytes), isTrue);
    expect(listEquals(previewer.bytes, packetBytes), isFalse);

    final save = tester.widget<FilledButton>(
      find.byKey(const Key('save-packet-batch')),
    );
    save.onPressed!();
    await tester.pumpAndSettle();
    expect(listEquals(exporter.bytes, batchBytes), isTrue);
    expect(exporter.fileName, contains('packets-p000-0000-p004-e6c4-v1.pdf'));
    expect(find.byKey(const Key('batch-save-outcome')), findsOneWidget);
  });
}

TemplateBuilderController _validController(String id, String name) {
  final controller = TemplateBuilderController(
    templateId: TemplateId(id),
    name: name,
  );
  final section = controller.addSection(title: 'Section');
  controller.addQuestion(section, prompt: 'Question');
  return controller;
}

PublishedTemplateArtifactService _publicationService(
  InMemoryPublishedTemplateArtifactRepository repository,
) => PublishedTemplateArtifactService(
  repository: repository,
  pdfRenderer: (_, _) async =>
      EngineResult.success(Uint8List.fromList([37, 80, 68, 70])),
);

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

Future<void> _tapVisible(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await _reveal(tester, finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
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

final class _SequenceTemplateIdGenerator implements TemplateIdGenerator {
  _SequenceTemplateIdGenerator(this.values);

  final List<String> values;
  var _index = 0;

  @override
  TemplateId generate() => TemplateId(values[_index++]);
}

final class _RecordingPreviewer implements PacketPdfPreviewer {
  Uint8List? bytes;

  @override
  Future<void> preview(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
    required String title,
  }) async {
    this.bytes = Uint8List.fromList(bytes);
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
