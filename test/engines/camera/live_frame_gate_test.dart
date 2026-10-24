import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/camera/application/document_tracker.dart';
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
              fallbackProbeDue: true,
            )
            .reason,
        LiveFrameGateReason.tooDark,
      );
      final blurred = gate.evaluate(
        config: config,
        document: _document(),
        quality: const DocumentQuality(brightness: 120, sharpness: 5),
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
        fallbackProbeDue: false,
      );
      final probe = gate.evaluate(
        config: config,
        document: null,
        quality: _quality,
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
        fallbackProbeDue: false,
      );
      expect(result.reason, LiveFrameGateReason.disabled);
      expect(result.shouldRunAruco, isTrue);
    });

    test('plausible moving document starts ArUco immediately', () {
      final result = gate.evaluate(
        config: config,
        document: _document(),
        quality: _quality,
        fallbackProbeDue: false,
      );

      expect(result.reason, LiveFrameGateReason.pass);
      expect(result.shouldRunAruco, isTrue);
    });
  });

  group('DocumentTracker', () {
    final frameSize = ImageSize(width: 1000, height: 1000);

    test('acquires immediately and smooths moving geometry', () {
      final tracker = DocumentTracker(
        maximumMotion: 0.02,
        minimumStableFrames: 3,
      );
      final acquired = tracker.update(_pixelDocument(), frameSize: frameSize);
      final moving = tracker.update(
        _pixelDocument(offset: 10),
        frameSize: frameSize,
      );

      expect(acquired.phase, DocumentTrackingPhase.acquired);
      expect(acquired.isFresh, isTrue);
      expect(moving.phase, DocumentTrackingPhase.tracking);
      expect(moving.document!.geometry.corners.first.x, closeTo(103.5, 1e-9));
    });

    test('temporary misses retain visual geometry then clear it', () {
      final tracker = DocumentTracker(
        maximumMotion: 0.02,
        minimumStableFrames: 3,
      );
      tracker.update(_pixelDocument(), frameSize: frameSize);

      for (var miss = 1; miss <= 3; miss++) {
        final retained = tracker.update(null, frameSize: frameSize);
        expect(retained.phase, DocumentTrackingPhase.temporarilyLost);
        expect(retained.document, isNotNull);
        expect(retained.isFresh, isFalse);
      }
      final lost = tracker.update(null, frameSize: frameSize);
      expect(lost.phase, DocumentTrackingPhase.searching);
      expect(lost.document, isNull);
    });

    test('brief miss reacquires the existing document track', () {
      final tracker = DocumentTracker(
        maximumMotion: 0.02,
        minimumStableFrames: 3,
      );
      tracker.update(_pixelDocument(), frameSize: frameSize);
      final missed = tracker.update(null, frameSize: frameSize);
      final reacquired = tracker.update(
        _pixelDocument(offset: 5),
        frameSize: frameSize,
      );

      expect(missed.phase, DocumentTrackingPhase.temporarilyLost);
      expect(reacquired.phase, DocumentTrackingPhase.tracking);
      expect(reacquired.isFresh, isTrue);
      expect(reacquired.temporaryMissCount, 0);
    });

    test('unrelated larger rectangle does not replace active track', () {
      final tracker = DocumentTracker(
        maximumMotion: 0.02,
        minimumStableFrames: 3,
      );
      final original = tracker.update(_pixelDocument(), frameSize: frameSize);
      final unrelated = tracker.update(
        _pixelDocument(offset: 500, areaRatio: 0.9),
        frameSize: frameSize,
      );

      expect(unrelated.phase, DocumentTrackingPhase.temporarilyLost);
      expect(unrelated.document, same(original.document));
      expect(unrelated.isFresh, isFalse);
    });
  });
}

const _quality = DocumentQuality(brightness: 120, sharpness: 100);
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

DetectedDocument _pixelDocument({double areaRatio = 0.5, double offset = 0}) =>
    DetectedDocument(
      geometry: DocumentGeometry(
        corners: [
          ImagePoint(100 + offset, 100),
          ImagePoint(900 + offset, 100),
          ImagePoint(900 + offset, 900),
          ImagePoint(100 + offset, 900),
        ],
        areaRatio: areaRatio,
        centroid: ImagePoint(500 + offset, 500),
        perspectiveRatio: 1,
      ),
      confidence: 0.9,
    );
