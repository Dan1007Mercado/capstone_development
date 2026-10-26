import 'dart:typed_data';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:capstone_development/application/camera_scanner/domain/camera_scan_context.dart';
import 'package:capstone_development/application/real_scanner/failed_scan_capture.dart';
import 'package:capstone_development/application/real_scanner/failed_scan_replay_bundle.dart';
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
    final manifest = archive.findFile('manifest.json')!;
    expect(image.content, [0xff, 0xd8, 1, 2, 3]);
    final manifestJson = jsonDecode(utf8.decode(manifest.content)) as Map;
    expect(manifestJson['pageId'], page.pageId.value);
    expect(manifestJson['schemaVersion'], 2);

    final replay = const FailedScanReplayBundleCodec().decode(
      const FailedScanCaptureExporter().buildBundle(recorder.capture!),
    );
    expect(replay.page, page);
    expect(replay.template, template);
    expect(replay.failure.code, 'ARUCO_REPROJECTION_FAILED');
    expect(replay.scannerConfig.alignment.enableMultipointHomography, isTrue);
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

  test('replay bundle rejects unsupported schema and corrupted payload', () {
    final template = buildP5NativeValidationTemplate();
    final page = buildP5NativeValidationPage();
    final capture = FailedScanCapture(
      encodedImage: Uint8List.fromList([0xff, 0xd8, 1, 2, 3]),
      context: CameraScanContext(
        template: template,
        pageLayout: page,
        templateId: template.id,
        templateVersion: template.version,
        pageId: page.pageId,
        scannerConfig: ScannerConfig(),
      ),
      error: EngineError(code: 'FAILED', message: 'Failed.'),
      timestamp: DateTime.utc(2026, 10, 27),
    );
    final bytes = const FailedScanCaptureExporter().buildBundle(capture);
    final decoded = ZipDecoder().decodeBytes(bytes);

    Uint8List rebuild(String target, List<int> Function(List<int>) alter) {
      final output = Archive();
      for (final file in decoded.files) {
        final content = List<int>.from(file.content as List<int>);
        final next = file.name == target ? alter(content) : content;
        output.addFile(ArchiveFile(file.name, next.length, next));
      }
      return Uint8List.fromList(ZipEncoder().encode(output)!);
    }

    final badVersion = rebuild('manifest.json', (content) {
      final value = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
      value['schemaVersion'] = 999;
      return utf8.encode(jsonEncode(value));
    });
    expect(
      () => const FailedScanReplayBundleCodec().decode(badVersion),
      throwsFormatException,
    );

    final corrupt = rebuild('artifact.json', (content) {
      content[content.length ~/ 2] ^= 1;
      return content;
    });
    expect(
      () => const FailedScanReplayBundleCodec().decode(corrupt),
      throwsFormatException,
    );

    final incompleteArchive = Archive();
    for (final file in decoded.files.where(
      (file) => file.name != 'scanner_config.json',
    )) {
      final content = List<int>.from(file.content as List<int>);
      incompleteArchive.addFile(
        ArchiveFile(file.name, content.length, content),
      );
    }
    final incomplete = Uint8List.fromList(
      ZipEncoder().encode(incompleteArchive)!,
    );
    expect(
      () => const FailedScanReplayBundleCodec().decode(incomplete),
      throwsFormatException,
    );
  });
}
