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

  test('marker geometry remaps to source coordinates and preserves ratios', () {
    final analysisDetection = ArucoDetection(
      sourceSize: ImageSize(width: 960, height: 540),
      markers: [
        _marker(10, 50, 50, 50),
        _marker(11, 860, 50, 50),
        _marker(12, 50, 440, 50),
        _marker(13, 860, 440, 50),
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
    expect(geometry.registrationPoints, [
      ImagePoint(200, 200),
      ImagePoint(1720, 200),
      ImagePoint(1720, 880),
      ImagePoint(200, 880),
    ]);
    expect(geometry.minimumMarkerSidePixels, closeTo(100, 1e-9));
    expect(
      geometry.pageAreaRatio,
      closeTo((1520 * 680) / (1920 * 1080), 1e-12),
    );
    expect(
      geometry.perspectiveRatio,
      closeTo(
        ImagePoint(200, 200).distanceTo(ImagePoint(1720, 880)) / 680,
        1e-12,
      ),
    );
  });

  test('camera worker source contains no PNG transport path', () {
    final source = File(
      'lib/engines/camera/infrastructure/isolate_camera_analysis_worker.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('encodePng')));
    expect(source, isNot(contains('decodePng')));
    expect(source, isNot(contains("package:image/image.dart")));
    expect(source, contains('OpenCvArucoDetector().detectGray'));
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
