import '../../core/ids/identifiers.dart';
import '../../core/result/engine_result.dart';
import 'published_template_artifact.dart';

/// Persistence boundary for exact immutable publication artifacts.
abstract interface class PublishedTemplateArtifactRepository {
  Future<EngineResult<PublishedTemplateArtifact>> save(
    PublishedTemplateArtifact artifact,
  );

  Future<EngineResult<PublishedTemplateArtifact?>> get(
    TemplateId templateId,
    TemplateVersion templateVersion,
  );

  Future<EngineResult<List<PublishedTemplateArtifact>>> list();
}
