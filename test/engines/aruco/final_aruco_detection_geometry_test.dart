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

  test('reduced marker corners remap exactly into full source coordinates', () {
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
      ImagePoint(200, 100),
    );
    expect(
      remapped.markers.single.corner(MarkerCorner.bottomRight),
      ImagePoint(400, 300),
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
