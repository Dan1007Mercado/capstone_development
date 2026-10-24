import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/camera/application/frame_stability_tracker.dart';
import 'package:capstone_development/engines/camera/application/live_frame_gate.dart';
import 'package:capstone_development/engines/camera/domain/camera_engine_config.dart';
import 'package:capstone_development/engines/camera/domain/live_frame_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LiveFrameGate', () {
    final config = CameraEngineConfig(minimumSharpness: 10);
    const gate = LiveFrameGate();

    test('dark and blurred frames skip ArUco', () {
      expect(
        gate
            .evaluate(
              config: config,
              document: _document(),
              quality: const DocumentQuality(brightness: 20, sharpness: 20),
              stability: _stable,
              fallbackProbeDue: true,
            )
            .reason,
        LiveFrameGateReason.tooDark,
      );
      final blurred = gate.evaluate(
        config: config,
        document: _document(),
        quality: const DocumentQuality(brightness: 120, sharpness: 5),
        stability: _stable,
        fallbackProbeDue: true,
      );
      expect(blurred.reason, LiveFrameGateReason.tooBlurry);
      expect(blurred.shouldRunAruco, isFalse);
    });

    test('small document skips and valid document allows ArUco', () {
      final small = gate.evaluate(
        config: config,
        document: _document(areaRatio: 0.05),
        quality: _quality,
        stability: _stable,
        fallbackProbeDue: false,
      );
      expect(small.reason, LiveFrameGateReason.tooSmall);
      expect(small.shouldRunAruco, isFalse);
      expect(
        gate
            .evaluate(
              config: config,
              document: _document(),
              quality: _quality,
              stability: _stable,
              fallbackProbeDue: false,
            )
            .shouldRunAruco,
        isTrue,
      );
    });

    test('no-contour fallback probe occurs', () {
      final ordinary = gate.evaluate(
        config: config,
        document: null,
        quality: _quality,
        stability: DocumentStability.unavailable,
        fallbackProbeDue: false,
      );
      final probe = gate.evaluate(
        config: config,
        document: null,
        quality: _quality,
        stability: DocumentStability.unavailable,
        fallbackProbeDue: true,
      );
      expect(ordinary.shouldRunAruco, isFalse);
      expect(probe.shouldRunAruco, isTrue);
      expect(probe.fallbackProbe, isTrue);
    });

    test('disabled gate restores unconditional ArUco behavior', () {
      final result = gate.evaluate(
        config: CameraEngineConfig(documentGateEnabled: false),
        document: null,
        quality: const DocumentQuality(brightness: 0, sharpness: 0),
        stability: DocumentStability.unavailable,
        fallbackProbeDue: false,
      );
      expect(result.reason, LiveFrameGateReason.disabled);
      expect(result.shouldRunAruco, isTrue);
    });
  });

  group('FrameStabilityTracker', () {
    test('static quad becomes stable', () {
      final tracker = FrameStabilityTracker(
        maximumMotion: 0.02,
        minimumStableFrames: 3,
      );
      expect(tracker.update(_document()).isStable, isFalse);
      expect(tracker.update(_document()).isStable, isFalse);
      expect(tracker.update(_document()).isStable, isTrue);
    });

    test('moving quad stays unstable and sudden change resets count', () {
      final tracker = FrameStabilityTracker(
        maximumMotion: 0.02,
        minimumStableFrames: 2,
      );
      tracker.update(_document());
      final moved = tracker.update(_document(offset: 0.1));
      expect(moved.isStable, isFalse);
      expect(moved.stableFrameCount, 1);
    });
  });
}

const _quality = DocumentQuality(brightness: 120, sharpness: 100);
const _stable = DocumentStability(
  isStable: true,
  stableFrameCount: 3,
  motion: 0,
);

DetectedDocument _document({double areaRatio = 0.5, double offset = 0}) =>
    DetectedDocument(
      geometry: DocumentGeometry(
        corners: [
          ImagePoint(0.1 + offset, 0.1),
          ImagePoint(0.9 + offset, 0.1),
          ImagePoint(0.9 + offset, 0.9),
          ImagePoint(0.1 + offset, 0.9),
        ],
        areaRatio: areaRatio,
        centroid: ImagePoint(0.5 + offset, 0.5),
        perspectiveRatio: 1,
      ),
      confidence: 0.9,
    );
