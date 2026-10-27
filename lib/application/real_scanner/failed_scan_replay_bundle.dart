import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import '../../core/errors/engine_error.dart';
import '../../core/ids/identifiers.dart';
import '../../engines/layout/domain/layout_config.dart';
import '../../engines/layout/domain/page_layout.dart';
import '../../engines/scanner/domain/scanner_config.dart';
import '../../engines/scanner/domain/scanner_config_codec.dart';
import '../../engines/template/domain/template_definition.dart';
import '../published_templates/published_template_artifact_codec.dart';

/// Self-contained, host-replayable capture. No repository lookup or default
/// template is permitted when this object is decoded.
final class FailedScanReplayBundle {
  FailedScanReplayBundle({
    required Uint8List encodedImage,
    required this.template,
    required this.layout,
    required this.layoutProfile,
    required this.pageId,
    required this.scannerConfig,
    required this.failure,
    required this.capturedAtUtc,
    Uint8List? publishedPdfBytes,
  }) : encodedImage = Uint8List.fromList(encodedImage),
       publishedPdfBytes = publishedPdfBytes == null
           ? null
           : Uint8List.fromList(publishedPdfBytes);

  final Uint8List encodedImage;
  final TemplateDefinition template;
  final LayoutDocument layout;
  final LayoutProfile layoutProfile;
  final PageId pageId;
  final ScannerConfig scannerConfig;
  final EngineError failure;
  final DateTime capturedAtUtc;
  final Uint8List? publishedPdfBytes;

  PageLayout get page => layout.pages.singleWhere((p) => p.pageId == pageId);
}

final class FailedScanReplayBundleCodec {
  const FailedScanReplayBundleCodec({
    this.artifactCodec = const PublishedTemplateArtifactCodec(),
    this.scannerConfigCodec = const ScannerConfigCodec(),
  });

  static const int schemaVersion = 3;
  static const int maximumFileCount = 9;
  static const int maximumUncompressedBytes = 64 * 1024 * 1024;
  static const Set<String> _metadataNames = {
    'manifest.json',
    'artifact.json',
    'scanner_config.json',
    'failure.json',
  };

  final PublishedTemplateArtifactCodec artifactCodec;
  final ScannerConfigCodec scannerConfigCodec;

