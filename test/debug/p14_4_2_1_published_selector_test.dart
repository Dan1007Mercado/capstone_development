import 'dart:typed_data';

import 'package:capstone_development/application/answer_sheet_packets/in_memory_packet_response_repository.dart';
import 'package:capstone_development/application/answer_sheet_packets/packet_generation_service.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact_repository.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact_service.dart';
import 'package:capstone_development/application/template_builder/template_builder_controller.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/debug/p12_template_builder_screen.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'one-question publish selects the reloaded artifact instance safely',
    (tester) async {
      final repository = _ReloadingArtifactRepository();
      final service = _service(repository);

      await _pumpBuilder(
        tester,
        controller: _controller('template-one', 'One Question'),
        publicationService: service,
      );
      await _tapVisible(tester, const Key('publish-answer-sheet'));

      expect(tester.takeException(), isNull);
      final dropdown = await _selector(tester);
      expect(dropdown.items, hasLength(1));
      expect(dropdown.value, isNotNull);
      expect(identical(dropdown.value, dropdown.items!.single.value), isTrue);
      expect(identical(dropdown.value, repository.saved.single), isFalse);
      expect(dropdown.value!.templateId, TemplateId('template-one'));
    },
  );

  for (final fixture in [
    (name: 'five questions', sections: [5]),
    (name: 'multiple sections', sections: [2, 3]),
  ]) {
    testWidgets('${fixture.name} publishes without a selector exception', (
      tester,
    ) async {
      final repository = _ReloadingArtifactRepository();
      await _pumpBuilder(
        tester,
        controller: _controller(
          'template-${fixture.sections.join('-')}',
          fixture.name,
          questionsPerSection: fixture.sections,
        ),
        publicationService: _service(repository),
      );

      await _tapVisible(tester, const Key('publish-answer-sheet'));

      expect(tester.takeException(), isNull);
      final dropdown = await _selector(tester);
      expect(dropdown.items, hasLength(1));
      expect(identical(dropdown.value, dropdown.items!.single.value), isTrue);
    });
  }

  testWidgets(
    'publishing B retains A, selects B, and removes exact duplicates',
    (tester) async {
      final repository = _ReloadingArtifactRepository(
        duplicateListEntries: true,
      );
      final service = _service(repository);
      final publishedA = await service.publish(
        draft: _controller('template-a', 'Template A').buildDefinition(),
        layoutConfig: LayoutConfig.a4AnswerSheet(),
      );
      expect(publishedA.isSuccess, isTrue);

      await _pumpBuilder(
        tester,
        controller: _controller('template-b', 'Template B'),
        publicationService: service,
      );
      await _tapVisible(tester, const Key('publish-answer-sheet'));

      expect(tester.takeException(), isNull);
      final dropdown = await _selector(tester);
      expect(dropdown.items, hasLength(2));
      expect(
        dropdown.items!.map((item) => item.value!.templateId.value).toSet(),
        {'template-a', 'template-b'},
      );
      expect(dropdown.value!.templateId, TemplateId('template-b'));
      expect(
        identical(
          dropdown.value,
          dropdown.items!
              .singleWhere(
                (item) => item.value!.templateId == TemplateId('template-b'),
              )
              .value,
        ),
        isTrue,
      );
    },
  );

  testWidgets('restart keeps v1 and v2 distinct without auto-selection', (
    tester,
  ) async {
    final repository = _ReloadingArtifactRepository(duplicateListEntries: true);
    final service = _service(repository);
    for (final version in [1, 2]) {
      final result = await service.publish(
        draft: _controller(
          'versioned-template',
          'Versioned Template',
          version: version,
        ).buildDefinition(),
        layoutConfig: LayoutConfig.a4AnswerSheet(),
      );
      expect(result.isSuccess, isTrue);
    }

    await _pumpBuilder(
      tester,
      controller: _controller('fresh-template', 'Fresh Template'),
      publicationService: service,
    );

    expect(tester.takeException(), isNull);
    final dropdown = await _selector(tester);
    expect(dropdown.value, isNull);
    expect(dropdown.items, hasLength(2));
    expect(
      dropdown.items!.map((item) => item.value!.templateVersion.value).toSet(),
      {1, 2},
    );
    expect(
      find.byKey(const Key('selected-answer-sheet'), skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets(
    'manual selection generates packets from the exact list artifact',
    (tester) async {
      final repository = _ReloadingArtifactRepository();
      final service = _service(repository);
      final published = await service.publish(
        draft: _controller(
          'stored-template',
          'Stored Template',
        ).buildDefinition(),
        layoutConfig: LayoutConfig.a4AnswerSheet(),
      );
      expect(published.isSuccess, isTrue);
      PublishedTemplateArtifact? renderedFrom;
      final packetRepository = InMemoryPacketResponseRepository();

      await _pumpBuilder(
        tester,
        controller: _controller('fresh-template', 'Fresh Template'),
        publicationService: service,
        packetGenerationService: PacketGenerationService(
          repository: packetRepository,
          batchPdfRenderer: (artifact, packets) async {
            renderedFrom = artifact;
            expect(packets, hasLength(1));
            return EngineResult.success(Uint8List.fromList([37, 80, 68, 70]));
          },
        ),
      );
      final dropdown = await _selector(tester);
      final selectedListArtifact = dropdown.items!.single.value!;
      dropdown.onChanged!(selectedListArtifact);
      await tester.pumpAndSettle();

      final count = find.byKey(const Key('packet-count'));
      await _reveal(tester, count);
      await tester.enterText(count, '1');
      await tester.pump();
      await _tapVisible(tester, const Key('generate-answer-sheet-packets'));

      expect(tester.takeException(), isNull);
      expect(identical(renderedFrom, selectedListArtifact), isTrue);
      expect((await packetRepository.listPackets()).value, hasLength(1));
      expect(find.textContaining('Generated packets: 1'), findsOneWidget);
    },
  );
}

TemplateBuilderController _controller(
  String id,
  String name, {
  int version = 1,
  List<int> questionsPerSection = const [1],
}) {
  final controller = TemplateBuilderController(
    templateId: TemplateId(id),
    version: TemplateVersion(version),
    name: name,
  );
  for (
    var sectionIndex = 0;
    sectionIndex < questionsPerSection.length;
    sectionIndex++
  ) {
    final section = controller.addSection(title: 'Section ${sectionIndex + 1}');
    for (
      var questionIndex = 0;
      questionIndex < questionsPerSection[sectionIndex];
      questionIndex++
    ) {
      controller.addQuestion(
        section,
        prompt: 'Question ${sectionIndex + 1}.${questionIndex + 1}',
      );
    }
  }
  return controller;
}

PublishedTemplateArtifactService _service(
  PublishedTemplateArtifactRepository repository,
) => PublishedTemplateArtifactService(
  repository: repository,
  pdfRenderer: (_, _) async =>
      EngineResult.success(Uint8List.fromList([37, 80, 68, 70])),
);

Future<void> _pumpBuilder(
  WidgetTester tester, {
  required TemplateBuilderController controller,
  required PublishedTemplateArtifactService publicationService,
  PacketGenerationService? packetGenerationService,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: P12TemplateBuilderScreen(
        controller: controller,
        answerSheetPublicationService: publicationService,
        packetGenerationService: packetGenerationService,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<DropdownButton<PublishedTemplateArtifact>> _selector(
  WidgetTester tester,
) async {
  final finder = find.byKey(const Key('published-answer-sheet-selector'));
  await _reveal(tester, finder);
  return tester.widget<DropdownButton<PublishedTemplateArtifact>>(
    find.descendant(
      of: finder,
      matching: find.byType(DropdownButton<PublishedTemplateArtifact>),
    ),
  );
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

final class _ReloadingArtifactRepository
    implements PublishedTemplateArtifactRepository {
  _ReloadingArtifactRepository({this.duplicateListEntries = false});

  final bool duplicateListEntries;
  final Map<String, PublishedTemplateArtifact> _stored = {};
  final List<PublishedTemplateArtifact> saved = [];

  @override
  Future<EngineResult<PublishedTemplateArtifact>> save(
    PublishedTemplateArtifact artifact,
  ) async {
    final key = _key(artifact.templateId, artifact.templateVersion);
    if (_stored.containsKey(key)) {
      throw StateError('Duplicate test artifact: $key');
    }
    _stored[key] = artifact;
    saved.add(artifact);
    return EngineResult.success(artifact);
  }

  @override
  Future<EngineResult<PublishedTemplateArtifact?>> get(
    TemplateId templateId,
    TemplateVersion templateVersion,
  ) async {
    final artifact = _stored[_key(templateId, templateVersion)];
    return EngineResult.success(artifact == null ? null : _reload(artifact));
  }

  @override
  Future<EngineResult<List<PublishedTemplateArtifact>>> list() async {
    final reloaded = _stored.values.map(_reload).toList(growable: false);
    return EngineResult.success(
      List.unmodifiable(
        duplicateListEntries
            ? [...reloaded, ...reloaded.map(_reload)]
            : reloaded,
      ),
    );
  }

  PublishedTemplateArtifact _reload(PublishedTemplateArtifact artifact) =>
      PublishedTemplateArtifact(
        template: artifact.template,
        layoutProfile: artifact.layoutProfile,
        layout: artifact.layout,
        pdfBytes: artifact.pdfBytes,
      );

  String _key(TemplateId id, TemplateVersion version) =>
      '${id.value}:${version.value}';
}
