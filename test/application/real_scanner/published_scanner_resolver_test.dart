import 'package:capstone_development/application/real_scanner/published_scanner_resolver.dart';
import 'package:capstone_development/application/real_scanner/scanner_validation_session.dart';
import 'package:capstone_development/application/template_builder/template_builder_controller.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/pdf/application/pdf_engine.dart';
import 'package:capstone_development/engines/template/application/template_publication_service.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/infrastructure/in_memory_template_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TemplatePublicationService publication;
  late PublishedScannerResolver resolver;

  setUp(() {
    publication = TemplatePublicationService(
      repository: InMemoryTemplateRepository(),
    );
    resolver = PublishedScannerResolver(publicationService: publication);
  });

  test('one-page published template matches PDF and scanner context', () async {
    final published = await _publish(publication, _realTemplate());
    final artifact = (await resolver.resolve(
      templateId: published.id,
      templateVersion: published.version,
    )).value;
    final pdf = PdfEngine().buildPlan(published, artifact.layout).value;
    final session = ScannerValidationSession.start(artifact: artifact);

    expect(artifact.layout.pages, hasLength(1));
    expect(pdf.pages, hasLength(1));
    expect(pdf.pages.single.layout, same(artifact.layout.pages.single));
    expect(session.currentContext.template, same(published));
    expect(
      session.currentContext.pageLayout,
      same(artifact.layout.pages.single),
    );
    expect(
      pdf.pages.single.identity.payload,
      'TS1|real-survey|1|real-survey-v1-p1',
    );
  });

  test(
    'multi-page published layout and PDF expose identical ordered pages',
    () async {
      final controller = _realTemplate(templateId: 'long-survey');
      final section = controller.snapshot.definition.sections.first.id;
      for (var index = 0; index < 20; index++) {
        controller.addQuestion(
          section,
          type: index.isEven
              ? QuestionType.multipleChoice
              : QuestionType.likert,
          prompt: 'Additional production question $index',
        );
      }
      final published = await _publish(publication, controller);
      final artifact = (await resolver.resolve(
        templateId: published.id,
        templateVersion: published.version,
      )).value;
      final pdf = PdfEngine().buildPlan(published, artifact.layout).value;

      expect(artifact.layout.pages.length, greaterThan(1));
      expect(
        pdf.pages.map((page) => page.layout.pageId),
        artifact.layout.pages.map((page) => page.pageId),
      );
      for (var index = 0; index < artifact.layout.pages.length; index++) {
        expect(
          pdf.pages[index].identity.payload,
          'TS1|long-survey|1|long-survey-v1-p${index + 1}',
        );
      }
    },
  );

  test('published versions remain distinct scanner artifacts', () async {
    final v1 = await _publish(publication, _realTemplate());
    final draftV2 = publication.createRevision(v1).value;
    await publication.publish(draftV2);

    final available = (await resolver.listAvailable()).value;

    expect(available.map((item) => item.templateVersion.value), [1, 2]);
    expect(available[0].layout.pages.single.pageId.value, 'real-survey-v1-p1');
    expect(available[1].layout.pages.single.pageId.value, 'real-survey-v2-p1');
  });

  test('unknown exact version returns typed not-found failure', () async {
    await _publish(publication, _realTemplate());

    final result = await resolver.resolve(
      templateId: TemplateId('real-survey'),
      templateVersion: TemplateVersion(2),
    );

    expect(result.error.code, 'PUBLISHED_TEMPLATE_NOT_FOUND');
  });
}

TemplateBuilderController _realTemplate({String templateId = 'real-survey'}) {
  final controller = TemplateBuilderController(
    templateId: TemplateId(templateId),
    name: 'Real Published Survey',
  );
  final section = controller.addSection(title: 'Responses');
  controller.addQuestion(
    section,
    type: QuestionType.singleChoice,
    prompt: 'Choose one response.',
  );
  controller.addQuestion(
    section,
    type: QuestionType.multipleChoice,
    prompt: 'Choose every applicable response.',
  );
  controller.addQuestion(
    section,
    type: QuestionType.likert,
    prompt: 'Rate your experience.',
  );
  controller.addQuestion(
    section,
    type: QuestionType.yesNo,
    prompt: 'Would you continue?',
  );
  controller.addQuestion(
    section,
    type: QuestionType.numericGrid,
    prompt: 'Enter the assigned number.',
  );
  return controller;
}

Future<TemplateDefinition> _publish(
  TemplatePublicationService publication,
  TemplateBuilderController controller,
) async => (await publication.publish(controller.buildDefinition())).value;
