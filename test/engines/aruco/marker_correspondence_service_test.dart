import 'package:capstone_development/engines/aruco/application/marker_correspondence_service.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_alignment_config.dart';
import 'package:capstone_development/engines/aruco/domain/detected_marker.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/layout/domain/layout_regions.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout/layout_test_fixtures.dart';

void main() {
  const service = MarkerCorrespondenceService();
  final page = buildLayout(
    fullTemplate(),
    config: testConfig(
      markerIds: const MarkerIds(
        topLeft: 41,
        topRight: 7,
        bottomLeft: 23,
        bottomRight: 5,
      ),
    ),
  ).pages.single;

  test('marker IDs map to PageLayout roles independent of detector order', () {
    final markers = _uprightMarkers(page.markerRegions).reversed;
    final result = service.build(
      detection: ArucoDetection(
        sourceSize: ImageSize(width: 1000, height: 1400),
        markers: markers,
      ),
      page: page,
      config: ArucoAlignmentConfig(),
    );

    expect(result.isSuccess, isTrue);
    expect(result.value.correspondences.map((item) => item.role), [
      MarkerRole.topLeft,
      MarkerRole.topRight,
      MarkerRole.bottomRight,
      MarkerRole.bottomLeft,
    ]);
    expect(result.value.correspondences.map((item) => item.markerId), [
      41,
      7,
      5,
      23,
    ]);
  });

  test('each page role selects its P4.1 page-facing detected corner', () {
    final result = _build(service, page, _uprightMarkers(page.markerRegions));

    expect(result.value.correspondences.map((item) => item.sourceCorner), [
      MarkerCorner.bottomRight,
      MarkerCorner.bottomLeft,
      MarkerCorner.topLeft,
      MarkerCorner.topRight,
    ]);
    expect(result.value.sourcePoints, [
      ImagePoint(140, 140),
      ImagePoint(860, 140),
      ImagePoint(860, 1260),
      ImagePoint(140, 1260),
    ]);
  });

  test('destination points derive from physical registration points', () {
    final result = _build(service, page, _uprightMarkers(page.markerRegions));

    for (final correspondence in result.value.correspondences) {
      final region = page.markerRegions.singleWhere(
        (marker) => marker.markerId == correspondence.markerId,
      );
      expect(
        correspondence.destinationPoint.x,
        closeTo(
          region.physicalRegistrationPoint.x.millimeters /
              page.pageSpec.size.width.millimeters *
              page.canonicalPageSpec.widthPixels,
          1e-9,
        ),
      );
      expect(
        correspondence.destinationPoint.y,
        closeTo(
          region.physicalRegistrationPoint.y.millimeters /
              page.pageSpec.size.height.millimeters *
              page.canonicalPageSpec.heightPixels,
          1e-9,
        ),
      );
    }
  });

  test('90-degree image rotation preserves semantic role matching', () {
    final rotated = _uprightMarkers(page.markerRegions)
        .map(
          (marker) => _transform(
            marker,
            (point) => ImagePoint(1399 - point.y, point.x),
          ),
        )
        .toList();
    final result = service.build(
      detection: ArucoDetection(
        sourceSize: ImageSize(width: 1400, height: 1000),
        markers: rotated,
      ),
      page: page,
      config: ArucoAlignmentConfig(),
    );

    expect(result.isSuccess, isTrue);
    expect(result.value.correspondences.map((item) => item.markerId), [
      41,
      7,
      5,
      23,
    ]);
  });

  test('duplicate expected marker returns structured ambiguity failure', () {
    final markers = _uprightMarkers(page.markerRegions);
    final result = _build(service, page, [...markers, markers.first]);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'ARUCO_REQUIRED_MARKER_DUPLICATE');
    expect(result.error.details['duplicateMarkerIds'], [41]);
  });

  test('missing expected marker returns structured failure', () {
    final markers = _uprightMarkers(page.markerRegions)..removeLast();
    final result = _build(service, page, markers);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'ARUCO_REQUIRED_MARKER_MISSING');
  });

  test('unrelated marker is ignored by default', () {
    final markers = _uprightMarkers(page.markerRegions)
      ..add(_marker(99, 450, 650));
    final result = _build(service, page, markers);

    expect(result.isSuccess, isTrue);
    expect(result.value.observations, hasLength(4));
  });

  test('mirrored marker topology is rejected', () {
    final mirrored = _uprightMarkers(page.markerRegions)
        .map(
          (marker) =>
              _transform(marker, (point) => ImagePoint(999 - point.x, point.y)),
        )
        .toList();
    final result = _build(service, page, mirrored);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'ARUCO_REFLECTION_DETECTED');
  });

  test('degenerate registration quadrilateral is rejected', () {
    final idsByRole = {
      for (final marker in page.markerRegions) marker.role: marker.markerId,
    };
    final markers = [
      _marker(idsByRole[MarkerRole.topLeft]!, 100, 500),
      _marker(idsByRole[MarkerRole.topRight]!, 300, 500),
      _marker(idsByRole[MarkerRole.bottomLeft]!, 700, 500),
      _marker(idsByRole[MarkerRole.bottomRight]!, 500, 500),
    ];
    final result = _build(service, page, markers);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'ARUCO_GEOMETRY_INVALID');
  });

  test('marker below configured minimum size is rejected', () {
    final markers = _uprightMarkers(page.markerRegions);
    final first = markers.first;
    markers[0] = DetectedMarker(
      id: first.id,
      topLeft: ImagePoint(100, 100),
      topRight: ImagePoint(105, 100),
      bottomRight: ImagePoint(105, 105),
      bottomLeft: ImagePoint(100, 105),
    );
    final result = _build(service, page, markers);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'ARUCO_MARKER_TOO_SMALL');
  });

  test('corner outside source image is rejected', () {
    final markers = _uprightMarkers(page.markerRegions);
    markers[0] = DetectedMarker(
      id: markers[0].id,
      topLeft: ImagePoint(-1, 100),
      topRight: ImagePoint(40, 100),
      bottomRight: ImagePoint(40, 140),
      bottomLeft: ImagePoint(-1, 140),
    );
    final result = _build(service, page, markers);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'ARUCO_GEOMETRY_INVALID');
  });
}

