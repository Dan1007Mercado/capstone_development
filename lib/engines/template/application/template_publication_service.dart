import '../../../core/errors/engine_error.dart';
import '../../../core/ids/identifiers.dart';
import '../../../core/result/engine_result.dart';
import '../domain/template_definition.dart';
import '../domain/template_status.dart';
import 'template_repository.dart';
import 'template_validator.dart';

/// Coordinates validation, version rules, and immutable persistence.
final class TemplatePublicationService {
  TemplatePublicationService({
    required TemplateRepository repository,
    TemplateValidator? validator,
  }) : _repository = repository,
       _validator = validator ?? TemplateValidator();

  final TemplateRepository _repository;
  final TemplateValidator _validator;

  Future<EngineResult<TemplateDefinition>> publish(
    TemplateDefinition draft,
  ) async {
    if (draft.status != TemplateStatus.draft) {
      return EngineResult.failure(
        _error(
          code: 'TEMPLATE_NOT_DRAFT',
          message: 'Only a draft template can be published.',
          template: draft,
        ),
      );
    }

    final validation = _validator.validate(draft);
    if (!validation.isValid) {
      return EngineResult.failure(
        _error(
          code: 'TEMPLATE_PUBLICATION_INVALID',
          message: 'The draft must be valid before publication.',
          template: draft,
          extraDetails: {
            'validationIssueCount': validation.errors.length,
            'validationIssues': [
              for (final issue in validation.errors)
                {
                  'code': issue.code,
                  'message': issue.message,
                  'path': issue.path,
                },
            ],
          },
        ),
      );
    }

    final existsResult = await _repository.publishedVersionExists(
      draft.id,
      draft.version,
    );
    if (existsResult.isFailure) {
      return EngineResult.failure(existsResult.error);
    }
    if (existsResult.value) {
      return EngineResult.failure(_alreadyPublished(draft));
    }

    final versionsResult = await _repository.listPublishedVersions(draft.id);
    if (versionsResult.isFailure) {
      return EngineResult.failure(versionsResult.error);
    }
    final versions = versionsResult.value;
    final minimumVersion = versions.isEmpty
        ? 1
        : versions.last.version.value + 1;
    if (draft.version.value < minimumVersion) {
      return EngineResult.failure(
        _error(
          code: 'TEMPLATE_REVISION_INVALID',
          message: 'A published template must be newer than stored history.',
          template: draft,
          extraDetails: {'minimumVersion': minimumVersion},
        ),
      );
    }

    final published = draft.toPublishedAfterValidation();
    final saveResult = await _repository.savePublished(published);
    if (saveResult.isFailure) {
      return EngineResult.failure(saveResult.error);
    }
    return EngineResult.success(saveResult.value);
  }

  EngineResult<TemplateDefinition> createRevision(
    TemplateDefinition published, {
    TemplateVersion? version,
  }) {
    if (published.status != TemplateStatus.published) {
      return EngineResult.failure(
        _error(
          code: 'TEMPLATE_REVISION_INVALID',
          message: 'Only a published template can start a revision.',
          template: published,
        ),
      );
    }
    final nextVersion = version ?? TemplateVersion(published.version.value + 1);
    if (nextVersion.value <= published.version.value) {
      return EngineResult.failure(
        _error(
          code: 'TEMPLATE_REVISION_INVALID',
          message: 'A revision version must exceed its published source.',
          template: published,
          extraDetails: {'requestedVersion': nextVersion.value},
        ),
      );
    }
    return EngineResult.success(published.createDraftRevision(nextVersion));
  }

  Future<EngineResult<TemplateDefinition?>> getPublished(
    TemplateId id,
    TemplateVersion version,
  ) => _repository.getPublished(id, version);

  Future<EngineResult<List<TemplateDefinition>>> listPublishedVersions(
    TemplateId id,
  ) => _repository.listPublishedVersions(id);

  EngineError _alreadyPublished(TemplateDefinition template) => _error(
    code: 'TEMPLATE_VERSION_ALREADY_PUBLISHED',
    message: 'This template version has already been published.',
    template: template,
  );

  EngineError _error({
    required String code,
    required String message,
    required TemplateDefinition template,
    Map<String, Object?> extraDetails = const {},
  }) => EngineError(
    code: code,
    message: message,
    details: {
      'templateId': template.id.value,
      'version': template.version.value,
      ...extraDetails,
    },
  );
}
