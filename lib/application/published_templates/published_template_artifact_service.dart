import 'dart:typed_data';

import '../../core/errors/engine_error.dart';
import '../../core/ids/identifiers.dart';
import '../../core/result/engine_result.dart';
import '../../engines/layout/application/layout_engine.dart';
import '../../engines/layout/domain/layout_config.dart';
import '../../engines/layout/domain/page_layout.dart';
import '../../engines/pdf/application/pdf_engine.dart';
import '../../engines/template/application/template_validator.dart';
import '../../engines/template/domain/template_definition.dart';
import '../../engines/template/domain/template_status.dart';
import 'published_template_artifact.dart';
import 'published_template_artifact_repository.dart';

typedef PublishedArtifactPdfRenderer =
    Future<EngineResult<Uint8List>> Function(
      TemplateDefinition template,
      LayoutDocument layout,
    );

/// Publishes semantics, exact geometry, and printable bytes as one aggregate.
final class PublishedTemplateArtifactService {
  PublishedTemplateArtifactService({
    required PublishedTemplateArtifactRepository repository,
    TemplateValidator? validator,
    LayoutEngine? layoutEngine,
    PdfEngine? pdfEngine,
    PublishedArtifactPdfRenderer? pdfRenderer,
  }) : _repository = repository,
       _validator = validator ?? TemplateValidator(),
       _layoutEngine = layoutEngine ?? LayoutEngine(),
       _pdfRenderer = pdfRenderer ?? (pdfEngine ?? PdfEngine()).render;

  final PublishedTemplateArtifactRepository _repository;
  final TemplateValidator _validator;
  final LayoutEngine _layoutEngine;
  final PublishedArtifactPdfRenderer _pdfRenderer;

  Future<EngineResult<PublishedTemplateArtifact>> publish({
    required TemplateDefinition draft,
    required LayoutConfig layoutConfig,
  }) async {
    if (draft.status != TemplateStatus.draft) {
      return EngineResult.failure(
        _error(
          code: 'TEMPLATE_NOT_DRAFT',
          message: 'Only a draft template can be published.',
          draft: draft,
        ),
      );
    }

    final validation = _validator.validate(draft);
    if (!validation.isValid) {
      return EngineResult.failure(
        _error(
          code: 'TEMPLATE_PUBLICATION_INVALID',
          message: 'The draft must be valid before publication.',
          draft: draft,
          extraDetails: {
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

    final existing = await _repository.get(draft.id, draft.version);
    if (existing.isFailure) return EngineResult.failure(existing.error);
    if (existing.value != null) {
      return EngineResult.failure(
        _error(
          code: 'TEMPLATE_VERSION_ALREADY_PUBLISHED',
          message: 'This exact template version is already published.',
          draft: draft,
        ),
      );
    }

    final history = await _repository.list();
    if (history.isFailure) return EngineResult.failure(history.error);
    final versions =
        history.value
            .where((artifact) => artifact.templateId == draft.id)
            .map((artifact) => artifact.templateVersion.value)
            .toList()
          ..sort();
    final minimumVersion = versions.isEmpty ? 1 : versions.last + 1;
    if (draft.version.value < minimumVersion) {
      return EngineResult.failure(
        _error(
          code: 'TEMPLATE_REVISION_INVALID',
          message: 'A published template must be newer than stored history.',
          draft: draft,
          extraDetails: {'minimumVersion': minimumVersion},
        ),
      );
    }

    final published = draft.toPublishedAfterValidation();
    final layout = _layoutEngine.build(published, layoutConfig);
    if (layout.isFailure) return EngineResult.failure(layout.error);
    final pdf = await _pdfRenderer(published, layout.value);
    if (pdf.isFailure) return EngineResult.failure(pdf.error);

    return _repository.save(
      PublishedTemplateArtifact(
        template: published,
        layoutProfile: layoutConfig.profile,
        layout: layout.value,
        pdfBytes: pdf.value,
      ),
    );
  }

  Future<EngineResult<PublishedTemplateArtifact?>> get(
    TemplateId templateId,
    TemplateVersion templateVersion,
  ) => _repository.get(templateId, templateVersion);

  Future<EngineResult<List<PublishedTemplateArtifact>>> list() =>
      _repository.list();

  EngineError _error({
    required String code,
    required String message,
    required TemplateDefinition draft,
    Map<String, Object?> extraDetails = const {},
  }) => EngineError(
    code: code,
    message: message,
    details: {
      'templateId': draft.id.value,
      'templateVersion': draft.version.value,
      ...extraDetails,
    },
  );
}
