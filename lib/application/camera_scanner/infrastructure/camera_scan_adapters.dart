import 'dart:typed_data';

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../../engines/camera/application/camera_engine.dart';
import '../../../engines/camera/domain/camera_models.dart';
import '../../../engines/scanner/application/offline_scanner_engine.dart';
import '../../../engines/scanner/domain/scan_result.dart';
import '../domain/camera_scan_context.dart';
import '../domain/camera_scan_ports.dart';

final class CameraEngineScanAdapter implements CameraScanCamera {
  const CameraEngineScanAdapter(this.engine);

  final CameraEngine engine;

  @override
  CameraEngineState get state => engine.state;

  @override
  Stream<CameraEngineState> get states => engine.states;

  @override
  Future<EngineResult<bool>> initialize() => engine.initialize();

  @override
  Future<EngineResult<bool>> startAnalysis() => engine.startAnalysis();

  @override
  Future<EngineResult<bool>> stopAnalysis() => engine.stopAnalysis();

  @override
  Future<EngineResult<CapturedPageImage>> capture() => engine.capture();

  @override
  Future<EngineResult<bool>> suspend() => engine.suspend();

  @override
  Future<void> dispose() => engine.dispose();
}

final class InMemoryCapturedImageBytesLoader
    implements CapturedImageBytesLoader {
  const InMemoryCapturedImageBytesLoader();

  @override
  Future<EngineResult<Uint8List>> load(CapturedPageImage capture) async {
    if (capture.encodedBytes.isEmpty) {
      return EngineResult.failure(
        EngineError(
          code: 'CAPTURE_IMAGE_EMPTY',
          message: 'The high-quality captured image contains no bytes.',
        ),
      );
    }
    // CapturedPageImage already owns a defensive byte copy. P9 copies at its
    // engine boundary, so another full-resolution copy here is unnecessary.
    return EngineResult.success(capture.encodedBytes);
  }
}

final class OfflineScannerRunnerAdapter implements OfflineScanRunner {
  const OfflineScannerRunnerAdapter(this.engine);

  final OfflineScannerEngine engine;

  @override
  Future<EngineResult<ScanResult>> scan({
    required Uint8List encodedImage,
    required CameraScanContext context,
  }) async {
    // Let the scanning state reach the UI before invoking the accepted
    // synchronous P9 boundary. Native scanner isolation remains a later phase.
    await Future<void>.delayed(Duration.zero);
    return engine.scan(
      encodedImage: encodedImage,
      template: context.template,
      pageLayout: context.pageLayout,
      config: context.scannerConfig,
    );
  }
}
