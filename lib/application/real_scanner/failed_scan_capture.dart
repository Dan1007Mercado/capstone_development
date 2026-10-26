import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../core/errors/engine_error.dart';
import '../../core/geometry/physical_geometry.dart';
import '../../core/result/engine_result.dart';
import '../camera_scanner/domain/camera_scan_context.dart';
import '../camera_scanner/domain/camera_scan_ports.dart';

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
    final extension = _imageExtension(capture.encodedImage);
    final manifestBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(_manifest(capture)),
    );
    final archive = Archive()
      ..addFile(
        ArchiveFile(
          'captured_still.$extension',
          capture.encodedImage.length,
          capture.encodedImage,
        ),
      )
      ..addFile(
        ArchiveFile(
          'replay_manifest.json',
          manifestBytes.length,
          manifestBytes,
        ),
      );
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  Map<String, Object?> _manifest(FailedScanCapture capture) {
    final context = capture.context;
    final page = context.pageLayout;
    final alignment = context.scannerConfig.alignment;
    Map<String, double> rect(PhysicalRect value) => {
      'leftMm': value.left.millimeters,
      'topMm': value.top.millimeters,
      'widthMm': value.width.millimeters,
      'heightMm': value.height.millimeters,
    };

    return {
      'formatVersion': 1,
      'capturedAtUtc': capture.timestamp.toIso8601String(),
      'failureCode': capture.error.code,
      'templateId': context.templateId.value,
      'templateVersion': context.templateVersion.value,
      'pageId': context.pageId.value,
      'pageIndex': page.pageIndex,
      'pageSizeMm': {
        'width': page.pageSpec.size.width.millimeters,
        'height': page.pageSpec.size.height.millimeters,
      },
      'canonicalSize': {
        'width': page.canonicalPageSpec.widthPixels,
        'height': page.canonicalPageSpec.heightPixels,
      },
      'markers': [
        for (final marker in page.markerRegions)
          {
            'id': marker.markerId,
            'role': marker.role.name,
            'printBounds': rect(marker.physicalBounds),
            'detectableBounds': rect(marker.physicalMarkerBounds),
          },
      ],
      'bubbleBounds': [
        for (final bubble in page.bubbleRegions) rect(bubble.physicalBounds),
      ],
      'alignmentConfig': {
        'dictionary': alignment.dictionary.name,
        'finalMarkerDetectionMaxDimension':
            alignment.finalMarkerDetectionMaxDimension,
        'maximumReprojectionErrorPixels':
            alignment.maximumReprojectionErrorPixels,
        'multipointRansacReprojectionThresholdPixels':
            alignment.multipointRansacReprojectionThresholdPixels,
        'minimumMultipointInlierRatio': alignment.minimumMultipointInlierRatio,
        'maximumRejectedCornerErrorPixels':
            alignment.maximumRejectedCornerErrorPixels,
        'maximumLocalizationScaleFactor':
            alignment.maximumLocalizationScaleFactor,
      },
    };
  }

  String _imageExtension(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'png';
    }
    return 'jpg';
  }
}
