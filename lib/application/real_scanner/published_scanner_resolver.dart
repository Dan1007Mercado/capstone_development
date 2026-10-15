import '../../core/errors/engine_error.dart';
import '../../core/ids/identifiers.dart';
import '../../core/result/engine_result.dart';
import '../../engines/layout/application/layout_engine.dart';
import '../../engines/layout/domain/layout_config.dart';
import '../../engines/layout/domain/page_layout.dart';
import '../../engines/template/application/template_publication_service.dart';
import '../../engines/template/domain/template_definition.dart';
import '../../engines/template/domain/template_status.dart';

/// Exact semantic and geometric artifact selected for a real scanner run.
final class PublishedScannerArtifact {
  const PublishedScannerArtifact({
    required this.template,
    required this.layout,
  });

  final TemplateDefinition template;
  final LayoutDocument layout;

  TemplateId get templateId => template.id;
  TemplateVersion get templateVersion => template.version;
}

/// Resolves scanner input only through immutable published history.
///
/// P13 stores semantic versions, so P13.5 deterministically reconstructs the
/// layout with the same authoritative engine/config used by PDF generation.
final class PublishedScannerResolver {
  PublishedScannerResolver({
    required TemplatePublicationService publicationService,
    LayoutEngine? layoutEngine,
    LayoutConfig? layoutConfig,
  }) : _publicationService = publicationService,
       _layoutEngine = layoutEngine ?? LayoutEngine(),
       _layoutConfig = layoutConfig ?? LayoutConfig.a4Default();

  final TemplatePublicationService _publicationService;
  final LayoutEngine _layoutEngine;
  final LayoutConfig _layoutConfig;

  Future<EngineResult<List<PublishedScannerArtifact>>> listAvailable() async {
    final published = await _publicationService.listPublishedTemplates();
    if (published.isFailure) return EngineResult.failure(published.error);
    final artifacts = <PublishedScannerArtifact>[];
    for (final template in published.value) {
      final resolved = _build(template);
      if (resolved.isFailure) return EngineResult.failure(resolved.error);
      artifacts.add(resolved.value);
    }
    artifacts.sort((left, right) {
      final byName = left.template.name.compareTo(right.template.name);
      if (byName != 0) return byName;
      final byId = left.templateId.value.compareTo(right.templateId.value);
      if (byId != 0) return byId;
      return left.templateVersion.value.compareTo(right.templateVersion.value);
    });
    return EngineResult.success(List.unmodifiable(artifacts));
  }

  Future<EngineResult<PublishedScannerArtifact>> resolve({
    required TemplateId templateId,
    required TemplateVersion templateVersion,
  }) async {
    final result = await _publicationService.getPublished(
      templateId,
      templateVersion,
    );
    if (result.isFailure) return EngineResult.failure(result.error);
    final template = result.value;
    if (template == null) {
      return EngineResult.failure(
        EngineError(
          code: 'PUBLISHED_TEMPLATE_NOT_FOUND',
          message: 'The selected published template version was not found.',
          details: {
            'templateId': templateId.value,
            'templateVersion': templateVersion.value,
          },
        ),
      );
    }
    return _build(template);
  }

  EngineResult<PublishedScannerArtifact> _build(TemplateDefinition template) {
    if (template.status != TemplateStatus.published) {
      return EngineResult.failure(
        EngineError(
          code: 'PUBLISHED_TEMPLATE_NOT_FOUND',
          message: 'Scanner selection requires an immutable published version.',
          details: {
            'templateId': template.id.value,
            'templateVersion': template.version.value,
          },
        ),
      );
    }
    final layout = _layoutEngine.build(template, _layoutConfig);
    if (layout.isFailure) {
      return EngineResult.failure(
        EngineError(
          code: 'PAGE_LAYOUT_NOT_FOUND',
          message: 'The selected published version has no valid PageLayout.',
          details: {
            'templateId': template.id.value,
            'templateVersion': template.version.value,
            'causeCode': layout.error.code,
            'causeMessage': layout.error.message,
            'causeDetails': layout.error.details,
          },
        ),
      );
    }
    if (layout.value.pages.isEmpty) {
      return EngineResult.failure(
        EngineError(
          code: 'PAGE_LAYOUT_NOT_FOUND',
          message: 'The published layout contains no scanner pages.',
          details: {
            'templateId': template.id.value,
            'templateVersion': template.version.value,
          },
        ),
      );
    }
    return EngineResult.success(
      PublishedScannerArtifact(template: template, layout: layout.value),
    );
  }
}
