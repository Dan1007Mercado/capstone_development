import '../../core/errors/engine_error.dart';
import '../../core/ids/identifiers.dart';
import '../../core/result/engine_result.dart';
import 'published_template_artifact.dart';
import 'published_template_artifact_repository.dart';

/// Deterministic test/debug storage with the same non-overwrite contract.
final class InMemoryPublishedTemplateArtifactRepository
    implements PublishedTemplateArtifactRepository {
  final Map<String, PublishedTemplateArtifact> _artifacts = {};

  @override
  Future<EngineResult<PublishedTemplateArtifact>> save(
    PublishedTemplateArtifact artifact,
  ) async {
    final key = _key(artifact.templateId, artifact.templateVersion);
    if (_artifacts.containsKey(key)) {
      return EngineResult.failure(
        EngineError(
          code: 'TEMPLATE_VERSION_ALREADY_PUBLISHED',
          message: 'This exact template version is already published.',
          details: {
            'templateId': artifact.templateId.value,
            'templateVersion': artifact.templateVersion.value,
          },
        ),
      );
    }
    _artifacts[key] = artifact;
    return EngineResult.success(artifact);
  }

  @override
  Future<EngineResult<PublishedTemplateArtifact?>> get(
    TemplateId templateId,
    TemplateVersion templateVersion,
  ) async =>
      EngineResult.success(_artifacts[_key(templateId, templateVersion)]);

  @override
  Future<EngineResult<List<PublishedTemplateArtifact>>> list() async {
    final result = _artifacts.values.toList()
      ..sort((left, right) {
        final byName = left.template.name.compareTo(right.template.name);
        if (byName != 0) return byName;
        final byId = left.templateId.value.compareTo(right.templateId.value);
        if (byId != 0) return byId;
        return left.templateVersion.value.compareTo(
          right.templateVersion.value,
        );
      });
    return EngineResult.success(List.unmodifiable(result));
  }

  static String _key(TemplateId id, TemplateVersion version) =>
      '${id.value}\u0000${version.value}';
}
