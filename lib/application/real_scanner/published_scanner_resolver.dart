import 'dart:typed_data';

import '../../core/errors/engine_error.dart';
import '../../core/ids/identifiers.dart';
import '../../core/result/engine_result.dart';
import '../published_templates/published_template_artifact.dart';
import '../published_templates/published_template_artifact_repository.dart';
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
    this.pdfBytes,
  });

  final TemplateDefinition template;
  final LayoutDocument layout;
  final Uint8List? pdfBytes;

  TemplateId get templateId => template.id;
  TemplateVersion get templateVersion => template.version;
}

/// Resolves scanner input only through immutable published history.
///
/// Durable artifacts provide their exact stored PageLayout. The legacy
/// semantic-only path remains available for older in-memory validation tests.
final class PublishedScannerResolver {
  PublishedScannerResolver({
    TemplatePublicationService? publicationService,
    PublishedTemplateArtifactRepository? artifactRepository,
    LayoutEngine? layoutEngine,
    LayoutConfig? layoutConfig,
  }) : assert(
         publicationService != null || artifactRepository != null,
         'A published artifact or legacy publication repository is required.',
       ),
       _publicationService = publicationService,
       _artifactRepository = artifactRepository,
       _layoutEngine = layoutEngine ?? LayoutEngine(),
       _layoutConfig = layoutConfig ?? LayoutConfig.a4Default();

  final TemplatePublicationService? _publicationService;
  final PublishedTemplateArtifactRepository? _artifactRepository;
  final LayoutEngine _layoutEngine;
  final LayoutConfig _layoutConfig;

  Future<EngineResult<List<PublishedScannerArtifact>>> listAvailable() async {
    final artifactRepository = _artifactRepository;
    if (artifactRepository != null) {
      final stored = await artifactRepository.list();
      if (stored.isFailure) return EngineResult.failure(stored.error);
      return EngineResult.success(
        List.unmodifiable(stored.value.map(_fromStoredArtifact)),
      );
    }

    final published = await _publicationService!.listPublishedTemplates();
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
    final artifactRepository = _artifactRepository;
    if (artifactRepository != null) {
      final stored = await artifactRepository.get(templateId, templateVersion);
      if (stored.isFailure) return EngineResult.failure(stored.error);
      final artifact = stored.value;
      if (artifact == null) return _notFound(templateId, templateVersion);
      return EngineResult.success(_fromStoredArtifact(artifact));
    }

    final result = await _publicationService!.getPublished(
      templateId,
      templateVersion,
    );
    if (result.isFailure) return EngineResult.failure(result.error);
    final template = result.value;
    if (template == null) return _notFound(templateId, templateVersion);
    return _build(template);
  }

  PublishedScannerArtifact _fromStoredArtifact(
    PublishedTemplateArtifact artifact,
  ) => PublishedScannerArtifact(
    template: artifact.template,
    layout: artifact.layout,
    pdfBytes: artifact.pdfBytes,
  );

  EngineResult<PublishedScannerArtifact> _notFound(
    TemplateId templateId,
    TemplateVersion templateVersion,
  ) => EngineResult.failure(
    EngineError(
      code: 'PUBLISHED_TEMPLATE_NOT_FOUND',
      message: 'The selected published template version was not found.',
      details: {
        'templateId': templateId.value,
        'templateVersion': templateVersion.value,
      },
    ),
  );

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
      if (layout.error.code == 'ARUCO_PAGE_ID_CAPACITY_EXCEEDED') {
        return EngineResult.failure(layout.error);
      }
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
