import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../core/errors/engine_error.dart';
import '../../core/result/engine_result.dart';
import 'template_pdf_exporter.dart';

abstract interface class PdfSaveDialog {
  Future<Uri?> save({
    required Uint8List bytes,
    required String suggestedFileName,
  });
}

final class FilePickerPdfSaveDialog implements PdfSaveDialog {
  const FilePickerPdfSaveDialog();

  @override
  Future<Uri?> save({
    required Uint8List bytes,
    required String suggestedFileName,
  }) => FilePicker.saveFile(
    dialogTitle: 'Save generated PDF',
    fileName: suggestedFileName,
    bytes: bytes,
    mimeType: 'application/pdf',
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
  );
}

/// Writes generated PDF bytes through the platform's user-facing save dialog.
///
/// On Android this uses the Storage Access Framework. The returned location can
/// be a content URI, so callers must not treat it as a filesystem path.
final class UserAccessibleTemplatePdfExporter implements TemplatePdfExporter {
  UserAccessibleTemplatePdfExporter({PdfSaveDialog? saveDialog})
    : _saveDialog = saveDialog ?? const FilePickerPdfSaveDialog();

  final PdfSaveDialog _saveDialog;

  @override
  Future<EngineResult<PdfExportOutcome>> export({
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

    final fileName = sanitizePdfFileName(suggestedFileName);
    try {
      final locationUri = await _saveDialog.save(
        bytes: bytes,
        suggestedFileName: fileName,
      );
      if (locationUri == null) {
        return EngineResult.success(
          PdfExportOutcome.cancelled(
            fileName: fileName,
            byteCount: bytes.length,
            method: PdfExportMethod.systemSaveDialog,
          ),
        );
      }
      return EngineResult.success(
        PdfExportOutcome.saved(
          fileName: fileName,
          byteCount: bytes.length,
          method: PdfExportMethod.systemSaveDialog,
          locationUri: locationUri,
        ),
      );
    } on Object catch (error) {
      return EngineResult.failure(
        EngineError(
          code: 'PDF_EXPORT_PICKER_FAILED',
          message: 'Unable to save the generated PDF with the system dialog.',
          details: {'cause': error.toString()},
        ),
      );
    }
  }
}
