import 'dart:typed_data';

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../../engines/camera/application/camera_engine.dart';
import '../../../engines/camera/domain/camera_models.dart';
import '../../../engines/scanner/application/offline_scanner_engine.dart';
import '../../../engines/scanner/domain/scanner_diagnostic_snapshot.dart';
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
  Future<EngineResult<bool>> setTorchEnabled(bool enabled) =>
      engine.setTorchEnabled(enabled);

  @override
  Future<EngineResult<bool>> suspend() => engine.suspend();

  @override
  void resetTracking() => engine.resetTracking();

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

/// In-process adapter retained for pure-Dart tests and explicit compositions.
/// Production camera scanning uses [IsolateOfflineScannerRunner].
final class OfflineScannerRunnerAdapter implements OfflineScanRunner {
  const OfflineScannerRunnerAdapter(this.engine);

  final OfflineScannerEngine engine;

  @override
  Future<EngineResult<FinalScannerRun>> scan({
    required Uint8List encodedImage,
    required CameraScanContext context,
    bool includeDiagnostics = false,
  }) async {
    await Future<void>.delayed(Duration.zero);
    final stopwatch = Stopwatch()..start();
    ScannerDiagnosticSnapshot? diagnosticSnapshot;
    final result = engine.scan(
      encodedImage: encodedImage,
      template: context.template,
      pageLayout: context.pageLayout,
      config: context.scannerConfig,
      diagnosticSink: includeDiagnostics
          ? (snapshot) => diagnosticSnapshot = snapshot
          : null,
    );
    stopwatch.stop();
    if (result.isFailure) return EngineResult.failure(result.error);
    return EngineResult.success(
      FinalScannerRun(
        result: result.value,
        workerDuration: stopwatch.elapsed,
        isolateOverhead: Duration.zero,
        workerReused: false,
        diagnosticSnapshot: diagnosticSnapshot,
      ),
    );
  }

  @override
  Future<void> dispose() async {}
}
