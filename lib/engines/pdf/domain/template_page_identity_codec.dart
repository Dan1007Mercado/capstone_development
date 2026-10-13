import '../../../core/ids/identifiers.dart';

/// Stable compact identity shared by printable pages and the future scanner.
final class TemplatePageIdentityCodec {
  const TemplatePageIdentityCodec();

  static const formatPrefix = 'TS1';

  String encode({
    required TemplateId templateId,
    required TemplateVersion templateVersion,
    required PageId pageId,
  }) =>
      '$formatPrefix|${templateId.value}|${templateVersion.value}|${pageId.value}';
}
