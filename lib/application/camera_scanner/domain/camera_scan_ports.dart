import 'dart:typed_data';

import '../../../core/result/engine_result.dart';
import '../../../engines/camera/domain/camera_models.dart';
import '../../../engines/scanner/domain/scan_result.dart';
import 'camera_scan_context.dart';

abstract interface class CameraScanCamera {
  CameraEngineState get state;
  Stream<CameraEngineState> get states;

  Future<EngineResult<bool>> initialize();
  Future<EngineResult<bool>> startAnalysis();
  Future<EngineResult<bool>> stopAnalysis();
  Future<EngineResult<CapturedPageImage>> capture();
  Future<EngineResult<bool>> suspend();
  Future<void> dispose();
}

abstract interface class CapturedImageBytesLoader {
  Future<EngineResult<Uint8List>> load(CapturedPageImage capture);
}

abstract interface class OfflineScanRunner {
  Future<EngineResult<FinalScannerRun>> scan({
    required Uint8List encodedImage,
    required CameraScanContext context,
  });

  Future<void> dispose();
}

final class FinalScannerRun {
  const FinalScannerRun({
    required this.result,
    required this.workerDuration,
    required this.isolateOverhead,
    required this.workerReused,
    this.transferredByteCount = 0,
    this.transferredByteChecksum = 0,
  });

  final ScanResult result;
  final Duration workerDuration;
  final Duration isolateOverhead;
  final bool workerReused;
  final int transferredByteCount;
  final int transferredByteChecksum;
}
