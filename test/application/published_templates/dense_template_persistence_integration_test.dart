import 'dart:convert';
import 'dart:io';

import 'package:capstone_development/application/published_templates/file_published_template_artifact_repository.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact_service.dart';
import 'package:capstone_development/application/real_scanner/published_scanner_resolver.dart';
import 'package:capstone_development/application/real_scanner/scanner_validation_session.dart';
import 'package:capstone_development/debug/p13_6_dense_validation_sheet.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/pdf/application/pdf_engine.dart';
import 'package:capstone_development/engines/template/domain/template_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'talaan-published-artifact-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'dense v1 survives repository restart with exact PDF and PageLayout',
    () async {
      final firstRepository = FilePublishedTemplateArtifactRepository(
        rootDirectory: temporaryDirectory,
      );
      final service = PublishedTemplateArtifactService(
        repository: firstRepository,
      );
      final published = await service.publish(
        draft: buildP13_6DenseValidationTemplate(),
        layoutConfig: LayoutConfig.a4Dense(),
      );

      expect(published.isSuccess, isTrue);
      final beforeRestart = published.value;
      expect(beforeRestart.template.status, TemplateStatus.published);
      expect(beforeRestart.layout.pages, hasLength(1));
      expect(
        beforeRestart.layout.pages.single.contentColumnRegions,
        hasLength(3),
      );
      expect(beforeRestart.layout.pages.single.bubbleRegions, hasLength(160));

      // A fresh repository and resolver represent a complete app restart.
      final restartedRepository = FilePublishedTemplateArtifactRepository(
        rootDirectory: temporaryDirectory,
      );
      final resolver = PublishedScannerResolver(
        artifactRepository: restartedRepository,
      );
      final available = await resolver.listAvailable();
      final resolved = await resolver.resolve(
        templateId: beforeRestart.templateId,
        templateVersion: beforeRestart.templateVersion,
      );
      final reloaded = await restartedRepository.get(
        beforeRestart.templateId,
        beforeRestart.templateVersion,
      );

      expect(available.value, hasLength(1));
      expect(resolved.isSuccess, isTrue);
      expect(reloaded.value, isNotNull);
      expect(reloaded.value!.template, beforeRestart.template);
      expect(reloaded.value!.layout, beforeRestart.layout);
      expect(reloaded.value!.pdfBytes, beforeRestart.pdfBytes);
      expect(resolved.value.layout, beforeRestart.layout);

      final scannerSession = ScannerValidationSession.start(
        artifact: resolved.value,
      );
      expect(
        scannerSession.currentContext.pageLayout,
        same(resolved.value.layout.pages.single),
      );
      expect(
        scannerSession.currentContext.pageLayout,
        beforeRestart.layout.pages.single,
      );

      final pdfPlan = PdfEngine()
          .buildPlan(reloaded.value!.template, reloaded.value!.layout)
          .value;
      expect(
        pdfPlan.pages.single.layout,
        same(reloaded.value!.layout.pages.single),
      );
    },
  );

  test('published version cannot be overwritten', () async {
    final repository = FilePublishedTemplateArtifactRepository(
      rootDirectory: temporaryDirectory,
    );
    final service = PublishedTemplateArtifactService(repository: repository);
    final draft = buildP13_6DenseValidationTemplate();

    expect(
      (await service.publish(
        draft: draft,
        layoutConfig: LayoutConfig.a4Dense(),
      )).isSuccess,
      isTrue,
    );
    final duplicate = await service.publish(
      draft: draft,
      layoutConfig: LayoutConfig.a4Dense(),
    );

    expect(duplicate.error.code, 'TEMPLATE_VERSION_ALREADY_PUBLISHED');
  });

  test('modified PDF fails integrity validation', () async {
    final repository = FilePublishedTemplateArtifactRepository(
      rootDirectory: temporaryDirectory,
    );
    final service = PublishedTemplateArtifactService(repository: repository);
    final artifact = (await service.publish(
      draft: buildP13_6DenseValidationTemplate(),
      layoutConfig: LayoutConfig.a4Dense(),
    )).value;
    final pdf = await _findArtifactFile(
      temporaryDirectory,
      FilePublishedTemplateArtifactRepository.pdfFileName,
    );
    await pdf.writeAsBytes([1, 2, 3], flush: true);

    final result = await repository.get(
      artifact.templateId,
      artifact.templateVersion,
    );

    expect(result.error.code, 'PUBLISHED_ARTIFACT_INTEGRITY_FAILED');
  });

  test(
    'modified template or geometry manifest fails integrity validation',
    () async {
      final repository = FilePublishedTemplateArtifactRepository(
        rootDirectory: temporaryDirectory,
      );
      final service = PublishedTemplateArtifactService(repository: repository);
      final artifact = (await service.publish(
        draft: buildP13_6DenseValidationTemplate(),
        layoutConfig: LayoutConfig.a4Dense(),
      )).value;
      final manifestFile = await _findArtifactFile(
        temporaryDirectory,
        FilePublishedTemplateArtifactRepository.manifestFileName,
      );
      final manifest = Map<String, Object?>.from(
        jsonDecode(await manifestFile.readAsString()) as Map,
      );
      final encoded = Map<String, Object?>.from(manifest['artifact']! as Map);
      final template = Map<String, Object?>.from(encoded['template']! as Map);
      template['name'] = 'Modified after publication';
      encoded['template'] = template;
      manifest['artifact'] = encoded;
      await manifestFile.writeAsString(jsonEncode(manifest), flush: true);

      final result = await repository.get(
        artifact.templateId,
        artifact.templateVersion,
      );

      expect(result.error.code, 'PUBLISHED_ARTIFACT_INTEGRITY_FAILED');
    },
  );
}

Future<File> _findArtifactFile(Directory root, String fileName) => root
    .list(recursive: true)
    .where(
      (entity) =>
          entity is File &&
          entity.path.endsWith('${Platform.pathSeparator}$fileName'),
    )
    .cast<File>()
    .single;
