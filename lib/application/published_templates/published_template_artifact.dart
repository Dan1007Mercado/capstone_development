import 'dart:typed_data';

import '../../core/ids/identifiers.dart';
import '../../engines/layout/domain/page_layout.dart';
import '../../engines/template/domain/template_definition.dart';
import '../../engines/template/domain/template_status.dart';

/// One immutable, printable and scannable published template version.
///
/// The PDF and scanner geometry travel together so neither consumer can
/// independently reconstruct positions after publication.
final class PublishedTemplateArtifact {
  PublishedTemplateArtifact({
    required this.template,
    required this.layout,
    required Uint8List pdfBytes,
  }) : _pdfBytes = Uint8List.fromList(pdfBytes) {
    if (template.status != TemplateStatus.published) {
      throw ArgumentError.value(
        template.status,
        'template',
        'A published artifact requires a published template.',
      );
    }
    if (layout.templateId != template.id ||
        layout.templateVersion != template.version) {
      throw ArgumentError(
        'Template and PageLayout identities must match exactly.',
      );
    }
    if (layout.pages.isEmpty) {
      throw ArgumentError.value(layout, 'layout', 'Layout must contain pages.');
    }
    if (_pdfBytes.isEmpty) {
      throw ArgumentError.value(pdfBytes, 'pdfBytes', 'PDF cannot be empty.');
    }
  }

  final TemplateDefinition template;
  final LayoutDocument layout;
  final Uint8List _pdfBytes;

  TemplateId get templateId => template.id;
  TemplateVersion get templateVersion => template.version;

  /// Returns a defensive copy so published PDF bytes cannot be mutated.
  Uint8List get pdfBytes => Uint8List.fromList(_pdfBytes);
}
