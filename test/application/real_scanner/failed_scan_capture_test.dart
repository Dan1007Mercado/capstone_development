import 'dart:typed_data';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:capstone_development/application/camera_scanner/domain/camera_scan_context.dart';
import 'package:capstone_development/application/real_scanner/failed_scan_capture.dart';
import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/debug/p5_native_validation_fixture.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('failed still export is disabled without explicit dart define', () {
    expect(failedScanCaptureExportEnabled, isFalse);
  });

  test('recorder retains an owned copy only after committed failure', () {
    final template = buildP5NativeValidationTemplate();
    final page = buildP5NativeValidationPage();
    final context = CameraScanContext(
      template: template,
      pageLayout: page,
      templateId: template.id,
      templateVersion: template.version,
      pageId: page.pageId,
      scannerConfig: ScannerConfig(),
    );
    final bytes = Uint8List.fromList([0xff, 0xd8, 1, 2, 3]);
    final recorder = FailedScanCaptureRecorder();

    recorder.stage(bytes, context);
    bytes.fillRange(0, bytes.length, 0);
    expect(recorder.hasCapture, isFalse);

    recorder.commitFailure(
      EngineError(code: 'ARUCO_REPROJECTION_FAILED', message: 'Rejected.'),
    );

    expect(recorder.hasCapture, isTrue);
    expect(recorder.capture!.encodedImage, [0xff, 0xd8, 1, 2, 3]);
    expect(recorder.capture!.context, same(context));
    expect(recorder.capture!.error.code, 'ARUCO_REPROJECTION_FAILED');

    final archive = ZipDecoder().decodeBytes(
      const FailedScanCaptureExporter().buildBundle(recorder.capture!),
    );
    final image = archive.findFile('captured_still.jpg')!;
    final manifest = archive.findFile('replay_manifest.json')!;
    expect(image.content, [0xff, 0xd8, 1, 2, 3]);
    final manifestJson = jsonDecode(utf8.decode(manifest.content)) as Map;
    expect(manifestJson['pageId'], page.pageId.value);
    expect(manifestJson['markers'], hasLength(4));
    expect(manifestJson['bubbleBounds'], isNotEmpty);
  });

  test('discard removes a staged success without replacing last failure', () {
    final template = buildP5NativeValidationTemplate();
    final page = buildP5NativeValidationPage();
    final context = CameraScanContext(
      template: template,
      pageLayout: page,
      templateId: template.id,
      templateVersion: template.version,
      pageId: page.pageId,
      scannerConfig: ScannerConfig(),
    );
    final recorder = FailedScanCaptureRecorder();
    recorder.stage(Uint8List.fromList([1]), context);
    recorder.commitFailure(
      EngineError(code: 'FIRST_FAILURE', message: 'First.'),
    );
    recorder.stage(Uint8List.fromList([2]), context);

    recorder.discard();

    expect(recorder.capture!.encodedImage, [1]);
    expect(recorder.capture!.error.code, 'FIRST_FAILURE');
  });
}
