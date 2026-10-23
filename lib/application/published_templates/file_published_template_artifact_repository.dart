import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../core/errors/engine_error.dart';
import '../../core/ids/identifiers.dart';
import '../../core/result/engine_result.dart';
import 'published_template_artifact.dart';
import 'published_template_artifact_codec.dart';
import 'published_template_artifact_repository.dart';

/// Durable, atomic file storage for exact published artifacts.
final class FilePublishedTemplateArtifactRepository
    implements PublishedTemplateArtifactRepository {
  FilePublishedTemplateArtifactRepository({
    required Directory rootDirectory,
    PublishedTemplateArtifactCodec codec =
        const PublishedTemplateArtifactCodec(),
  }) : _rootDirectory = rootDirectory,
       _codec = codec;

  static const String manifestFileName = 'artifact.json';
  static const String pdfFileName = 'template.pdf';

  final Directory _rootDirectory;
  final PublishedTemplateArtifactCodec _codec;

  @override
  Future<EngineResult<PublishedTemplateArtifact>> save(
    PublishedTemplateArtifact artifact,
  ) async {
    final target = _versionDirectory(
      artifact.templateId,
      artifact.templateVersion,
    );
    if (await target.exists()) {
      return EngineResult.failure(_alreadyExists(artifact));
    }

    final staging = Directory(
      '${target.path}.staging-${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await staging.create(recursive: true);
      final encoded = _codec.encode(
        template: artifact.template,
        layoutProfile: artifact.layoutProfile,
        layout: artifact.layout,
      );
      final pdfBytes = artifact.pdfBytes;
      final manifest = <String, Object?>{
        'artifact': encoded,
        'artifactSha256': _jsonSha256(encoded),
        'pdfSha256': sha256.convert(pdfBytes).toString(),
      };
      await File(
        '${staging.path}${Platform.pathSeparator}$pdfFileName',
      ).writeAsBytes(pdfBytes, flush: true);
      await File(
        '${staging.path}${Platform.pathSeparator}$manifestFileName',
      ).writeAsString(jsonEncode(manifest), flush: true);
      await target.parent.create(recursive: true);
      await staging.rename(target.path);
      return EngineResult.success(artifact);
    } on Object catch (error) {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
      if (await target.exists()) {
        return EngineResult.failure(_alreadyExists(artifact));
      }
      return EngineResult.failure(
        EngineError(
          code: 'PUBLISHED_ARTIFACT_WRITE_FAILED',
          message: 'Unable to save the exact published template artifact.',
          details: {
            'templateId': artifact.templateId.value,
            'templateVersion': artifact.templateVersion.value,
            'cause': error.toString(),
          },
        ),
      );
    }
  }

  @override
  Future<EngineResult<PublishedTemplateArtifact?>> get(
    TemplateId templateId,
    TemplateVersion templateVersion,
  ) async {
    final directory = _versionDirectory(templateId, templateVersion);
    if (!await directory.exists()) return EngineResult.success(null);
    final loaded = await _load(directory);
    if (loaded.isFailure) return loaded;
    final artifact = loaded.value;
    if (artifact.templateId != templateId ||
        artifact.templateVersion != templateVersion) {
      return EngineResult.failure(
        EngineError(
          code: 'PUBLISHED_ARTIFACT_IDENTITY_MISMATCH',
          message: 'Stored artifact identity does not match its lookup key.',
          details: {
            'requestedTemplateId': templateId.value,
            'requestedTemplateVersion': templateVersion.value,
            'storedTemplateId': artifact.templateId.value,
            'storedTemplateVersion': artifact.templateVersion.value,
          },
        ),
      );
    }
    return EngineResult.success(artifact);
  }

  @override
  Future<EngineResult<List<PublishedTemplateArtifact>>> list() async {
    if (!await _rootDirectory.exists()) {
      return EngineResult.success(const []);
    }
    try {
      final manifests = await _rootDirectory
          .list(recursive: true, followLinks: false)
          .where(
            (entity) =>
                entity is File &&
                _fileName(entity.path) == manifestFileName &&
                _fileName(entity.parent.path).startsWith('v'),
          )
          .cast<File>()
          .toList();
      final artifacts = <PublishedTemplateArtifact>[];
      for (final manifest in manifests) {
        final loaded = await _load(manifest.parent);
        if (loaded.isFailure) return EngineResult.failure(loaded.error);
        artifacts.add(loaded.value);
      }
      artifacts.sort((left, right) {
        final byName = left.template.name.compareTo(right.template.name);
        if (byName != 0) return byName;
        final byId = left.templateId.value.compareTo(right.templateId.value);
        if (byId != 0) return byId;
        return left.templateVersion.value.compareTo(
          right.templateVersion.value,
        );
      });
      return EngineResult.success(List.unmodifiable(artifacts));
    } on Object catch (error) {
      return EngineResult.failure(
        EngineError(
          code: 'PUBLISHED_ARTIFACT_READ_FAILED',
          message: 'Unable to list locally published template artifacts.',
          details: {'cause': error.toString()},
        ),
      );
    }
  }

  Future<EngineResult<PublishedTemplateArtifact>> _load(
    Directory directory,
  ) async {
    try {
      final manifestFile = File(
        '${directory.path}${Platform.pathSeparator}$manifestFileName',
      );
      final pdfFile = File(
        '${directory.path}${Platform.pathSeparator}$pdfFileName',
      );
      final manifest = Map<String, Object?>.from(
        jsonDecode(await manifestFile.readAsString()) as Map,
      );
      final encoded = Map<String, Object?>.from(manifest['artifact']! as Map);
      final pdfBytes = Uint8List.fromList(await pdfFile.readAsBytes());
      final actualArtifactHash = _jsonSha256(encoded);
      final actualPdfHash = sha256.convert(pdfBytes).toString();
      if (manifest['artifactSha256'] != actualArtifactHash ||
          manifest['pdfSha256'] != actualPdfHash) {
        return EngineResult.failure(
          EngineError(
            code: 'PUBLISHED_ARTIFACT_INTEGRITY_FAILED',
            message: 'Stored template geometry or PDF bytes were modified.',
            details: {'artifactDirectory': directory.path},
          ),
        );
      }
      final decoded = _codec.decode(encoded);
      return EngineResult.success(
        PublishedTemplateArtifact(
          template: decoded.template,
          layoutProfile: decoded.layoutProfile,
          layout: decoded.layout,
          pdfBytes: pdfBytes,
        ),
      );
    } on Object catch (error) {
      return EngineResult.failure(
        EngineError(
          code: 'PUBLISHED_ARTIFACT_READ_FAILED',
          message: 'Unable to load a locally published template artifact.',
          details: {
            'artifactDirectory': directory.path,
            'cause': error.toString(),
          },
        ),
      );
    }
  }

  Directory _versionDirectory(
    TemplateId templateId,
    TemplateVersion templateVersion,
  ) => Directory(
    '${_rootDirectory.path}${Platform.pathSeparator}'
    '${_safeDirectoryName(templateId.value)}${Platform.pathSeparator}'
    'v${templateVersion.value}',
  );

  static String _safeDirectoryName(String value) =>
      base64Url.encode(utf8.encode(value)).replaceAll('=', '');

  static String _jsonSha256(Object? value) =>
      sha256.convert(utf8.encode(jsonEncode(value))).toString();

  static String _fileName(String path) =>
      path.split(Platform.pathSeparator).last;

  static EngineError _alreadyExists(PublishedTemplateArtifact artifact) =>
      EngineError(
        code: 'TEMPLATE_VERSION_ALREADY_PUBLISHED',
        message: 'This exact template version is already published.',
        details: {
          'templateId': artifact.templateId.value,
          'templateVersion': artifact.templateVersion.value,
        },
      );
}
