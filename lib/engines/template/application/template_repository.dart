import '../../../core/ids/identifiers.dart';
import '../../../core/result/engine_result.dart';
import '../domain/template_definition.dart';

/// Persistence boundary for editable drafts and immutable published history.
abstract interface class TemplateRepository {
  Future<EngineResult<TemplateDefinition>> saveDraft(TemplateDefinition draft);

  Future<EngineResult<TemplateDefinition?>> getDraft(TemplateId id);

  Future<EngineResult<TemplateDefinition?>> getPublished(
    TemplateId id,
    TemplateVersion version,
  );

  Future<EngineResult<List<TemplateDefinition>>> listPublishedVersions(
    TemplateId id,
  );

  Future<EngineResult<TemplateDefinition>> savePublished(
    TemplateDefinition published,
  );

  Future<EngineResult<bool>> publishedVersionExists(
    TemplateId id,
    TemplateVersion version,
  );
}
