import 'package:capstone_development/engines/aruco/domain/aruco_alignment_config.dart';
import 'package:capstone_development/engines/aruco/domain/detected_marker.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/infrastructure/opencv_aruco_vision_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'final detection size preserves aspect and supports full resolution',
    () {
      final source = ImageSize(width: 4000, height: 3000);

      expect(
        finalDetectionSize(source, 1200),
        ImageSize(width: 1200, height: 900),
      );
      expect(
        finalDetectionSize(source, 1400),
        ImageSize(width: 1400, height: 1050),
      );
      expect(
        finalDetectionSize(source, 1600),
        ImageSize(width: 1600, height: 1200),
      );
      expect(finalDetectionSize(source, null), source);
    },
  );

  test('reduced marker corners remap using OpenCV pixel-center geometry', () {
    final reduced = ArucoDetection(
      sourceSize: ImageSize(width: 1400, height: 1050),
      markers: [
        DetectedMarker(
          id: 10,
          topLeft: ImagePoint(70, 35),
          topRight: ImagePoint(140, 35),
          bottomRight: ImagePoint(140, 105),
          bottomLeft: ImagePoint(70, 105),
        ),
      ],
    );

    final remapped = remapDetectionToSource(
      reduced,
      ImageSize(width: 4000, height: 3000),
    );

    expect(remapped.sourceSize, ImageSize(width: 4000, height: 3000));
    expect(remapped.markers.single.id, 10);
    expect(
      remapped.markers.single.corner(MarkerCorner.topLeft),
      ImagePoint(200.92857142857144, 100.92857142857143),
    );
    expect(
      remapped.markers.single.corner(MarkerCorner.bottomRight),
      ImagePoint(400.92857142857144, 300.92857142857144),
    );
  });

  test('pixel-center remap handles nonuniform detection scaling', () {
    final remapped = remapDetectionToSource(
      ArucoDetection(
        sourceSize: ImageSize(width: 1000, height: 800),
        markers: [
          DetectedMarker(
            id: 10,
            topLeft: ImagePoint(9.5, 19.5),
            topRight: ImagePoint(19.5, 19.5),
            bottomRight: ImagePoint(19.5, 29.5),
            bottomLeft: ImagePoint(9.5, 29.5),
          ),
        ],
      ),
      ImageSize(width: 2000, height: 2400),
    );

    expect(
      remapped.markers.single.corner(MarkerCorner.topLeft),
      ImagePoint(19.5, 59.5),
    );
    expect(
      remapped.markers.single.corner(MarkerCorner.bottomRight),
      ImagePoint(39.5, 89.5),
    );
  });

  test('final marker detection maximum validates positive values', () {
    for (final value in [720, 800, 960, 1200, 1400, 1600]) {
      expect(
        ArucoAlignmentConfig(
          finalMarkerDetectionMaxDimension: value,
        ).finalMarkerDetectionMaxDimension,
        value,
      );
    }
    expect(
      () => ArucoAlignmentConfig(finalMarkerDetectionMaxDimension: 0),
      throwsArgumentError,
    );
  });
}
