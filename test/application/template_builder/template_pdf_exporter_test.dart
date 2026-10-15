import 'dart:io';
import 'dart:typed_data';

import 'package:capstone_development/application/template_builder/template_pdf_exporter.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'talaan-pdf-export-test-',
    );
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test(
    'safe filename folds accents, removes unsafe characters, and versions',
    () {
      expect(
        templatePdfFileName('Résumé – Survey: 2026/27?', TemplateVersion(3)),
        'resume-survey-2026-27-v3.pdf',
      );
      expect(sanitizePdfFileName(r' ..\/:*?"<>| '), 'template.pdf');
      expect(sanitizePdfFileName('Already.PDF'), 'already.pdf');
    },
  );

  test('internal export writes exact bytes and returns its file URI', () async {
    final bytes = Uint8List.fromList([37, 80, 68, 70, 45, 1, 2, 3]);
    final exporter = IoTemplatePdfExporter(
      directoryProvider: () async => temporaryDirectory,
    );

    final result = await exporter.export(
      bytes: bytes,
      suggestedFileName: 'Survey: One-v1.pdf',
    );

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(result.value.fileName, 'survey-one-v1.pdf');
    expect(result.value.byteCount, bytes.length);
    expect(result.value.method, PdfExportMethod.internalFileSystem);
    expect(result.value.userCancelled, isFalse);
    final file = File.fromUri(result.value.locationUri!);
    expect(await file.exists(), isTrue);
    expect(await file.readAsBytes(), bytes);
  });

  test(
    'same deterministic name is overwritten with the latest bytes',
    () async {
      final exporter = IoTemplatePdfExporter(
        directoryProvider: () async => temporaryDirectory,
      );
      await exporter.export(
        bytes: Uint8List.fromList([1, 2, 3]),
        suggestedFileName: 'same.pdf',
      );

      final result = await exporter.export(
        bytes: Uint8List.fromList([4, 5]),
        suggestedFileName: 'same.pdf',
      );

      expect(result.isSuccess, isTrue);
      expect(await File.fromUri(result.value.locationUri!).readAsBytes(), [
        4,
        5,
      ]);
    },
  );

  test('empty bytes return a structured export failure', () async {
    final result = await IoTemplatePdfExporter(
      directoryProvider: () async => temporaryDirectory,
    ).export(bytes: Uint8List(0), suggestedFileName: 'empty.pdf');

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'PDF_EXPORT_FAILED');
  });

  test('unavailable directory returns a structured path failure', () async {
    final blockingFile = File('${temporaryDirectory.path}/not-a-directory');
    await blockingFile.writeAsString('blocked');

    final result = await IoTemplatePdfExporter(
      directoryProvider: () async => Directory(blockingFile.path),
    ).export(bytes: Uint8List.fromList([1]), suggestedFileName: 'blocked.pdf');

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'PDF_EXPORT_PATH_UNAVAILABLE');
    expect(result.error.details['cause'], isNotNull);
  });
}
