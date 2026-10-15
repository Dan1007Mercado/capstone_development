import 'dart:io';
import 'dart:typed_data';

import '../../core/errors/engine_error.dart';
import '../../core/ids/identifiers.dart';
import '../../core/result/engine_result.dart';

final class ExportedPdfFile {
  const ExportedPdfFile({
    required this.path,
    required this.fileName,
    required this.byteCount,
  });

  final String path;
  final String fileName;
  final int byteCount;
}

abstract interface class TemplatePdfExporter {
  Future<EngineResult<ExportedPdfFile>> export({
    required Uint8List bytes,
    required String suggestedFileName,
  });
}

typedef ExportDirectoryProvider = Future<Directory> Function();

/// Persists preview PDFs below the app-specific system temporary directory.
///
/// Android maps [Directory.systemTemp] to the app cache, so this requires no
/// broad storage permission. A repeated deterministic name is overwritten.
final class IoTemplatePdfExporter implements TemplatePdfExporter {
  IoTemplatePdfExporter({ExportDirectoryProvider? directoryProvider})
    : _directoryProvider = directoryProvider ?? _defaultDirectory;

  final ExportDirectoryProvider _directoryProvider;

  @override
  Future<EngineResult<ExportedPdfFile>> export({
    required Uint8List bytes,
    required String suggestedFileName,
  }) async {
    if (bytes.isEmpty) {
      return EngineResult.failure(
        EngineError(
          code: 'PDF_EXPORT_FAILED',
          message: 'Cannot export an empty PDF.',
        ),
      );
    }

    Directory directory;
    try {
      directory = await _directoryProvider();
      await directory.create(recursive: true);
    } on Object catch (error) {
      return EngineResult.failure(
        EngineError(
          code: 'PDF_EXPORT_PATH_UNAVAILABLE',
          message: 'The PDF export directory is unavailable.',
          details: {'cause': error.toString()},
        ),
      );
    }

    final fileName = sanitizePdfFileName(suggestedFileName);
    final path = '${directory.path}${Platform.pathSeparator}$fileName';
    try {
      final file = File(path);
      await file.writeAsBytes(bytes, flush: true);
      final byteCount = await file.length();
      if (byteCount != bytes.length) {
        return EngineResult.failure(
          EngineError(
            code: 'PDF_EXPORT_WRITE_FAILED',
            message: 'The exported PDF byte count did not match its input.',
            details: {
              'targetPath': path,
              'expectedBytes': bytes.length,
              'actualBytes': byteCount,
            },
          ),
        );
      }
      return EngineResult.success(
        ExportedPdfFile(
          path: file.absolute.path,
          fileName: fileName,
          byteCount: byteCount,
        ),
      );
    } on Object catch (error) {
      return EngineResult.failure(
        EngineError(
          code: 'PDF_EXPORT_WRITE_FAILED',
          message: 'Unable to write the generated PDF file.',
          details: {'targetPath': path, 'cause': error.toString()},
        ),
      );
    }
  }

  static Future<Directory> _defaultDirectory() async => Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}'
    'talaan_scan${Platform.pathSeparator}exports',
  );
}

String templatePdfFileName(String templateName, TemplateVersion version) =>
    '${_safeStem(templateName)}-v${version.value}.pdf';

String sanitizePdfFileName(String value) {
  final withoutExtension = value.toLowerCase().endsWith('.pdf')
      ? value.substring(0, value.length - 4)
      : value;
  return '${_safeStem(withoutExtension)}.pdf';
}

String _safeStem(String value) {
  final folded = value.toLowerCase().split('').map(_foldCharacter).join();
  final safe = folded
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return safe.isEmpty ? 'template' : safe;
}

String _foldCharacter(String character) => switch (character) {
  'á' || 'à' || 'â' || 'ä' || 'ã' || 'å' => 'a',
  'ç' => 'c',
  'é' || 'è' || 'ê' || 'ë' => 'e',
  'í' || 'ì' || 'î' || 'ï' => 'i',
  'ñ' => 'n',
  'ó' || 'ò' || 'ô' || 'ö' || 'õ' => 'o',
  'ú' || 'ù' || 'û' || 'ü' => 'u',
  'ý' || 'ÿ' => 'y',
  _ => character,
};
