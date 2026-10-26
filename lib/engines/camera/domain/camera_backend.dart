import '../../../core/result/engine_result.dart';
import 'camera_engine_config.dart';
import 'camera_models.dart';

typedef CameraFrameMaterializer = CameraAnalysisFrame Function();

/// Delivers a native frame without transferring its pixel buffer eagerly.
///
/// The callback and [materialize] function are synchronous. Implementations
/// must not retain [materialize] because it may refer to a native camera image
/// whose lifetime ends when the camera plugin callback returns.
typedef CameraFrameCallback =
    void Function(DateTime timestamp, CameraFrameMaterializer materialize);

abstract interface class CameraBackend {
  Future<EngineResult<CameraPreviewInfo>> initialize(CameraEngineConfig config);

  Future<EngineResult<bool>> startAnalysis(CameraFrameCallback onFrame);

  Future<EngineResult<bool>> stopAnalysis();

  Future<EngineResult<CapturedPageImage>> captureStill();

  Future<EngineResult<bool>> setTorchEnabled(bool enabled);

  Future<void> dispose();
}

abstract interface class CameraFrameAnalyzer {
  Future<EngineResult<CameraFrameObservation>> analyze(
    CameraAnalysisFrame frame,
    CameraEngineConfig config,
  );

  void resetTracking();

  Future<void> dispose();
}
