import '../domain/camera_engine_config.dart';
import '../domain/live_frame_analysis.dart';

final class LiveFrameGate {
  const LiveFrameGate();

  LiveFrameGateResult evaluate({
    required CameraEngineConfig config,
    required LiveAnalysisMode analysisMode,
    required DocumentQuality quality,
    required bool fallbackProbeDue,
  }) {
    if (!config.documentGateEnabled) {
      return const LiveFrameGateResult(
        reason: LiveFrameGateReason.disabled,
        shouldRunAruco: true,
        fallbackProbe: false,
      );
    }
    // Live acquisition only rejects frames that are clearly unusable. The
    // stricter capture-quality thresholds remain authoritative in CameraEngine.
    if (quality.brightness < config.minimumBrightness * 0.5) {
      return _reject(LiveFrameGateReason.tooDark);
    }
    if (quality.brightness >
        config.maximumBrightness + (255 - config.maximumBrightness) * 0.5) {
      return _reject(LiveFrameGateReason.tooBright);
    }
    if (quality.sharpness < config.minimumSharpness * 0.5) {
      return _reject(LiveFrameGateReason.tooBlurry);
    }
    if (analysisMode == LiveAnalysisMode.search) {
      return LiveFrameGateResult(
        reason: LiveFrameGateReason.noDocument,
        shouldRunAruco: fallbackProbeDue,
        fallbackProbe: fallbackProbeDue,
      );
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

/// Keeps fast ArUco acquisition independent from contour continuity.
final class LiveAnalysisModeTracker {
  LiveAnalysisModeTracker({this.maximumAbsentFrames = 3});

  final int maximumAbsentFrames;
  LiveAnalysisMode _mode = LiveAnalysisMode.search;
  int _absentFrames = 0;

  LiveAnalysisMode get mode => _mode;

  LiveAnalysisMode beginFrame({required bool hasDocumentCandidate}) {
    if (hasDocumentCandidate) {
      _mode = LiveAnalysisMode.active;
      _absentFrames = 0;
    }
    return _mode;
  }

  void finishFrame({
    required bool hasDocumentCandidate,
    required bool hasMarker,
    required bool hasIdentity,
  }) {
    if (hasDocumentCandidate || hasMarker || hasIdentity) {
      _mode = LiveAnalysisMode.active;
      _absentFrames = 0;
      return;
    }
    if (_mode == LiveAnalysisMode.search) return;
    _absentFrames++;
    if (_absentFrames > maximumAbsentFrames) {
      _mode = LiveAnalysisMode.search;
      _absentFrames = 0;
    }
  }

  void reset() {
    _mode = LiveAnalysisMode.search;
    _absentFrames = 0;
  }
}
