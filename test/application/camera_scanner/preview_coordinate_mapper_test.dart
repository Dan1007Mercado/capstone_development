import 'package:capstone_development/application/camera_scanner/domain/preview_coordinate_mapper.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/camera/domain/camera_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const mapper = PreviewCoordinateMapper();

  test('portrait rotation maps source corners into portrait viewport', () {
    final mapped = mapper.mapQuadrilateral(
      sourcePoints: [
        ImagePoint(0, 0),
        ImagePoint(1920, 0),
        ImagePoint(1920, 1080),
        ImagePoint(0, 1080),
      ],
      sourceSize: ImageSize(width: 1920, height: 1080),
      viewportSize: const PreviewSize(300, 400),
      sensorOrientationDegrees: 90,
      deviceOrientation: CameraDeviceOrientation.portraitUp,
      mirrored: false,
    );

    expect(mapped[0].x, closeTo(300, 1e-9));
    expect(mapped[0].y, closeTo(-66.666, 0.01));
    expect(mapped[1].x, closeTo(300, 1e-9));
    expect(mapped[1].y, closeTo(466.666, 0.01));
    expect(mapped[2].x, closeTo(0, 1e-9));
    expect(mapped[2].y, closeTo(466.666, 0.01));
    expect(mapped[3].x, closeTo(0, 1e-9));
    expect(mapped[3].y, closeTo(-66.666, 0.01));
  });

  test('cover crop offsets landscape preview without stretching geometry', () {
    final center = mapper.mapPoint(
      sourcePoint: ImagePoint(960, 540),
      sourceSize: ImageSize(width: 1920, height: 1080),
      viewportSize: const PreviewSize(300, 400),
      sensorOrientationDegrees: 0,
      deviceOrientation: CameraDeviceOrientation.portraitUp,
      mirrored: false,
    );

    expect(center.x, closeTo(150, 1e-9));
    expect(center.y, closeTo(200, 1e-9));
  });

  test('front preview mirrors horizontal position after orientation', () {
    final normal = mapper.mapPoint(
      sourcePoint: ImagePoint(100, 200),
      sourceSize: ImageSize(width: 1000, height: 500),
      viewportSize: const PreviewSize(400, 200),
      sensorOrientationDegrees: 0,
      deviceOrientation: CameraDeviceOrientation.portraitUp,
      mirrored: false,
    );
    final mirrored = mapper.mapPoint(
      sourcePoint: ImagePoint(100, 200),
      sourceSize: ImageSize(width: 1000, height: 500),
      viewportSize: const PreviewSize(400, 200),
      sensorOrientationDegrees: 0,
      deviceOrientation: CameraDeviceOrientation.portraitUp,
      mirrored: true,
    );

    expect(mirrored.x, closeTo(400 - normal.x, 1e-9));
    expect(mirrored.y, closeTo(normal.y, 1e-9));
  });

  test('partial tracking never fabricates a full quadrilateral', () {
    final mapped = mapper.mapQuadrilateral(
      sourcePoints: [ImagePoint(10, 10), ImagePoint(20, 10)],
      sourceSize: ImageSize(width: 100, height: 100),
      viewportSize: const PreviewSize(100, 100),
      sensorOrientationDegrees: 0,
      deviceOrientation: CameraDeviceOrientation.portraitUp,
      mirrored: false,
    );

    expect(mapped, isEmpty);
  });

  test('portrait document polygon remains inside covered viewport', () {
    final mapped = mapper.mapQuadrilateral(
      sourcePoints: [
        ImagePoint(300, 100),
        ImagePoint(1620, 100),
        ImagePoint(1620, 980),
        ImagePoint(300, 980),
      ],
      sourceSize: ImageSize(width: 1920, height: 1080),
      viewportSize: const PreviewSize(300, 400),
      sensorOrientationDegrees: 90,
      deviceOrientation: CameraDeviceOrientation.portraitUp,
      mirrored: false,
    );

    expect(mapped, hasLength(4));
    for (final point in mapped) {
      expect(point.x, inInclusiveRange(0, 300));
      expect(point.y, inInclusiveRange(0, 400));
    }
  });

  test('sensor and device rotation share deterministic cover semantics', () {
    final oriented = mapper.orientedSourceSize(
      sourceSize: ImageSize(width: 1920, height: 1080),
      sensorOrientationDegrees: 90,
      deviceOrientation: CameraDeviceOrientation.landscapeLeft,
      mirrored: false,
    );
    final center = mapper.mapPoint(
      sourcePoint: ImagePoint(960, 540),
      sourceSize: ImageSize(width: 1920, height: 1080),
      viewportSize: const PreviewSize(400, 300),
      sensorOrientationDegrees: 90,
      deviceOrientation: CameraDeviceOrientation.landscapeLeft,
      mirrored: false,
    );

    expect(oriented.width / oriented.height, closeTo(16 / 9, 1e-9));
    expect(center.x, closeTo(200, 1e-9));
    expect(center.y, closeTo(150, 1e-9));
  });
}
