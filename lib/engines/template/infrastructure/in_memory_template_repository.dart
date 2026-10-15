import 'dart:collection';

import '../../../core/errors/engine_error.dart';
import '../../../core/ids/identifiers.dart';
import '../../../core/result/engine_result.dart';
import '../application/template_repository.dart';
import '../domain/template_definition.dart';
import '../domain/template_status.dart';

/// Deterministic process-local storage for drafts and published history.
final class InMemoryTemplateRepository implements TemplateRepository {
  final Map<TemplateId, TemplateDefinition> _drafts = {};
  final Map<TemplateId, SplayTreeMap<int, TemplateDefinition>> _published = {};

  @override
  Future<EngineResult<TemplateDefinition>> saveDraft(
    TemplateDefinition draft,
  ) async {
    if (draft.status != TemplateStatus.draft) {
      return EngineResult.failure(
        _statusError(
          code: 'TEMPLATE_NOT_DRAFT',
          message: 'The draft repository accepts only draft templates.',
          template: draft,
        ),
      );
    }
    _drafts[draft.id] = draft;
    return EngineResult.success(draft);
  }

  @override
  Future<EngineResult<TemplateDefinition?>> getDraft(TemplateId id) async =>
      EngineResult.success(_drafts[id]);

  @override
  Future<EngineResult<TemplateDefinition?>> getPublished(
    TemplateId id,
    TemplateVersion version,
  ) async => EngineResult.success(_published[id]?[version.value]);

  @override
  Future<EngineResult<List<TemplateDefinition>>> listPublishedVersions(
    TemplateId id,
  ) async => EngineResult.success(
    List<TemplateDefinition>.unmodifiable(
      _published[id]?.values ?? const <TemplateDefinition>[],
    ),
  );

  @override
  Future<EngineResult<List<TemplateDefinition>>>
  listPublishedTemplates() async => EngineResult.success(
    List<TemplateDefinition>.unmodifiable([
      for (final entry in _published.entries)
        for (final template in entry.value.values) template,
    ]),
  );

  @override
  Future<EngineResult<TemplateDefinition>> savePublished(
    TemplateDefinition published,
  ) async {
    if (published.status != TemplateStatus.published) {
      return EngineResult.failure(
        _statusError(
          code: 'TEMPLATE_REPOSITORY_FAILURE',
          message: 'Published history accepts only published templates.',
          template: published,
        ),
      );
    }
    final versions = _published.putIfAbsent(
      published.id,
      () => SplayTreeMap<int, TemplateDefinition>(),
    );
    if (versions.containsKey(published.version.value)) {
      return EngineResult.failure(
        _statusError(
          code: 'TEMPLATE_VERSION_ALREADY_PUBLISHED',
          message: 'Published template versions cannot be overwritten.',
          template: published,
        ),
      );
    }
    versions[published.version.value] = published;
    return EngineResult.success(published);
  }

  @override
  Future<EngineResult<bool>> publishedVersionExists(
    TemplateId id,
    TemplateVersion version,
  ) async =>
      EngineResult.success(_published[id]?.containsKey(version.value) ?? false);

  EngineError _statusError({
    required String code,
    required String message,
    required TemplateDefinition template,
  }) => EngineError(
    code: code,
    message: message,
    details: {
      'templateId': template.id.value,
      'version': template.version.value,
      'status': template.status.name,
    },
  );
}
