import 'package:capstone_development/application/camera_scanner/domain/detected_page_geometry.dart';
import 'package:capstone_development/debug/p5_native_validation_fixture.dart';
import 'package:capstone_development/engines/aruco/application/marker_correspondence_service.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/layout/domain/layout_regions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('registration quadrilateral projects to true page corners', () {
    final page = buildP5NativeValidationPage();
    final regions = {
      for (final marker in page.markerRegions) marker.role: marker,
    };
    const roles = [
      MarkerRole.topLeft,
      MarkerRole.topRight,
      MarkerRole.bottomRight,
      MarkerRole.bottomLeft,
    ];
    const correspondence = MarkerCorrespondenceService();
    final tracked = [
      for (final role in roles)
        _cameraPoint(
          correspondence.physicalRegistrationToCanonical(regions[role]!, page),
        ),
    ];

    final outline = projectDetectedPageOutline(
      page: page,
      sourceRegistrationPoints: tracked,
    );

    expect(outline, hasLength(4));
    final width = page.canonicalPageSpec.widthPixels.toDouble();
    final height = page.canonicalPageSpec.heightPixels.toDouble();
    _expectSamePoint(outline[0], _cameraPoint(ImagePoint(0, 0)));
    _expectSamePoint(outline[1], _cameraPoint(ImagePoint(width, 0)));
    _expectSamePoint(outline[2], _cameraPoint(ImagePoint(width, height)));
    _expectSamePoint(outline[3], _cameraPoint(ImagePoint(0, height)));
  });

  test('missing registration point does not fabricate an outline', () {
    final outline = projectDetectedPageOutline(
      page: buildP5NativeValidationPage(),
      sourceRegistrationPoints: [
        ImagePoint(10, 10),
        ImagePoint(20, 10),
        ImagePoint(20, 20),
      ],
    );

    expect(outline, isEmpty);
  });
}

ImagePoint _cameraPoint(ImagePoint canonical) {
  final denominator = 1 + canonical.x * 0.00005 + canonical.y * 0.00003;
  return ImagePoint(
    (100 + canonical.x * 0.5 + canonical.y * 0.02) / denominator,
    (200 + canonical.x * 0.01 + canonical.y * 0.5) / denominator,
  );
}

void _expectSamePoint(ImagePoint actual, ImagePoint expected) {
  expect(actual.x, closeTo(expected.x, 1e-6));
  expect(actual.y, closeTo(expected.y, 1e-6));
}
