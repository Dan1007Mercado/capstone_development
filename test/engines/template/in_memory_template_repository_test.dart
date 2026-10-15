import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/template/infrastructure/in_memory_template_repository.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/domain/template_section.dart';
import 'package:capstone_development/engines/template/domain/template_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTemplateRepository repository;

  setUp(() => repository = InMemoryTemplateRepository());

  test('saves and retrieves the current draft', () async {
    final draft = _template(version: 2);

    expect((await repository.saveDraft(draft)).isSuccess, isTrue);
    final stored = await repository.getDraft(draft.id);

    expect(stored.value, draft);
    expect(stored.value!.status, TemplateStatus.draft);
  });

  test('stores multiple published versions in deterministic order', () async {
    final v2 = _published(version: 2, name: 'Second');
    final v1 = _published(version: 1, name: 'First');
    await repository.savePublished(v2);
    await repository.savePublished(v1);

    final versions = await repository.listPublishedVersions(v1.id);

    expect(versions.value.map((item) => item.version.value), [1, 2]);
    expect(
      (await repository.getPublished(v1.id, TemplateVersion(1))).value,
      v1,
    );
    expect(
      (await repository.getPublished(v1.id, TemplateVersion(2))).value,
      v2,
    );
    expect(
      (await repository.publishedVersionExists(
        v1.id,
        TemplateVersion(2),
      )).value,
      isTrue,
    );
  });

  test('published history cannot be overwritten', () async {
    final original = _published(version: 1, name: 'Original');
    await repository.savePublished(original);

    final duplicate = await repository.savePublished(
      _published(version: 1, name: 'Replacement'),
    );

    expect(duplicate.isFailure, isTrue);
    expect(duplicate.error.code, 'TEMPLATE_VERSION_ALREADY_PUBLISHED');
    expect(
      (await repository.getPublished(original.id, original.version)).value,
      original,
    );
  });

  test('unknown published version returns null', () async {
    final result = await repository.getPublished(
      TemplateId('missing'),
      TemplateVersion(9),
    );

    expect(result.isSuccess, isTrue);
    expect(result.value, isNull);
  });

  test(
    'returned history and definitions cannot corrupt stored versions',
    () async {
      final v1 = _published(version: 1, name: 'Original');
      await repository.savePublished(v1);
      final history = (await repository.listPublishedVersions(v1.id)).value;

      expect(() => history.add(_published(version: 2)), throwsUnsupportedError);
      expect(() => history.single.sections.clear(), throwsUnsupportedError);

      final revision = v1.createDraftRevision(TemplateVersion(2));
      final changed = revision.copyWith(name: 'Changed revision');
      await repository.saveDraft(changed);

      final storedV1 = await repository.getPublished(v1.id, v1.version);
      expect(storedV1.value!.name, 'Original');
      expect(storedV1.value, v1);
    },
  );

  test('repository rejects status misuse with structured errors', () async {
    final draftAsPublished = await repository.savePublished(_template());
    final publishedAsDraft = await repository.saveDraft(_published(version: 1));

    expect(draftAsPublished.isFailure, isTrue);
    expect(draftAsPublished.error.code, 'TEMPLATE_REPOSITORY_FAILURE');
    expect(publishedAsDraft.isFailure, isTrue);
    expect(publishedAsDraft.error.code, 'TEMPLATE_NOT_DRAFT');
  });
}

TemplateDefinition _published({int version = 1, String name = 'Survey'}) =>
    _template(version: version, name: name).toPublishedAfterValidation();

TemplateDefinition _template({int version = 1, String name = 'Survey'}) =>
    TemplateDefinition(
      id: TemplateId('employee-survey'),
      version: TemplateVersion(version),
      name: name,
      status: TemplateStatus.draft,
      sections: [TemplateSection(id: SectionId('section'), title: 'Section')],
    );
