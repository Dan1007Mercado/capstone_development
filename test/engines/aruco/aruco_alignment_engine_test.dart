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

  test(
    'identity markers are retained but do not alter registration validation',
    () {
      final page = _page();
      final registration = _detectionFor(page);
      final identity = [
        _identityMarker(1, 400),
        _identityMarker(2, 440),
        _identityMarker(3, 480),
        _identityMarker(4, 520),
      ];
      final backend = _FakeBackend(
        ArucoDetection(
          sourceSize: registration.sourceSize,
          markers: [...registration.markers, ...identity],
        ),
      );

      final result = ArucoAlignmentEngine(
        backend: backend,
      ).align(Uint8List.fromList([1, 2, 3]), page);

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      expect(result.value.observations, hasLength(4));
      expect(result.value.detectedMarkers, hasLength(8));
      expect(result.value.diagnostics.detectedMarkerIds, hasLength(8));
    },
  );

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

  test('final still rejects a different page marker signature', () {
    final pages = buildLayout(longTemplate(30)).pages;
    final backend = _FakeBackend(_detectionFor(pages[1]));

    final result = ArucoAlignmentEngine(
      backend: backend,
    ).align(Uint8List.fromList([1]), pages[0]);

    expect(result.error.code, 'SCAN_UNKNOWN_PAGE_MARKERS');
    expect(backend.session!.disposed, isTrue);
  });

  test('final still rejects duplicate marker IDs', () {
    final page = _page();
    final detection = _detectionFor(page);
    final duplicate = ArucoDetection(
      sourceSize: detection.sourceSize,
      markers: [
        detection.markers[0],
        detection.markers[0],
        detection.markers[2],
        detection.markers[3],
      ],
    );
    final backend = _FakeBackend(duplicate);

    final result = ArucoAlignmentEngine(
      backend: backend,
    ).align(Uint8List.fromList([1]), page);

    expect(result.error.code, 'SCAN_DUPLICATE_PAGE_MARKERS');
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

DetectedMarker _identityMarker(int id, double left) => DetectedMarker(
  id: id,
  topLeft: ImagePoint(left, 30),
  topRight: ImagePoint(left + 20, 30),
  bottomRight: ImagePoint(left + 20, 50),
  bottomLeft: ImagePoint(left, 50),
);

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

  @override
  ImageSize get sourceSize => ImageSize(width: 1200, height: 1800);

  @override
  ArucoBackendOpenTimings get openTimings => const ArucoBackendOpenTimings();
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
