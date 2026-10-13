import '../../../core/errors/engine_error.dart';
import '../../../core/ids/identifiers.dart';
import '../../../core/result/engine_result.dart';

final class TemplatePageIdentity {
  const TemplatePageIdentity({
    required this.templateId,
    required this.templateVersion,
    required this.pageId,
  });

  final TemplateId templateId;
  final TemplateVersion templateVersion;
  final PageId pageId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemplatePageIdentity &&
          other.templateId == templateId &&
          other.templateVersion == templateVersion &&
          other.pageId == pageId;

  @override
  int get hashCode => Object.hash(templateId, templateVersion, pageId);
}

/// Stable compact identity shared by printable pages and the future scanner.
final class TemplatePageIdentityCodec {
  const TemplatePageIdentityCodec();

  static const formatPrefix = 'TS1';

  String encode({
    required TemplateId templateId,
    required TemplateVersion templateVersion,
    required PageId pageId,
  }) => [
    formatPrefix,
    Uri.encodeComponent(templateId.value),
    templateVersion.value,
    Uri.encodeComponent(pageId.value),
  ].join('|');

  EngineResult<TemplatePageIdentity> decode(String payload) {
    final fields = payload.split('|');
    if (fields.length != 4 || fields.first != formatPrefix) {
      return _malformed();
    }

    try {
      final templateIdValue = Uri.decodeComponent(fields[1]);
      final versionValue = int.tryParse(fields[2]);
      final pageIdValue = Uri.decodeComponent(fields[3]);
      if (templateIdValue.isEmpty ||
          versionValue == null ||
          pageIdValue.isEmpty) {
        return _malformed();
      }
      return EngineResult.success(
        TemplatePageIdentity(
          templateId: TemplateId(templateIdValue),
          templateVersion: TemplateVersion(versionValue),
          pageId: PageId(pageIdValue),
        ),
      );
    } on Object {
      return _malformed();
    }
  }

  EngineResult<TemplatePageIdentity> _malformed() => EngineResult.failure(
    EngineError(
      code: 'TEMPLATE_PAGE_IDENTITY_INVALID',
      message: 'Template page identity payload is malformed.',
    ),
  );
}
