import 'dart:typed_data';

import 'package:capstone_development/application/template_builder/template_pdf_exporter.dart';
import 'package:capstone_development/application/template_builder/user_accessible_template_pdf_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'system save dialog receives exact PDF bytes and safe filename',
    () async {
      final bytes = Uint8List.fromList([37, 80, 68, 70, 45, 1, 2, 3]);
      final dialog = _RecordingSaveDialog(
        result: Uri.parse('content://documents/resume-survey-v1.pdf'),
      );

      final result = await UserAccessibleTemplatePdfExporter(
        saveDialog: dialog,
      ).export(bytes: bytes, suggestedFileName: 'Résumé Survey-v1.pdf');

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      expect(dialog.bytes, same(bytes));
      expect(dialog.fileName, 'resume-survey-v1.pdf');
      expect(result.value.fileName, 'resume-survey-v1.pdf');
      expect(result.value.byteCount, bytes.length);
      expect(result.value.method, PdfExportMethod.systemSaveDialog);
      expect(
        result.value.locationUri,
        Uri.parse('content://documents/resume-survey-v1.pdf'),
      );
      expect(result.value.userCancelled, isFalse);
    },
  );

  test('system save cancellation is a benign typed outcome', () async {
    final result =
        await UserAccessibleTemplatePdfExporter(
          saveDialog: _RecordingSaveDialog(result: null),
        ).export(
          bytes: Uint8List.fromList([37, 80, 68, 70]),
          suggestedFileName: 'survey.pdf',
        );

    expect(result.isSuccess, isTrue);
    expect(result.value.userCancelled, isTrue);
    expect(result.value.locationUri, isNull);
    expect(result.value.method, PdfExportMethod.systemSaveDialog);
  });

  test('system save exception becomes a structured picker failure', () async {
    final result =
        await UserAccessibleTemplatePdfExporter(
          saveDialog: _ThrowingSaveDialog(),
        ).export(
          bytes: Uint8List.fromList([37, 80, 68, 70]),
          suggestedFileName: 'survey.pdf',
        );

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'PDF_EXPORT_PICKER_FAILED');
    expect(result.error.details['cause'], contains('picker unavailable'));
  });

  test('empty bytes do not open the system save dialog', () async {
    final dialog = _RecordingSaveDialog(result: Uri.parse('content://unused'));

    final result = await UserAccessibleTemplatePdfExporter(
      saveDialog: dialog,
    ).export(bytes: Uint8List(0), suggestedFileName: 'empty.pdf');

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'PDF_EXPORT_FAILED');
    expect(dialog.bytes, isNull);
  });
}

final class _RecordingSaveDialog implements PdfSaveDialog {
  _RecordingSaveDialog({required this.result});

  final Uri? result;
  Uint8List? bytes;
  String? fileName;

  @override
  Future<Uri?> save({
    required Uint8List bytes,
    required String suggestedFileName,
  }) async {
    this.bytes = bytes;
    fileName = suggestedFileName;
    return result;
  }
}

final class _ThrowingSaveDialog implements PdfSaveDialog {
  @override
  Future<Uri?> save({
    required Uint8List bytes,
    required String suggestedFileName,
  }) => throw StateError('picker unavailable');
}