  Uint8List encode(FailedScanReplayBundle bundle) {
    final imageName = _imageName(bundle.encodedImage);
    final payloads = <String, Uint8List>{
      imageName: bundle.encodedImage,
      'artifact.json': _jsonBytes(
        artifactCodec.encode(
          template: bundle.template,
          layoutProfile: bundle.layoutProfile,
          layout: bundle.layout,
        ),
      ),
      'scanner_config.json': _jsonBytes(
        scannerConfigCodec.encode(bundle.scannerConfig),
      ),
      'failure.json': _jsonBytes({
        'code': bundle.failure.code,
        'message': bundle.failure.message,
        'details': bundle.failure.details,
      }),
      'published.pdf': ?bundle.publishedPdfBytes,
    };
    final manifest = <String, Object?>{
      'schemaVersion': schemaVersion,
      'capturedAtUtc': bundle.capturedAtUtc.toUtc().toIso8601String(),
      'templateId': bundle.template.id.value,
      'templateVersion': bundle.template.version.value,
      'pageId': bundle.pageId.value,
      'imageFile': imageName,
      'pdfFile': bundle.publishedPdfBytes == null ? null : 'published.pdf',
      'files': {
        for (final entry in payloads.entries)
          entry.key: {
            'length': entry.value.length,
            'sha256': sha256.convert(entry.value).toString(),
          },
      },
    };
    final archive = Archive();
    for (final entry in <String, Uint8List>{
      'manifest.json': _jsonBytes(manifest),
      ...payloads,
    }.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  FailedScanReplayBundle decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maximumUncompressedBytes) {
      throw const FormatException('Replay bundle size is invalid.');
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.files.length > maximumFileCount) {
      throw const FormatException('Replay bundle contains too many files.');
    }
    var total = 0;
    final files = <String, Uint8List>{};
    for (final file in archive.files) {
      if (!file.isFile ||
          !_safeName(file.name) ||
          files.containsKey(file.name)) {
        throw FormatException('Unsafe or duplicate replay entry: ${file.name}');
      }
      total += file.size;
      if (total > maximumUncompressedBytes) {
        throw const FormatException('Replay bundle expands beyond its limit.');
      }
      files[file.name] = Uint8List.fromList(file.content as List<int>);
    }
    final manifest = _jsonMap(_required(files, 'manifest.json'));
    final decodedSchema = manifest['schemaVersion'];
    if (decodedSchema != 2 && decodedSchema != schemaVersion) {
      throw FormatException(
        'Unsupported replay schema: ${manifest['schemaVersion']}',
      );
    }
    final imageName = manifest['imageFile'] as String?;
    if (imageName == null || !_safeName(imageName)) {
      throw const FormatException('Replay image path is missing or unsafe.');
    }
    final pdfName = decodedSchema == 2 ? null : manifest['pdfFile'] as String?;
    if (pdfName != null &&
        (pdfName != 'published.pdf' || !_safeName(pdfName))) {
      throw const FormatException('Replay PDF path is invalid.');
    }
    final allowed = {..._metadataNames, imageName, ?pdfName};
    if (files.keys.any((name) => !allowed.contains(name))) {
      throw const FormatException('Replay bundle contains an unexpected file.');
    }
    final integrity = (manifest['files'] as Map?)?.cast<String, Object?>();
    final payloadNames = {...allowed}..remove('manifest.json');
    if (integrity == null ||
        integrity.keys.toSet().difference(payloadNames).isNotEmpty ||
        payloadNames.difference(integrity.keys.toSet()).isNotEmpty) {
      throw const FormatException('Replay integrity table is invalid.');
    }
    for (final entry in integrity.entries) {
      final data = _required(files, entry.key);
      final expected = (entry.value as Map).cast<String, Object?>();
      if ((expected['length'] as num?)?.toInt() != data.length ||
          expected['sha256'] != sha256.convert(data).toString()) {
        throw FormatException(
          'Replay integrity check failed for ${entry.key}.',
        );
      }
    }
    final artifact = artifactCodec.decode(
      _jsonMap(_required(files, 'artifact.json')),
    );
    final config = scannerConfigCodec.decode(
      _jsonMap(_required(files, 'scanner_config.json')),
    );
    final failureJson = _jsonMap(_required(files, 'failure.json'));
    final pageId = PageId(manifest['pageId'] as String);
    final pages = artifact.layout.pages.where((page) => page.pageId == pageId);
    if (artifact.template.id.value != manifest['templateId'] ||
        artifact.template.version.value != manifest['templateVersion'] ||
        pages.length != 1) {
      throw const FormatException(
        'Replay identities do not match embedded geometry.',
      );
    }
    final markerIds = pages.single.markerRegions
        .map((marker) => marker.markerId)
        .toList(growable: false);
    if (markerIds.length != 4 || markerIds.toSet().length != 4) {
      throw const FormatException(
        'Replay page must contain four unique registration marker IDs.',
      );
    }
    return FailedScanReplayBundle(
      encodedImage: _required(files, imageName),
      template: artifact.template,
      layout: artifact.layout,
      layoutProfile: artifact.layoutProfile,
      pageId: pageId,
      scannerConfig: config,
      failure: EngineError(
        code: failureJson['code'] as String,
        message: failureJson['message'] as String,
        details:
            (failureJson['details'] as Map?)?.cast<String, Object?>() ??
            const {},
      ),
      capturedAtUtc: DateTime.parse(
        manifest['capturedAtUtc'] as String,
      ).toUtc(),
      publishedPdfBytes: pdfName == null ? null : _required(files, pdfName),
    );
  }

  static Uint8List _required(Map<String, Uint8List> files, String name) {
    final value = files[name];
    if (value == null) throw FormatException('Replay file is missing: $name');
    return value;
  }

  static bool _safeName(String name) =>
      name.isNotEmpty &&
      !name.contains('/') &&
      !name.contains('\\') &&
      name != '.' &&
      name != '..';

  static Uint8List _jsonBytes(Object? value) => Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(value)),
  );

  static Map<String, Object?> _jsonMap(Uint8List bytes) =>
      (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();

  static String _imageName(Uint8List bytes) =>
      bytes.length >= 4 &&
          bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4e &&
          bytes[3] == 0x47
      ? 'captured_still.png'
      : 'captured_still.jpg';
}
