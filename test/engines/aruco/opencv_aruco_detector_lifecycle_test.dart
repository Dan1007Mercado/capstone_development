import 'dart:io';

import 'package:capstone_development/engines/aruco/infrastructure/opencv_aruco_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uninitialized detector disposes idempotently without native work', () {
    final detector = OpenCvArucoDetector();
    expect(() {
      detector.dispose();
      detector.dispose();
    }, returnsNormally);
  });

  test('camera worker owns one persistent detector inside its isolate', () {
    final source = File(
      'lib/engines/camera/infrastructure/isolate_camera_analysis_worker.dart',
    ).readAsStringSync();

    expect(RegExp(r'OpenCvArucoDetector\(\)').allMatches(source).length, 1);
    expect(source, contains('final OpenCvArucoDetector detector'));
    expect(source, contains('_analyzeInWorker(message, state)'));
    expect(source, contains('detector.dispose();'));
  });

  test('final scanner worker owns and disposes one persistent backend', () {
    final source = File(
      'lib/application/camera_scanner/infrastructure/'
      'isolate_offline_scanner_runner.dart',
    ).readAsStringSync();

    expect(
      RegExp(r'OpenCvArucoVisionBackend\(\)').allMatches(source).length,
      1,
    );
    expect(source, contains('alignmentBackend?.dispose();'));
    expect(source, contains('alignmentBackend: alignmentBackend!'));
  });

  test(
    'final scanner native path remains grayscale without PNG round trip',
    () {
      final source = File(
        'lib/engines/aruco/infrastructure/opencv_aruco_vision_backend.dart',
      ).readAsStringSync();

      expect(source, contains('cv.IMREAD_GRAYSCALE'));
      expect(source, isNot(contains('cv.IMREAD_COLOR')));
      expect(source, isNot(contains('cv.COLOR_BGR2GRAY')));
      expect(source, isNot(contains('cv.imencode')));
      expect(source, contains('cv.resize'));
      expect(source, contains('cv.warpPerspective(_image!'));
    },
  );
}
