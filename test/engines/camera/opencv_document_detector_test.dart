import 'dart:typed_data';

import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/infrastructure/opencv_aruco_detector.dart';
import 'package:capstone_development/engines/camera/domain/live_frame_analysis.dart';
import 'package:capstone_development/engines/camera/infrastructure/opencv_document_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const detector = OpenCvDocumentDetector();
  late bool backendAvailable;
  String? unavailableReason;

  setUpAll(() {
    final probe = OpenCvArucoDetector();
    final result = probe.detectGray(
      pixels: Uint8List(100),
      width: 10,
      height: 10,
    );
    backendAvailable = result.isSuccess;
    unavailableReason = result.errorOrNull?.message;
    probe.dispose();
  });

  test('detects large rectangle and orders corners deterministically', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final pixels = _imageWithRectangle(
      200,
      300,
      left: 30,
      top: 25,
      right: 170,
      bottom: 275,
    );
    final document = detector.detect(
      pixels: pixels,
      width: 200,
      height: 300,
      cannyLowThreshold: 40,
      cannyHighThreshold: 120,
      polygonEpsilonRatio: 0.02,
    );
    expect(document, isNotNull);
    expect(document!.geometry.areaRatio, greaterThan(0.5));
    final corners = document.geometry.corners;
    expect(corners[0].x, lessThan(corners[1].x));
    expect(corners[0].y, lessThan(corners[3].y));
  });

  test('no contour is handled safely', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final document = detector.detect(
      pixels: Uint8List(200 * 300)..fillRange(0, 200 * 300, 128),
      width: 200,
      height: 300,
      cannyLowThreshold: 40,
      cannyHighThreshold: 120,
      polygonEpsilonRatio: 0.02,
    );
    expect(document, isNull);
  });

  test('corner ordering is independent of contour order', () {
    final ordered = orderDocumentCorners([
      ImagePoint(90, 90),
      ImagePoint(10, 90),
      ImagePoint(90, 10),
      ImagePoint(10, 10),
    ]);
    expect(ordered, [
      ImagePoint(10, 10),
      ImagePoint(90, 10),
      ImagePoint(90, 90),
      ImagePoint(10, 90),
    ]);
  });

  test('malformed corners are rejected without a detector exception', () {
    expect(
      tryOrderDocumentCorners([
        ImagePoint(10, 10),
        ImagePoint(10, 10),
        ImagePoint(90, 90),
        ImagePoint(10, 90),
      ]),
      isNull,
    );
  });

  test('best-effort detection converts native failure into diagnostics', () {
    final attempt = detectDocumentBestEffort(
      detector: _ThrowingDocumentDetector(),
      pixels: Uint8List(100),
      width: 10,
      height: 10,
      cannyLowThreshold: 40,
      cannyHighThreshold: 120,
      polygonEpsilonRatio: 0.02,
    );

    expect(attempt.document, isNull);
    expect(attempt.failed, isTrue);
    expect(attempt.error, contains('synthetic contour failure'));
  });
}

final class _ThrowingDocumentDetector implements DocumentDetector {
  @override
  DetectedDocument? detect({
    required Uint8List pixels,
    required int width,
    required int height,
    required double cannyLowThreshold,
    required double cannyHighThreshold,
    required double polygonEpsilonRatio,
  }) => throw StateError('synthetic contour failure');
}

Uint8List _imageWithRectangle(
  int width,
  int height, {
  required int left,
  required int top,
  required int right,
  required int bottom,
}) {
  final pixels = Uint8List(width * height);
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      pixels[y * width + x] = 240;
    }
  }
  return pixels;
}
