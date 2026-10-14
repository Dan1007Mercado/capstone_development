import '../../../core/result/engine_result.dart';
import 'camera_engine_config.dart';
import 'camera_models.dart';

typedef CameraFrameCallback = void Function(CameraAnalysisFrame frame);

abstract interface class CameraBackend {
  Future<EngineResult<CameraPreviewInfo>> initialize(CameraEngineConfig config);

  Future<EngineResult<bool>> startAnalysis(CameraFrameCallback onFrame);

  Future<EngineResult<bool>> stopAnalysis();

  Future<EngineResult<CapturedPageImage>> captureStill();

  Future<void> dispose();
}

abstract interface class CameraFrameAnalyzer {
  Future<EngineResult<CameraFrameObservation>> analyze(
    CameraAnalysisFrame frame,
    CameraEngineConfig config,
  );

  Future<void> dispose();
}
