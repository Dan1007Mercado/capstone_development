import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:capstone_development/application/camera_scanner/domain/camera_scan_context.dart';
import 'package:capstone_development/application/published_templates/file_published_template_artifact_repository.dart';
import 'package:capstone_development/application/published_templates/in_memory_published_template_artifact_repository.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact_codec.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact_service.dart';
import 'package:capstone_development/application/template_builder/template_builder_controller.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/engines/layout/application/layout_engine.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/layout/domain/layout_regions.dart';
import 'package:capstone_development/engines/pdf/application/pdf_engine.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'publishes the current template with exact answer-sheet geometry and PDF',
    () async {
      final repository = InMemoryPublishedTemplateArtifactRepository();
      final service = PublishedTemplateArtifactService(repository: repository);
      final controller = _customController();
      final draft = controller.buildDefinition();
      final expectedLayout = LayoutEngine()
          .build(draft, LayoutConfig.a4AnswerSheet())
          .value;

      final result = await service.publish(
        draft: draft,
        layoutConfig: LayoutConfig.a4AnswerSheet(),
      );

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      final artifact = result.value;
      expect(artifact.templateId, TemplateId('researcher-current-template'));
      expect(artifact.template.name, 'Researcher Current Template');
      expect(artifact.template.status, TemplateStatus.published);
      expect(artifact.layoutProfile, LayoutProfile.answerSheet);
      expect(artifact.layout, expectedLayout);
      expect(artifact.pdfBytes, isNotEmpty);
      expect(ascii.decode(artifact.pdfBytes.take(5).toList()), '%PDF-');

      for (var index = 0; index < artifact.layout.pages.length; index++) {
        final publishedPage = artifact.layout.pages[index];
        final expectedPage = expectedLayout.pages[index];
        expect(publishedPage, expectedPage);
        expect(publishedPage.questionRegions, expectedPage.questionRegions);
        expect(publishedPage.bubbleRegions, expectedPage.bubbleRegions);
        expect(
          publishedPage.bubbleRegions.map((bubble) => bubble.physicalBounds),
          expectedPage.bubbleRegions.map((bubble) => bubble.physicalBounds),
        );
        expect(
          publishedPage.bubbleRegions.map((bubble) => bubble.normalizedBounds),
          expectedPage.bubbleRegions.map((bubble) => bubble.normalizedBounds),
        );
        expect(
          publishedPage.bubbleRegions.map((bubble) => bubble.printedLabel),
          expectedPage.bubbleRegions.map((bubble) => bubble.printedLabel),
        );
        expect(
          publishedPage.bubbleRegions.map(
            (bubble) => bubble.measurementCenterExclusionRatio,
          ),
          expectedPage.bubbleRegions.map(
            (bubble) => bubble.measurementCenterExclusionRatio,
          ),
        );
        expect(
          CameraScanContext(
            template: artifact.template,
            pageLayout: publishedPage,
            templateId: artifact.templateId,
            templateVersion: artifact.templateVersion,
            pageId: publishedPage.pageId,
            scannerConfig: ScannerConfig(),
            candidatePageLayouts: artifact.layout.pages,
          ).validate(),
          isNull,
        );
      }

      final plan = PdfEngine()
          .buildPlan(artifact.template, artifact.layout)
          .value;
      expect(plan.pages, hasLength(artifact.layout.pages.length));
      for (var index = 0; index < plan.pages.length; index++) {
        expect(plan.pages[index].layout, same(artifact.layout.pages[index]));
      }
      expect(
        artifact.layout.pages
            .expand((page) => page.questionRegions)
            .every(
              (question) =>
                  question.renderMode ==
                      QuestionRenderMode.answerSheetHorizontal ||
                  question.renderMode ==
                      QuestionRenderMode.answerSheetNumericGrid,
            ),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'codec round-trip retains all p14.2 profile and region fields',
    () async {
      final service = PublishedTemplateArtifactService(
        repository: InMemoryPublishedTemplateArtifactRepository(),
        pdfRenderer: (_, _) async =>
            EngineResult.success(Uint8List.fromList([37, 80, 68, 70, 45])),
      );
      final artifact = (await service.publish(
        draft: _customController().buildDefinition(),
        layoutConfig: LayoutConfig.a4AnswerSheet(),
      )).value;
      const codec = PublishedTemplateArtifactCodec();

      final restored = codec.decode(
        codec.encode(
          template: artifact.template,
          layoutProfile: artifact.layoutProfile,
          layout: artifact.layout,
        ),
      );

      expect(restored.template, artifact.template);
      expect(restored.layoutProfile, LayoutProfile.answerSheet);
      expect(restored.layout, artifact.layout);
      for (var index = 0; index < artifact.layout.pages.length; index++) {
        final originalPage = artifact.layout.pages[index];
        final restoredPage = restored.layout.pages[index];
        expect(restoredPage.questionRegions, originalPage.questionRegions);
        expect(restoredPage.bubbleRegions, originalPage.bubbleRegions);
        expect(
          restoredPage.questionRegions.map((item) => item.questionNumber),
          originalPage.questionRegions.map((item) => item.questionNumber),
        );
        expect(
          restoredPage.questionRegions.map((item) => item.answerGroupLabel),
          originalPage.questionRegions.map((item) => item.answerGroupLabel),
        );
        expect(
          restoredPage.questionRegions.map((item) => item.renderMode),
          originalPage.questionRegions.map((item) => item.renderMode),
        );
      }
    },
  );

  test('schema-v1 dense artifacts retain their legacy profile identity', () {
    final draft = _customController().buildDefinition();
    final published = draft.toPublishedAfterValidation();
    final layout = LayoutEngine()
        .build(published, LayoutConfig.a4Dense())
        .value;
    const codec = PublishedTemplateArtifactCodec();
    final legacy =
        codec.encode(
            template: published,
            layoutProfile: LayoutProfile.dense,
            layout: layout,
          )
          ..['schemaVersion'] = 1
          ..remove('layoutProfile');

    final restored = codec.decode(legacy);

    expect(restored.layoutProfile, LayoutProfile.dense);
    expect(restored.layout, layout);
  });

  test(
    'file round-trip retains answer-sheet PDF, profile, and layout',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'talaan-answer-sheet-artifact-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final repository = FilePublishedTemplateArtifactRepository(
        rootDirectory: directory,
      );
      final bytes = Uint8List.fromList([37, 80, 68, 70, 45, 1, 2, 3]);
      final service = PublishedTemplateArtifactService(
        repository: repository,
        pdfRenderer: (_, _) async => EngineResult.success(bytes),
      );
      final published = (await service.publish(
        draft: _customController().buildDefinition(),
        layoutConfig: LayoutConfig.a4AnswerSheet(),
      )).value;

      final restoredRepository = FilePublishedTemplateArtifactRepository(
        rootDirectory: directory,
      );
      final restored = (await restoredRepository.get(
        published.templateId,
        published.templateVersion,
      )).value!;

      expect(restored.layoutProfile, LayoutProfile.answerSheet);
      expect(restored.template, published.template);
      expect(restored.layout, published.layout);
      expect(restored.pdfBytes, bytes);
    },
  );

  test('multi-page publication preserves ordered page identities', () async {
    final controller = TemplateBuilderController(
      templateId: TemplateId('long-answer-sheet'),
      name: 'Long Answer Sheet',
    );
    final section = controller.addSection(title: 'All Answers');
    for (var index = 0; index < 130; index++) {
      controller.addQuestion(
        section,
        type: QuestionType.yesNo,
        prompt: 'Question ${index + 1}',
      );
    }
    final service = PublishedTemplateArtifactService(
      repository: InMemoryPublishedTemplateArtifactRepository(),
      pdfRenderer: (_, _) async =>
          EngineResult.success(Uint8List.fromList([37, 80, 68, 70, 45])),
    );

    final artifact = (await service.publish(
      draft: controller.buildDefinition(),
      layoutConfig: LayoutConfig.a4AnswerSheet(),
    )).value;

    expect(artifact.layout.pages.length, greaterThan(1));
    for (var index = 0; index < artifact.layout.pages.length; index++) {
      final page = artifact.layout.pages[index];
      expect(page.pageIndex, index);
      expect(page.totalPageCount, artifact.layout.pages.length);
      expect(page.pageId.value, 'long-answer-sheet-v1-p${index + 1}');
      expect(page.templateId, artifact.templateId);
      expect(page.templateVersion, artifact.templateVersion);
    }
  });

  test(
    'published answer-sheet revisions remain independently retrievable',
    () async {
      final repository = InMemoryPublishedTemplateArtifactRepository();
      final service = PublishedTemplateArtifactService(
        repository: repository,
        pdfRenderer: (template, _) async => EngineResult.success(
          Uint8List.fromList([37, 80, 68, 70, template.version.value]),
        ),
      );
      final v1 = (await service.publish(
        draft: _customController().buildDefinition(),
        layoutConfig: LayoutConfig.a4AnswerSheet(),
      )).value;
      final v2Controller = TemplateBuilderController.fromDraft(
        v1.template.createNextDraftRevision(),
      )..updateName('Researcher Current Template Revised');
      final v2 = (await service.publish(
        draft: v2Controller.buildDefinition(),
        layoutConfig: LayoutConfig.a4AnswerSheet(),
      )).value;

      final storedV1 = (await service.get(
        v1.templateId,
        v1.templateVersion,
      )).value!;
      final storedV2 = (await service.get(
        v2.templateId,
        v2.templateVersion,
      )).value!;
      expect(storedV1.template.name, 'Researcher Current Template');
      expect(storedV2.template.name, 'Researcher Current Template Revised');
      expect(storedV1.layout.pages.first.pageId.value, endsWith('-v1-p1'));
      expect(storedV2.layout.pages.first.pageId.value, endsWith('-v2-p1'));
      expect(storedV1.pdfBytes, isNot(storedV2.pdfBytes));
      expect((await service.list()).value, hasLength(2));
    },
  );

  test('invalid publication does not persist a partial artifact', () async {
    final repository = InMemoryPublishedTemplateArtifactRepository();
    final service = PublishedTemplateArtifactService(repository: repository);
    final invalid = TemplateBuilderController(
      templateId: TemplateId('invalid-answer-sheet'),
      name: '',
    ).buildDefinition();

    final result = await service.publish(
      draft: invalid,
      layoutConfig: LayoutConfig.a4AnswerSheet(),
    );

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'TEMPLATE_PUBLICATION_INVALID');
    expect((await repository.list()).value, isEmpty);
  });
}

TemplateBuilderController _customController() {
  final controller = TemplateBuilderController(
    templateId: TemplateId('researcher-current-template'),
    name: 'Researcher Current Template',
  );
  final section = controller.addSection(title: 'Current Responses');
  controller.addQuestion(
    section,
    type: QuestionType.singleChoice,
    prompt: 'Current single choice',
  );
  controller.addQuestion(
    section,
    type: QuestionType.likert,
    prompt: 'Current rating',
  );
  controller.addQuestion(
    section,
    type: QuestionType.yesNo,
    prompt: 'Current yes or no',
  );
  controller.addQuestion(
    section,
    type: QuestionType.numericGrid,
    prompt: 'Current numeric identifier',
  );
  return controller;
}
