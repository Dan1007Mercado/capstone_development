import 'dart:convert';

import 'package:capstone_development/application/template_builder/template_builder_controller.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/layout/application/layout_engine.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/pdf/application/pdf_engine.dart';
import 'package:capstone_development/engines/template/application/template_publication_service.dart';
import 'package:capstone_development/engines/template/infrastructure/in_memory_template_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('published versions retain exact layout and PDF identity', () async {
    final repository = InMemoryTemplateRepository();
    final publication = TemplatePublicationService(repository: repository);
    final controller = TemplateBuilderController(
      templateId: TemplateId('employee-survey'),
      name: 'Employee Survey',
    );
    final section = controller.addSection(title: 'Workplace');
    controller.addQuestion(section, prompt: 'Are you satisfied?');

    final publishedV1 = (await publication.publish(
      controller.buildDefinition(),
    )).value;
    final draftV2 = publication.createRevision(publishedV1).value;
    final publishedV2 = (await publication.publish(draftV2)).value;

    final layoutEngine = LayoutEngine();
    final config = LayoutConfig.a4Default();
    final layoutV1 = layoutEngine.build(publishedV1, config).value;
    final layoutV1Again = layoutEngine.build(publishedV1, config).value;
    final layoutV2 = layoutEngine.build(publishedV2, config).value;

    expect(layoutV1, layoutV1Again);
    expect(layoutV1.pages.single.pageId.value, 'employee-survey-v1-p1');
    expect(layoutV2.pages.single.pageId.value, 'employee-survey-v2-p1');
    expect(layoutV1.pages.single.markerRegions.map((item) => item.markerId), [
      10,
      11,
      12,
      13,
    ]);
    expect(layoutV2.pages.single.markerRegions.map((item) => item.markerId), [
      10,
      11,
      12,
      13,
    ]);
    expect(
      layoutV2.pages.single.bubbleRegions.map((item) => item.physicalBounds),
      layoutV1.pages.single.bubbleRegions.map((item) => item.physicalBounds),
    );

    final pdfEngine = PdfEngine();
    final planV1 = pdfEngine.buildPlan(publishedV1, layoutV1).value;
    final planV2 = pdfEngine.buildPlan(publishedV2, layoutV2).value;
    expect(
      planV1.pages.single.identity.payload,
      'TS1|employee-survey|1|employee-survey-v1-p1',
    );
    expect(
      planV2.pages.single.identity.payload,
      'TS1|employee-survey|2|employee-survey-v2-p1',
    );
    final pdfV1 = await pdfEngine.render(publishedV1, layoutV1);
    final pdfV2 = await pdfEngine.render(publishedV2, layoutV2);
    expect(pdfV1.isSuccess, isTrue, reason: pdfV1.errorOrNull?.toString());
    expect(pdfV2.isSuccess, isTrue, reason: pdfV2.errorOrNull?.toString());
    expect(ascii.decode(pdfV1.value.take(5).toList()), '%PDF-');
    expect(ascii.decode(pdfV2.value.take(5).toList()), '%PDF-');

    final storedV1 = await publication.getPublished(
      publishedV1.id,
      publishedV1.version,
    );
    final versions = await publication.listPublishedVersions(publishedV1.id);
    expect(storedV1.value, publishedV1);
    expect(versions.value, [publishedV1, publishedV2]);
  });
}
