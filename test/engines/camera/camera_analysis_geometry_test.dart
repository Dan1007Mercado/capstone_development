import 'dart:io';
import 'dart:typed_data';

import 'package:capstone_development/engines/aruco/domain/detected_marker.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/camera/infrastructure/camera_analysis_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('large landscape frame downscales to configured long edge', () {
    final source = Uint8List(1920 * 1080);
    final image = prepareCameraAnalysisImage(
      source: source,
      width: 1920,
      height: 1080,
      bytesPerRow: 1920,
      bytesPerPixel: 1,
      maximumDimension: 960,
    );

    expect(image.analysisSize, ImageSize(width: 960, height: 540));
    expect(image.analysisScaleX, 0.5);
    expect(image.analysisScaleY, 0.5);
    expect(image.pixels.length, 960 * 540);
  });

  test(
    'portrait downscale preserves aspect ratio without orientation assumptions',
    () {
      final image = prepareCameraAnalysisImage(
        source: Uint8List(1080 * 1920),
        width: 1080,
        height: 1920,
        bytesPerRow: 1080,
        bytesPerPixel: 1,
        maximumDimension: 960,
      );

      expect(image.analysisSize, ImageSize(width: 540, height: 960));
      expect(
        image.analysisSize.width / image.analysisSize.height,
        closeTo(1080 / 1920, 1e-12),
      );
    },
  );

  test('small compact frame is not upscaled or copied', () {
    final source = Uint8List.fromList(List.generate(640 * 2, (i) => i % 256));
    final image = prepareCameraAnalysisImage(
      source: source,
      width: 640,
      height: 2,
      bytesPerRow: 640,
      bytesPerPixel: 1,
      maximumDimension: 960,
    );

    expect(image.analysisSize, ImageSize(width: 640, height: 2));
    source[0] = 99;
    expect(image.pixels[0], 99);
    expect(image.analysisScaleX, 1);
    expect(image.analysisScaleY, 1);
  });

  test('strided downscale does not mutate source frame', () {
    final source = Uint8List.fromList([1, 2, 3, 99, 4, 5, 6, 99]);
    final before = Uint8List.fromList(source);

    final image = prepareCameraAnalysisImage(
      source: source,
      width: 3,
      height: 2,
      bytesPerRow: 4,
      bytesPerPixel: 1,
      maximumDimension: 2,
    );

    expect(source, before);
    expect(image.analysisSize, ImageSize(width: 2, height: 1));
    expect(image.pixels, [1, 2]);
  });

  for (final maximumDimension in [960, 800, 720]) {
    test(
      'marker geometry and IDs survive remapping at $maximumDimension px',
      () {
        final scale = maximumDimension / 960;
        final analysisDetection = ArucoDetection(
          sourceSize: ImageSize(
            width: maximumDimension,
            height: (540 * scale).round(),
          ),
          markers: [
            _marker(10, 50 * scale, 50 * scale, 50 * scale),
            _marker(11, 860 * scale, 50 * scale, 50 * scale),
            _marker(12, 50 * scale, 440 * scale, 50 * scale),
            _marker(13, 860 * scale, 440 * scale, 50 * scale),
          ],
        );
        final sourceDetection = remapArucoDetectionToSource(
          analysisDetection,
          ImageSize(width: 1920, height: 1080),
        );
        final geometry = calculateCameraMarkerGeometry(
          sourceDetection: sourceDetection,
          markerIds: const [10, 11, 12, 13],
        );

        expect(geometry.detectedMarkerIds, [10, 11, 12, 13]);
        final expected = [
          ImagePoint(200, 200),
          ImagePoint(1720, 200),
          ImagePoint(1720, 880),
          ImagePoint(200, 880),
        ];
        for (var index = 0; index < expected.length; index++) {
          expect(
            geometry.registrationPoints[index].x,
            closeTo(expected[index].x, 1e-9),
          );
          expect(
            geometry.registrationPoints[index].y,
            closeTo(expected[index].y, 1e-9),
          );
        }
        expect(geometry.minimumMarkerSidePixels, closeTo(100, 1e-9));
        expect(
          geometry.pageAreaRatio,
          closeTo((1520 * 680) / (1920 * 1080), 1e-12),
        );
      },
    );
  }

  test('camera worker source contains no PNG transport path', () {
    final source = File(
      'lib/engines/camera/infrastructure/isolate_camera_analysis_worker.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('encodePng')));
    expect(source, isNot(contains('decodePng')));
    expect(source, isNot(contains("package:image/image.dart")));
    expect(source, contains('final OpenCvArucoDetector detector'));
    expect(source, contains('_analyzeInWorker(message, state)'));
    expect(source, contains('state.detector.detectGray('));
    expect(source, contains('detector.dispose();'));
  });
}

DetectedMarker _marker(int id, double left, double top, double size) =>
    DetectedMarker(
      id: id,
      topLeft: ImagePoint(left, top),
      topRight: ImagePoint(left + size, top),
      bottomRight: ImagePoint(left + size, top + size),
      bottomLeft: ImagePoint(left, top + size),
    );
