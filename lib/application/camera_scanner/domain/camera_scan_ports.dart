import 'dart:typed_data';

import '../../../core/result/engine_result.dart';
import '../../../engines/camera/domain/camera_models.dart';
import '../../../engines/scanner/domain/scan_result.dart';
import '../../../engines/scanner/domain/scanner_diagnostic_snapshot.dart';
import 'camera_scan_context.dart';

abstract interface class CameraScanCamera {
  CameraEngineState get state;
  Stream<CameraEngineState> get states;

  Future<EngineResult<bool>> initialize();
  Future<EngineResult<bool>> startAnalysis();
  Future<EngineResult<bool>> stopAnalysis();
  Future<EngineResult<CapturedPageImage>> capture();
  Future<EngineResult<bool>> setTorchEnabled(bool enabled);
  Future<EngineResult<bool>> suspend();
  void resetTracking();
  Future<void> dispose();
}

abstract interface class CapturedImageBytesLoader {
  Future<EngineResult<Uint8List>> load(CapturedPageImage capture);
}

abstract interface class OfflineScanRunner {
  Future<EngineResult<FinalScannerRun>> scan({
    required Uint8List encodedImage,
    required CameraScanContext context,
    bool includeDiagnostics = false,
  });

  Future<void> dispose();
}

final class FinalScannerRun {
  const FinalScannerRun({
    required this.result,
    required this.workerDuration,
    required this.isolateOverhead,
    required this.workerReused,
    this.workerStartupDuration = Duration.zero,
    this.transferredByteCount = 0,
    this.transferredByteChecksum = 0,
    this.diagnosticSnapshot,
  });

  final ScanResult result;
  final Duration workerDuration;
  final Duration isolateOverhead;
  final bool workerReused;
  final Duration workerStartupDuration;
  final int transferredByteCount;
  final int transferredByteChecksum;
  final ScannerDiagnosticSnapshot? diagnosticSnapshot;
}
