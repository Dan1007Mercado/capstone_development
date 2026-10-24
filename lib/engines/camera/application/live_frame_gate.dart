import '../domain/camera_engine_config.dart';
import '../domain/live_frame_analysis.dart';

final class LiveFrameGate {
  const LiveFrameGate();

  LiveFrameGateResult evaluate({
    required CameraEngineConfig config,
    required DetectedDocument? document,
    required DocumentQuality quality,
    required DocumentStability stability,
    required bool fallbackProbeDue,
  }) {
    if (!config.documentGateEnabled) {
      return const LiveFrameGateResult(
        reason: LiveFrameGateReason.disabled,
        shouldRunAruco: true,
        fallbackProbe: false,
      );
    }
    if (quality.brightness < config.minimumBrightness) {
      return _reject(LiveFrameGateReason.tooDark);
    }
    if (quality.brightness > config.maximumBrightness) {
      return _reject(LiveFrameGateReason.tooBright);
    }
    if (quality.sharpness < config.minimumSharpness) {
      return _reject(LiveFrameGateReason.tooBlurry);
    }
    if (document == null) {
      return LiveFrameGateResult(
        reason: LiveFrameGateReason.noDocument,
        shouldRunAruco: fallbackProbeDue,
        fallbackProbe: fallbackProbeDue,
      );
    }
    if (document.geometry.areaRatio < config.minimumDocumentAreaRatio) {
      return _reject(LiveFrameGateReason.tooSmall);
    }
    if (document.geometry.perspectiveRatio >
        config.maximumDocumentPerspectiveRatio) {
      return _reject(LiveFrameGateReason.tooSkewed);
    }
    if (!stability.isStable) {
      return _reject(LiveFrameGateReason.unstable);
    }
    return const LiveFrameGateResult(
      reason: LiveFrameGateReason.pass,
      shouldRunAruco: true,
      fallbackProbe: false,
    );
  }

  LiveFrameGateResult _reject(LiveFrameGateReason reason) =>
      LiveFrameGateResult(
        reason: reason,
        shouldRunAruco: false,
        fallbackProbe: false,
      );
}
