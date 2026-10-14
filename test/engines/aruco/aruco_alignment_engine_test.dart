import 'dart:typed_data';

import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/engines/aruco/application/aruco_alignment_engine.dart';
import 'package:capstone_development/engines/aruco/application/marker_correspondence_service.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_alignment_config.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_vision_backend.dart';
import 'package:capstone_development/engines/aruco/domain/detected_marker.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/layout/domain/layout_regions.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout/layout_test_fixtures.dart';

void main() {
  test('empty encoded image returns a structured image failure', () {
    final backend = _FakeBackend(_detectionFor(_page()));
    final result = ArucoAlignmentEngine(
      backend: backend,
    ).align(Uint8List(0), _page());

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'ARUCO_IMAGE_INVALID');
    expect(backend.opened, isFalse);
  });

  test('successful alignment exposes homography, image, and diagnostics', () {
    final page = _page();
    final backend = _FakeBackend(_detectionFor(page));
    final result = ArucoAlignmentEngine(
      backend: backend,
    ).align(Uint8List.fromList([1, 2, 3]), page);

    expect(result.isSuccess, isTrue);
    expect(
      result.value.canonicalPage.size.width,
      page.canonicalPageSpec.widthPixels,
    );
    expect(
      result.value.canonicalPage.size.height,
      page.canonicalPageSpec.heightPixels,
    );
    expect(result.value.homography.values, [1, 0, 0, 0, 1, 0, 0, 0, 1]);
    expect(result.value.observations, hasLength(4));
    expect(result.value.correspondences, hasLength(4));
    expect(result.value.diagnostics.reprojectionErrors, everyElement(0));
    expect(result.value.diagnostics.meanReprojectionError, 0);
    expect(result.value.diagnostics.maxReprojectionError, 0);
    expect(backend.session!.disposed, isTrue);
  });

  test('excessive reprojection error fails and disposes the session', () {
    final page = _page();
    final backend = _FakeBackend(
      _detectionFor(page),
      homography: HomographyMatrix([1, 0, 10, 0, 1, 0, 0, 0, 1]),
    );
    final result = ArucoAlignmentEngine(
      backend: backend,
    ).align(Uint8List.fromList([1]), page);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'ARUCO_REPROJECTION_FAILED');
    expect(backend.session!.disposed, isTrue);
  });
}

PageLayout _page() => buildLayout(fullTemplate()).pages.single;

ArucoDetection _detectionFor(PageLayout page) {
  const service = MarkerCorrespondenceService();
  final markers = <DetectedMarker>[];
  for (final region in page.markerRegions) {
    final target = service.physicalRegistrationToCanonical(region, page);
    markers.add(_markerAtRegistration(region, target));
  }
  return ArucoDetection(
    sourceSize: ImageSize(
      width: page.canonicalPageSpec.widthPixels,
      height: page.canonicalPageSpec.heightPixels,
    ),
    markers: markers,
  );
}

DetectedMarker _markerAtRegistration(MarkerRegion region, ImagePoint point) {
  const size = 20.0;
  final (left, top) = switch (region.role) {
    MarkerRole.topLeft => (point.x - size, point.y - size),
    MarkerRole.topRight => (point.x, point.y - size),
    MarkerRole.bottomLeft => (point.x - size, point.y),
    MarkerRole.bottomRight => (point.x, point.y),
  };
  return DetectedMarker(
    id: region.markerId,
    topLeft: ImagePoint(left, top),
    topRight: ImagePoint(left + size, top),
    bottomRight: ImagePoint(left + size, top + size),
    bottomLeft: ImagePoint(left, top + size),
  );
}

final class _FakeBackend implements ArucoVisionBackend {
  _FakeBackend(this.detection, {HomographyMatrix? homography})
    : homography = homography ?? HomographyMatrix([1, 0, 0, 0, 1, 0, 0, 0, 1]);

  final ArucoDetection detection;
  final HomographyMatrix homography;
  bool opened = false;
  _FakeSession? session;

  @override
  EngineResult<ArucoImageSession> open(
    Uint8List encodedImage,
    ArucoAlignmentConfig config,
  ) {
    opened = true;
    session = _FakeSession(detection, homography);
    return EngineResult.success(session!);
  }
}

final class _FakeSession implements ArucoImageSession {
  _FakeSession(this.detection, this.homography);

  @override
  final ArucoDetection detection;
  final HomographyMatrix homography;
  bool disposed = false;

  @override
  void dispose() => disposed = true;

  @override
  EngineResult<BackendRectification> rectify({
    required List<ImagePoint> sourcePoints,
    required List<ImagePoint> destinationPoints,
    required ImageSize outputSize,
  }) => EngineResult.success(
    BackendRectification(
      canonicalPage: CanonicalPageImage(
        size: outputSize,
        pngBytes: [137, 80, 78, 71],
      ),
      homography: homography,
    ),
  );
}