EngineResult<MarkerCorrespondenceSet> _build(
  MarkerCorrespondenceService service,
  PageLayout page,
  Iterable<DetectedMarker> markers,
) => service.build(
  detection: ArucoDetection(
    sourceSize: ImageSize(width: 1000, height: 1400),
    markers: markers,
  ),
  page: page,
  config: ArucoAlignmentConfig(),
);

List<DetectedMarker> _uprightMarkers(List<MarkerRegion> regions) {
  final byRole = {for (final marker in regions) marker.role: marker.markerId};
  return [
    _marker(byRole[MarkerRole.topLeft]!, 100, 100),
    _marker(byRole[MarkerRole.topRight]!, 860, 100),
    _marker(byRole[MarkerRole.bottomLeft]!, 100, 1260),
    _marker(byRole[MarkerRole.bottomRight]!, 860, 1260),
  ];
}

DetectedMarker _marker(int id, double left, double top, [double size = 40]) =>
    DetectedMarker(
      id: id,
      topLeft: ImagePoint(left, top),
      topRight: ImagePoint(left + size, top),
      bottomRight: ImagePoint(left + size, top + size),
      bottomLeft: ImagePoint(left, top + size),
    );

DetectedMarker _transform(
  DetectedMarker marker,
  ImagePoint Function(ImagePoint) transform,
) => DetectedMarker(
  id: marker.id,
  topLeft: transform(marker.corner(MarkerCorner.topLeft)),
  topRight: transform(marker.corner(MarkerCorner.topRight)),
  bottomRight: transform(marker.corner(MarkerCorner.bottomRight)),
  bottomLeft: transform(marker.corner(MarkerCorner.bottomLeft)),
);
