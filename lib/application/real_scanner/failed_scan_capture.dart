import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../core/errors/engine_error.dart';
import '../../core/result/engine_result.dart';
import '../../engines/layout/domain/layout_config.dart';
import '../../engines/layout/domain/page_layout.dart';
import '../camera_scanner/domain/camera_scan_context.dart';
import '../camera_scanner/domain/camera_scan_ports.dart';
import 'failed_scan_replay_bundle.dart';

/// Disabled unless a debug build explicitly supplies
/// `--dart-define=ENABLE_FAILED_SCAN_CAPTURE_EXPORT=true`.
const failedScanCaptureExportEnabled =
    kDebugMode && bool.fromEnvironment('ENABLE_FAILED_SCAN_CAPTURE_EXPORT');

final class FailedScanCapture {
  FailedScanCapture({
    required Uint8List encodedImage,
    required this.context,
    required this.error,
    required this.timestamp,
  }) : encodedImage = Uint8List.fromList(encodedImage);

  final Uint8List encodedImage;
  final CameraScanContext context;
  final EngineError error;
  final DateTime timestamp;
}

/// Holds at most one exact final-still copy in memory. No copy is made when
/// this opt-in recorder is absent from the production coordinator.
final class FailedScanCaptureRecorder implements FailedScanCaptureSink {
  Uint8List? _stagedImage;
  CameraScanContext? _stagedContext;
  FailedScanCapture? _capture;

  FailedScanCapture? get capture => _capture;
  bool get hasCapture => _capture != null;

  @override
  void stage(Uint8List encodedImage, CameraScanContext context) {
    _stagedImage = Uint8List.fromList(encodedImage);
    _stagedContext = context;
  }

  @override
  void commitFailure(EngineError error) {
    final image = _stagedImage;
    final context = _stagedContext;
    if (image == null || context == null) return;
    _capture = FailedScanCapture(
      encodedImage: image,
      context: context,
      error: error,
      timestamp: DateTime.now().toUtc(),
    );
    _clearStaged();
  }

  @override
  void discard() => _clearStaged();

  void _clearStaged() {
    _stagedImage = null;
    _stagedContext = null;
  }
}

final class FailedScanCaptureExporter {
  const FailedScanCaptureExporter();

  Future<EngineResult<String?>> export(FailedScanCapture capture) async {
    try {
      final bundle = buildBundle(capture);
      final selectedUri = await FilePicker.saveFile(
        dialogTitle: 'Export failed scanner replay bundle',
        fileName: 'talaanscan_failed_capture.zip',
        bytes: bundle,
        mimeType: 'application/zip',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      return EngineResult.success(selectedUri?.toString());
    } on Object catch (error) {
      return EngineResult.failure(
        EngineError(
          code: 'FAILED_SCAN_CAPTURE_EXPORT_FAILED',
          message: 'The failed scanner still could not be exported.',
          details: {'cause': error.toString()},
        ),
      );
    }
  }

  Uint8List buildBundle(FailedScanCapture capture) {
    final context = capture.context;
    final pages = context.availablePages.toList()
      ..sort((left, right) => left.pageIndex.compareTo(right.pageIndex));
    final layout = LayoutDocument(
      templateId: context.templateId,
      templateVersion: context.templateVersion,
      pages: pages,
    );
    return const FailedScanReplayBundleCodec().encode(
      FailedScanReplayBundle(
        encodedImage: capture.encodedImage,
        template: context.template,
        layout: layout,
        layoutProfile: _inferProfile(pages),
        pageId: context.pageId,
        scannerConfig: context.scannerConfig,
        failure: capture.error,
        capturedAtUtc: capture.timestamp,
      ),
    );
  }

  LayoutProfile _inferProfile(List<PageLayout> pages) {
    final columns = pages.fold<int>(
      0,
      (maximum, page) => page.contentColumnRegions.length > maximum
          ? page.contentColumnRegions.length
          : maximum,
    );
    return columns > 1 ? LayoutProfile.dense : LayoutProfile.comfortable;
  }
}
