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
  test('homography inverse round-trips representative content points', () {
    final matrix = HomographyMatrix([
      0.8,
      0.04,
      25,
      -0.02,
      0.75,
      40,
      0.0001,
      -0.00008,
      1,
    ]);
    final inverse = matrix.inverse();

    for (final point in [
      ImagePoint(0, 0),
      ImagePoint(500, 700),
      ImagePoint(1000, 1400),
    ]) {
      expect(
        inverse.project(matrix.project(point)).distanceTo(point),
        lessThan(1e-8),
      );
    }
  });

  test('homography inverse is invariant to matrix representation scale', () {
    final matrix = HomographyMatrix([
      1e-10,
      0,
      2e-9,
      0,
      1e-10,
      3e-9,
      0,
      0,
      1e-10,
    ]);
    final point = ImagePoint(125, 250);

    final projected = matrix.project(point);
    final restored = matrix.inverse().project(projected);

    expect(restored.distanceTo(point), lessThan(1e-6));
  });

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

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
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
    expect(result.value.correspondences, hasLength(16));
    expect(
      result.value.diagnostics.selectedHomographyMethod,
      AlignmentHomographyMethod.fourPoint,
    );
    expect(result.value.diagnostics.fourPointCandidate, isNotNull);
    expect(result.value.diagnostics.multiPointCandidate, isNotNull);
    expect(result.value.diagnostics.reprojectionErrors, everyElement(0));
    expect(result.value.diagnostics.meanReprojectionError, 0);
    expect(result.value.diagnostics.maxReprojectionError, 0);
    expect(
      result.value.diagnostics.fourPointCandidate!.fittingResiduals!.errors,
      hasLength(4),
    );
    expect(
      result
          .value
          .diagnostics
          .fourPointCandidate!
          .heldOutValidationResiduals!
          .errors,
      hasLength(12),
    );
    expect(
      result.value.diagnostics.fourPointCandidate!.heldOutValidationMethod,
      HomographyValidationMethod.unusedFittingCorners,
    );
    expect(
      result.value.diagnostics.multiPointCandidate!.fittingResiduals!.errors,
      hasLength(16),
    );
    expect(
      result.value.diagnostics.multiPointCandidate!.heldOutValidationMethod,
      HomographyValidationMethod.leaveOneMarkerOut,
    );
    expect(
      result
          .value
          .diagnostics
          .multiPointCandidate!
          .heldOutValidationResiduals!
          .errors,
      hasLength(16),
    );
    expect(backend.session!.estimationMethods, [
      HomographyEstimationMethod.fourPoint,
      HomographyEstimationMethod.multiPointRansac,
      HomographyEstimationMethod.multiPointRansac,
      HomographyEstimationMethod.multiPointRansac,
      HomographyEstimationMethod.multiPointRansac,
      HomographyEstimationMethod.multiPointRansac,
    ]);
    expect(backend.session!.warpCount, 1);
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

  test('multi-point is selected only for a material held-out gain', () {
    final page = _page();
    final backend = _FakeBackend(
      _detectionFor(page),
      fourPointHomography: HomographyMatrix([1, 0, 0.8, 0, 1, 0, 0, 0, 1]),
      multiPointHomography: HomographyMatrix([1, 0, 0, 0, 1, 0, 0, 0, 1]),
    );

    final result = ArucoAlignmentEngine(
      backend: backend,
    ).align(Uint8List.fromList([1]), page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(
      result.value.diagnostics.selectedHomographyMethod,
      AlignmentHomographyMethod.multiPoint,
    );
    expect(
      result.value.diagnostics.multiPointCandidate!.heldOutValidationScore,
      lessThan(
        result.value.diagnostics.fourPointCandidate!.heldOutValidationScore!,
      ),
    );
    expect(backend.session!.warpCount, 1);
  });

  test('four-point remains selected when multi-point is not better', () {
    final page = _page();
    final backend = _FakeBackend(
      _detectionFor(page),
      multiPointHomography: HomographyMatrix([1, 0, 0.5, 0, 1, 0, 0, 0, 1]),
    );

    final result = ArucoAlignmentEngine(
      backend: backend,
    ).align(Uint8List.fromList([1]), page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(
      result.value.diagnostics.selectedHomographyMethod,
      AlignmentHomographyMethod.fourPoint,
    );
    expect(backend.session!.warpCount, 1);
  });

  test('multi-point fitting residual is not reported as held-out evidence', () {
    final page = _page();
    final backend = _FakeBackend(
      _detectionFor(page),
      crossValidationHomography: HomographyMatrix([1, 0, 5, 0, 1, 0, 0, 0, 1]),
    );

    final result = ArucoAlignmentEngine(
      backend: backend,
    ).align(Uint8List.fromList([1]), page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    final multi = result.value.diagnostics.multiPointCandidate!;
    expect(multi.fittingResiduals!.maximum, 0);
    expect(multi.heldOutValidationResiduals!.maximum, closeTo(5, 1e-9));
    expect(multi.accepted, isFalse);
    expect(multi.rejectionReason, 'HELD_OUT_REPROJECTION_EXCEEDED');
    expect(
      result.value.diagnostics.selectedHomographyMethod,
      AlignmentHomographyMethod.fourPoint,
    );
    expect(
      result.value.diagnostics.fallbackReason,
      'HELD_OUT_REPROJECTION_EXCEEDED',
    );
  });

  for (final fixture in <(String, HomographyMatrix)>[
    ('uniform scale', HomographyMatrix([0.62, 0, 40, 0, 0.62, 55, 0, 0, 1])),
    (
      'mild nonuniform affine scale',
      HomographyMatrix([0.70, 0.025, 35, 0.01, 0.61, 45, 0, 0, 1]),
    ),
  ]) {
    test('${fixture.$1} preserves independent bubble landmarks', () {
      final page = _page();
      final canonicalToSource = fixture.$2;
      final sourceToCanonical = canonicalToSource.inverse();
      final detection = _transformedDetection(page, canonicalToSource);
      final backend = _FakeBackend(detection, homography: sourceToCanonical);

      final result = ArucoAlignmentEngine(
        backend: backend,
      ).align(Uint8List.fromList([1]), page);

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      final errors = [
        for (final bubble in page.bubbleRegions)
          _bubbleCanonicalPoint(bubble, page).distanceTo(
            result.value.homography.project(
              canonicalToSource.project(_bubbleCanonicalPoint(bubble, page)),
            ),
          ),
      ];
      expect(errors, everyElement(lessThan(1e-6)));
      expect(
        result.value.correspondences.map((item) => item.markerId).toSet(),
        page.markerRegions.map((item) => item.markerId).toSet(),
      );
    });
  }

  test('four-point remains operational when multi-point is disabled', () {
    final page = _page();
    final backend = _FakeBackend(_detectionFor(page));

    final result = ArucoAlignmentEngine(
      backend: backend,
      config: ArucoAlignmentConfig(enableMultipointHomography: false),
    ).align(Uint8List.fromList([1]), page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(
      result.value.diagnostics.selectedHomographyMethod,
      AlignmentHomographyMethod.fourPoint,
    );
    expect(backend.session!.estimationMethods, [
      HomographyEstimationMethod.fourPoint,
    ]);
  });

  test('near-degenerate candidates fail before warping', () {
    final page = _page();
    final degenerate = HomographyMatrix([1, 0, 0, 0, 0, 0, 0, 0, 1]);
    final backend = _FakeBackend(_detectionFor(page), homography: degenerate);

    final result = ArucoAlignmentEngine(
      backend: backend,
    ).align(Uint8List.fromList([1]), page);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'ARUCO_REPROJECTION_FAILED');
    expect(backend.session!.warpCount, 0);
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
    markers.add(
      DetectedMarker(
        id: region.markerId,
        topLeft: service.physicalMarkerCornerToCanonical(
          region,
          MarkerCorner.topLeft,
          page,
        ),
        topRight: service.physicalMarkerCornerToCanonical(
          region,
          MarkerCorner.topRight,
          page,
        ),
        bottomRight: service.physicalMarkerCornerToCanonical(
          region,
          MarkerCorner.bottomRight,
          page,
        ),
        bottomLeft: service.physicalMarkerCornerToCanonical(
          region,
          MarkerCorner.bottomLeft,
          page,
        ),
      ),
    );
  }
  return ArucoDetection(
    sourceSize: ImageSize(
      width: page.canonicalPageSpec.widthPixels,
      height: page.canonicalPageSpec.heightPixels,
    ),
    markers: markers,
  );
}

ArucoDetection _transformedDetection(
  PageLayout page,
  HomographyMatrix canonicalToSource,
) {
  const service = MarkerCorrespondenceService();
  final markers = [
    for (final region in page.markerRegions)
      DetectedMarker(
        id: region.markerId,
        topLeft: canonicalToSource.project(
          service.physicalMarkerCornerToCanonical(
            region,
            MarkerCorner.topLeft,
            page,
          ),
        ),
        topRight: canonicalToSource.project(
          service.physicalMarkerCornerToCanonical(
            region,
            MarkerCorner.topRight,
            page,
          ),
        ),
        bottomRight: canonicalToSource.project(
          service.physicalMarkerCornerToCanonical(
            region,
            MarkerCorner.bottomRight,
            page,
          ),
        ),
        bottomLeft: canonicalToSource.project(
          service.physicalMarkerCornerToCanonical(
            region,
            MarkerCorner.bottomLeft,
            page,
          ),
        ),
      ),
  ];
  final transformedPageCorner = canonicalToSource.project(
    ImagePoint(
      page.canonicalPageSpec.widthPixels - 1,
      page.canonicalPageSpec.heightPixels - 1,
    ),
  );
  return ArucoDetection(
    sourceSize: ImageSize(
      width: transformedPageCorner.x.ceil() + 80,
      height: transformedPageCorner.y.ceil() + 80,
    ),
    markers: markers,
  );
}

ImagePoint _bubbleCanonicalPoint(BubbleRegion bubble, PageLayout page) =>
    ImagePoint(
      bubble.physicalCenter.x.millimeters /
          page.pageSpec.size.width.millimeters *
          page.canonicalPageSpec.widthPixels,
      bubble.physicalCenter.y.millimeters /
          page.pageSpec.size.height.millimeters *
          page.canonicalPageSpec.heightPixels,
    );

DetectedMarker _identityMarker(int id, double left) => DetectedMarker(
  id: id,
  topLeft: ImagePoint(left, 30),
  topRight: ImagePoint(left + 20, 30),
  bottomRight: ImagePoint(left + 20, 50),
  bottomLeft: ImagePoint(left, 50),
);

final class _FakeBackend implements ArucoVisionBackend {
  _FakeBackend(
    this.detection, {
    HomographyMatrix? homography,
    HomographyMatrix? fourPointHomography,
    HomographyMatrix? multiPointHomography,
    this.crossValidationHomography,
  }) : fourPointHomography =
           fourPointHomography ??
           homography ??
           HomographyMatrix([1, 0, 0, 0, 1, 0, 0, 0, 1]),
       multiPointHomography =
           multiPointHomography ??
           homography ??
           HomographyMatrix([1, 0, 0, 0, 1, 0, 0, 0, 1]);

  final ArucoDetection detection;
  final HomographyMatrix fourPointHomography;
  final HomographyMatrix multiPointHomography;
  final HomographyMatrix? crossValidationHomography;
  bool opened = false;
  _FakeSession? session;

  @override
  EngineResult<ArucoImageSession> open(
    Uint8List encodedImage,
    ArucoAlignmentConfig config,
  ) {
    opened = true;
    session = _FakeSession(
      detection,
      fourPointHomography,
      multiPointHomography,
      crossValidationHomography,
    );
    return EngineResult.success(session!);
  }
}

final class _FakeSession implements ArucoImageSession {
  _FakeSession(
    this.detection,
    this.fourPointHomography,
    this.multiPointHomography,
    this.crossValidationHomography,
  );

  @override
  final ArucoDetection detection;

  @override
  ImageSize get sourceSize => detection.sourceSize;

  @override
  ArucoBackendOpenTimings get openTimings => const ArucoBackendOpenTimings();
  final HomographyMatrix fourPointHomography;
  final HomographyMatrix multiPointHomography;
  final HomographyMatrix? crossValidationHomography;
  bool disposed = false;
  int warpCount = 0;
  final List<HomographyEstimationMethod> estimationMethods = [];
  int _multiPointEstimateCount = 0;

  @override
  void dispose() => disposed = true;

  @override
  EngineResult<BackendHomographyEstimate> estimateHomography({
    required List<ImagePoint> sourcePoints,
    required List<ImagePoint> destinationPoints,
    required HomographyEstimationMethod method,
    required double ransacReprojectionThresholdPixels,
    required int maximumIterations,
    required double confidence,
  }) {
    estimationMethods.add(method);
    final selectedHomography = switch (method) {
      HomographyEstimationMethod.fourPoint => fourPointHomography,
      HomographyEstimationMethod.multiPointRansac =>
        _multiPointEstimateCount++ == 0
            ? multiPointHomography
            : crossValidationHomography ?? multiPointHomography,
    };
    return EngineResult.success(
      BackendHomographyEstimate(
        homography: selectedHomography,
        inliers: List<bool>.filled(sourcePoints.length, true),
      ),
    );
  }

  @override
  EngineResult<BackendWarp> warp({
    required HomographyMatrix homography,
    required ImageSize outputSize,
  }) {
    warpCount++;
    return EngineResult.success(
      BackendWarp(
        canonicalPage: CanonicalPageImage(
          size: outputSize,
          pngBytes: [137, 80, 78, 71],
        ),
      ),
    );
  }
}
