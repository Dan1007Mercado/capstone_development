import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/template/application/template_publication_service.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/domain/template_option.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:capstone_development/engines/template/domain/template_section.dart';
import 'package:capstone_development/engines/template/domain/template_status.dart';
import 'package:capstone_development/engines/template/infrastructure/in_memory_template_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTemplateRepository repository;
  late TemplatePublicationService service;

  setUp(() {
    repository = InMemoryTemplateRepository();
    service = TemplatePublicationService(repository: repository);
  });

  test(
    'valid draft publishes without changing its source or identities',
    () async {
      final draft = _draft();

      final result = await service.publish(draft);

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      expect(result.value.status, TemplateStatus.published);
      expect(result.value.id, draft.id);
      expect(result.value.version, draft.version);
      expect(result.value.name, draft.name);
      expect(result.value.description, draft.description);
      expect(result.value.sections, draft.sections);
      expect(result.value.sections.single.id, draft.sections.single.id);
      expect(
        result.value.sections.single.questions.single.id,
        draft.sections.single.questions.single.id,
      );
      expect(
        result.value.sections.single.questions.single.options.map(
          (option) => option.id,
        ),
        draft.sections.single.questions.single.options.map(
          (option) => option.id,
        ),
      );
      expect(draft.status, TemplateStatus.draft);
    },
  );

  test('invalid draft cannot publish and reports validation details', () async {
    final result = await service.publish(_draft(name: ''));

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'TEMPLATE_PUBLICATION_INVALID');
    expect(result.error.details['validationIssueCount'], greaterThan(0));
    expect(
      await repository
          .listPublishedVersions(TemplateId('employee-survey'))
          .then((value) => value.value),
      isEmpty,
    );
  });

  test('published definition cannot be published as a draft', () async {
    final published = _draft().toPublishedAfterValidation();

    final result = await service.publish(published);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'TEMPLATE_NOT_DRAFT');
  });

  test('duplicate template ID and version is rejected', () async {
    final draft = _draft();
    expect((await service.publish(draft)).isSuccess, isTrue);

    final duplicate = await service.publish(draft);

    expect(duplicate.isFailure, isTrue);
    expect(duplicate.error.code, 'TEMPLATE_VERSION_ALREADY_PUBLISHED');
  });

  test(
    'explicitly higher revision publishes but history cannot go backward',
    () async {
      final publishedV1 = (await service.publish(_draft())).value;
      final draftV3 = service
          .createRevision(publishedV1, version: TemplateVersion(3))
          .value;
      expect((await service.publish(draftV3)).isSuccess, isTrue);
      final draftV2 = service
          .createRevision(publishedV1, version: TemplateVersion(2))
          .value;

      final result = await service.publish(draftV2);

      expect(result.isFailure, isTrue);
      expect(result.error.code, 'TEMPLATE_REVISION_INVALID');
      expect(result.error.details['minimumVersion'], 4);
    },
  );

  test(
    'published v1 creates editable v2 with preserved semantic IDs',
    () async {
      final publishedV1 = (await service.publish(_draft())).value;

      final result = service.createRevision(publishedV1);

      expect(result.isSuccess, isTrue);
      final draftV2 = result.value;
      expect(draftV2.id, publishedV1.id);
      expect(draftV2.version, TemplateVersion(2));
      expect(draftV2.status, TemplateStatus.draft);
      expect(draftV2.sections, publishedV1.sections);
      expect(
        draftV2.sections.single.questions.single.options,
        publishedV1.sections.single.questions.single.options,
      );

      final changedSection = draftV2.sections.single.copyWith(title: 'Changed');
      final changedV2 = draftV2.copyWith(sections: [changedSection]);
      expect(changedV2.sections.single.title, 'Changed');
      expect(publishedV1.sections.single.title, 'Workplace');
    },
  );

  test('same/lower revision and draft sources return typed failures', () async {
    final publishedV2 = _draft(version: 2).toPublishedAfterValidation();

    for (final version in [TemplateVersion(2), TemplateVersion(1)]) {
      final result = service.createRevision(publishedV2, version: version);
      expect(result.isFailure, isTrue);
      expect(result.error.code, 'TEMPLATE_REVISION_INVALID');
    }
    final draftResult = service.createRevision(_draft());
    expect(draftResult.isFailure, isTrue);
    expect(draftResult.error.code, 'TEMPLATE_REVISION_INVALID');
  });
}

TemplateDefinition _draft({String name = 'Employee Survey', int version = 1}) {
  final question = TemplateQuestion(
    id: QuestionId('satisfaction'),
    type: QuestionType.singleChoice,
    prompt: 'Are you satisfied?',
    options: [
      TemplateOption(id: OptionId('yes'), label: 'Yes'),
      TemplateOption(id: OptionId('no'), label: 'No'),
    ],
  );
  return TemplateDefinition(
    id: TemplateId('employee-survey'),
    version: TemplateVersion(version),
    name: name,
    description: 'Stable semantics',
    status: TemplateStatus.draft,
    sections: [
      TemplateSection(
        id: SectionId('workplace'),
        title: 'Workplace',
        questions: [question],
      ),
    ],
  );
}
