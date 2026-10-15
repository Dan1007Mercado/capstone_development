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
    expect(source, contains('final detector = OpenCvArucoDetector();'));
    expect(source, contains('_analyzeInWorker(message, detector)'));
    expect(source, contains('detector.dispose();'));
  });
}
