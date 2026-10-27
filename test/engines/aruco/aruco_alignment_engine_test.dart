import 'dart:io';
import 'dart:typed_data';

import 'package:capstone_development/application/real_scanner/failed_scan_replay_bundle.dart';
import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/engines/aruco/application/aruco_alignment_engine.dart';
import 'package:capstone_development/engines/aruco/application/aruco_capture_replay_harness.dart';
import 'package:capstone_development/engines/aruco/application/marker_correspondence_service.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_alignment_config.dart';
import 'package:capstone_development/engines/aruco/domain/alignment_failure_diagnostics.dart';
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
    expect(
      result.value.diagnostics.selectionPolicy,
      HomographySelectionPolicy.fourPointBaseline,
    );
    expect(result.value.diagnostics.fourPointCandidate, isNotNull);
    expect(result.value.diagnostics.multiPointCandidate, isNull);
    expect(
      result.value.diagnostics.multiPointHomographyDuration,
      Duration.zero,
    );
    expect(result.value.diagnostics.multiPointEstimationFailureCode, isNull);
    expect(result.value.diagnostics.fallbackReason, isNull);
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
    expect(backend.session!.estimationMethods, [
      HomographyEstimationMethod.fourPoint,
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

  test(
    'safe baseline skips an optional fit even if it could have a lower residual',
    () {
      final page = _page();
      final backend = _FakeBackend(
        _detectionFor(page),
        fourPointHomography: HomographyMatrix([1, 0, 0.8, 0, 1, 0, 0, 0, 1]),
        multiPointHomography: HomographyMatrix([1, 0, 0, 0, 1, 0, 0, 0, 1]),
      );

      final result = ArucoAlignmentEngine(
        backend: backend,
        config: ArucoAlignmentConfig(
          selectionPolicy: HomographySelectionPolicy.fourPointBaseline,
        ),
      ).align(Uint8List.fromList([1]), page);

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      expect(
        result.value.diagnostics.selectedHomographyMethod,
        AlignmentHomographyMethod.fourPoint,
      );
      expect(result.value.diagnostics.multiPointCandidate, isNull);
      expect(backend.session!.estimationMethods, [
        HomographyEstimationMethod.fourPoint,
      ]);
      expect(
        result.value.diagnostics.selectionReason,
        'FOUR_POINT_VALIDATED_BASELINE',
      );
      expect(backend.session!.warpCount, 1);
    },
  );

  test('multi-point is selected as fallback when four-point is unsafe', () {
    final page = _page();
    final backend = _FakeBackend(
      _detectionFor(page),
      fourPointHomography: HomographyMatrix([1, 0, 2, 0, 1, 0, 0, 0, 1]),
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
      result.value.diagnostics.fallbackReason,
      'FITTING_REPROJECTION_EXCEEDED',
    );
    expect(backend.session!.estimationMethods, hasLength(2));
    expect(backend.session!.warpCount, 1);
    expect(
      result.value.diagnostics.fourPointCandidate!.rejectionReason,
      'FITTING_REPROJECTION_EXCEEDED',
    );
  });

  test('failed four-point estimator still attempts enabled multi-point', () {
    final page = _page();
    final backend = _FakeBackend(
      _detectionFor(page),
      failingMethods: const {HomographyEstimationMethod.fourPoint},
    );
    final result = ArucoAlignmentEngine(
      backend: backend,
    ).align(Uint8List.fromList([1]), page);
    expect(result.isSuccess, isTrue);
    expect(
      result.value.diagnostics.selectedHomographyMethod,
      AlignmentHomographyMethod.multiPoint,
    );
    expect(
      result.value.diagnostics.fourPointEstimationFailureCode,
      'ARUCO_HOMOGRAPHY_FAILED',
    );
    expect(backend.session!.estimationMethods, [
      HomographyEstimationMethod.fourPoint,
      HomographyEstimationMethod.multiPointRansac,
    ]);
    expect(backend.session!.warpCount, 1);
    expect(backend.session!.disposed, isTrue);
  });

  test('disabled multi-point cannot rescue an unsafe baseline', () {
    final page = _page();
    final backend = _FakeBackend(
      _detectionFor(page),
      fourPointHomography: HomographyMatrix([1, 0, 2, 0, 1, 0, 0, 0, 1]),
    );
    final result = ArucoAlignmentEngine(
      backend: backend,
      config: ArucoAlignmentConfig(enableMultipointHomography: false),
    ).align(Uint8List.fromList([1]), page);
    expect(result.isFailure, isTrue);
    final diagnostics = AlignmentFailureDiagnostics.findInDetails(
      result.error.details,
    )!;
    expect(
      diagnostics.multiPoint.validationStatus,
      HomographyValidationStatus.notRun,
    );
    expect(backend.session!.estimationMethods, [
      HomographyEstimationMethod.fourPoint,
    ]);
    expect(backend.session!.warpCount, 0);
    expect(backend.session!.disposed, isTrue);
  });

  test(
    'recorded failed-capture correspondences preserve the safe baseline',
    () {
      // Re-evaluates stored detections and estimates, not JPEG decoding, native
      // detection, actual warping, or answer accuracy.
      final bundle = const FailedScanReplayBundleCodec().decode(
        File('talaanscan_failed_capture.zip').readAsBytesSync(),
      );
      final recorded = AlignmentFailureDiagnostics.findInDetails(
        bundle.failure.details,
      )!;
      final ids = recorded.detectedRegistrationMarkerIds;
      ImagePoint corner(int id, MarkerCorner corner) {
        final point = recorded.detectedCorners.singleWhere(
          (point) => point['id'] == id && point['corner'] == corner.name,
        );
        return ImagePoint(
          (point['x']! as num).toDouble(),
          (point['y']! as num).toDouble(),
        );
      }

      final detection = ArucoDetection(
        sourceSize: recorded.sourceSize,
        markers: [
          for (final id in ids)
            DetectedMarker(
              id: id,
              topLeft: corner(id, MarkerCorner.topLeft),
              topRight: corner(id, MarkerCorner.topRight),
              bottomRight: corner(id, MarkerCorner.bottomRight),
              bottomLeft: corner(id, MarkerCorner.bottomLeft),
            ),
        ],
      );
      _FakeBackend backend() => _FakeBackend(
        detection,
        fourPointHomography: recorded.fourPoint.homography!,
        multiPointHomography: recorded.multiPoint.homography!,
        multiPointInliers: recorded.multiPoint.inlierMask,
        openTimings: ArucoBackendOpenTimings(
          detectionSize: recorded.detectionSize,
          detectionScaleX: recorded.detectionScaleX,
          detectionScaleY: recorded.detectionScaleY,
        ),
      );
      final baselineBackend = backend();
      final baseline = ArucoAlignmentEngine(
        backend: baselineBackend,
      ).align(bundle.encodedImage, bundle.page);
      expect(
        baseline.isSuccess,
        isTrue,
        reason: baseline.errorOrNull?.toString(),
      );
      expect(
        baseline.value.homography.values,
        recorded.fourPoint.homography!.values,
      );
      expect(
        baseline.value.diagnostics.maxReprojectionError,
        closeTo(recorded.fourPoint.maximumResidual!, 1e-8),
      );
      expect(baselineBackend.session!.estimationMethods, [
        HomographyEstimationMethod.fourPoint,
      ]);
      expect(baselineBackend.session!.warpCount, 1);
      final comparisonBackend = backend();
      final comparison = ArucoAlignmentEngine(
        backend: comparisonBackend,
        config: bundle.scannerConfig.alignment,
      ).align(bundle.encodedImage, bundle.page);
      expect(comparison.isSuccess, isTrue);
      expect(
        comparison.value.homography.values,
        baseline.value.homography.values,
      );
      expect(
        comparison.value.diagnostics.multiPointCandidate!.acceptance,
        HomographyCandidateAcceptance.acceptableWithLocalizedUncertainty,
      );
      expect(comparisonBackend.session!.estimationMethods, hasLength(2));
      expect(comparisonBackend.session!.warpCount, 1);
    },
  );

  for (final fixture in <(String, List<bool>)>[
    (
      'real-camera 12/16 support with two mildly unreliable markers',
      const [
        true,
        true,
        false,
        false,
        true,
        true,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
      ],
    ),
    (
      'recorded-resolution 12/16 spatial support',
      const [
        true,
        true,
        false,
        false,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        false,
      ],
    ),
    (
      'full-resolution 11/16 spatial support',
      const [
        true,
        true,
        false,
        false,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        false,
        true,
        true,
        true,
        false,
      ],
    ),
  ]) {
    test('multi-point accepts localized uncertainty with ${fixture.$1}', () {
      final page = _page();
      final backend = _FakeBackend(
        _detectionFor(page),
        fourPointHomography: HomographyMatrix([1, 0, 2, 0, 1, 0, 0, 0, 1]),
        multiPointInliers: fixture.$2,
      );

      final result = ArucoAlignmentEngine(
        backend: backend,
      ).align(Uint8List.fromList([1]), page);

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      final multi = result.value.diagnostics.multiPointCandidate!;
      expect(multi.accepted, isTrue);
      expect(
        multi.acceptance,
        HomographyCandidateAcceptance.acceptableWithLocalizedUncertainty,
      );
      expect(
        result.value.diagnostics.selectedHomographyMethod,
        AlignmentHomographyMethod.multiPoint,
      );
    });
  }

  test('multi-point rejects weak support spread across every marker', () {
    final page = _page();
    final result = ArucoAlignmentEngine(
      backend: _FakeBackend(
        _detectionFor(page),
        fourPointHomography: HomographyMatrix([1, 0, 2, 0, 1, 0, 0, 0, 1]),
        multiPointInliers: const [
          true,
          true,
          false,
          false,
          true,
          true,
          false,
          false,
          true,
          true,
          false,
          false,
          true,
          true,
          false,
          false,
        ],
      ),
    ).align(Uint8List.fromList([1]), page);

    expect(result.isFailure, isTrue);
    expect(
      result.error.details['multiPointRejectionReason'],
      'UNSAFE_INLIER_DISTRIBUTION',
    );
  });

  test('multi-point rejects 12/16 support concentrated in three markers', () {
    final page = _page();
    final result = ArucoAlignmentEngine(
      backend: _FakeBackend(
        _detectionFor(page),
        fourPointHomography: HomographyMatrix([1, 0, 2, 0, 1, 0, 0, 0, 1]),
        multiPointInliers: const [
          true,
          true,
          true,
          true,
          true,
          true,
          true,
          true,
          true,
          true,
          true,
          true,
          false,
          false,
          false,
          false,
        ],
      ),
    ).align(Uint8List.fromList([1]), page);

    expect(result.isFailure, isTrue);
    expect(
      result.error.details['multiPointRejectionReason'],
      'UNSAFE_INLIER_DISTRIBUTION',
    );
  });

  test(
    'default baseline does not select from multi-point fitting residuals',
    () {
      final page = _page();
      final result = ArucoAlignmentEngine(
        backend: _FakeBackend(
          _detectionFor(page),
          multiPointHomography: HomographyMatrix([1, 0, 0.5, 0, 1, 0, 0, 0, 1]),
        ),
      ).align(Uint8List.fromList([1]), page);

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      expect(
        result.value.diagnostics.selectedHomographyMethod,
        AlignmentHomographyMethod.fourPoint,
      );
      expect(
        result.value.diagnostics.selectionReason,
        'FOUR_POINT_VALIDATED_BASELINE',
      );
    },
  );

  test('validated accuracy policy can prefer a safe multi-point estimate', () {
    final page = _page();
    final backend = _FakeBackend(_detectionFor(page));

    final result = ArucoAlignmentEngine(
      backend: backend,
      config: ArucoAlignmentConfig(
        selectionPolicy:
            HomographySelectionPolicy.validatedMultiPointPreference,
      ),
    ).align(Uint8List.fromList([1]), page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(
      result.value.diagnostics.selectedHomographyMethod,
      AlignmentHomographyMethod.multiPoint,
    );
    expect(
      result.value.diagnostics.selectionReason,
      'EXTERNALLY_VALIDATED_MULTIPOINT_PREFERENCE',
    );
    expect(backend.session!.estimationMethods, hasLength(2));
    expect(backend.session!.warpCount, 1);
  });

  test('validated accuracy policy falls back from unsafe multi-point', () {
    final page = _page();
    final backend = _FakeBackend(
      _detectionFor(page),
      multiPointHomography: HomographyMatrix([1, 0, 5, 0, 1, 0, 0, 0, 1]),
    );

    final result = ArucoAlignmentEngine(
      backend: backend,
      config: ArucoAlignmentConfig(
        selectionPolicy:
            HomographySelectionPolicy.validatedMultiPointPreference,
      ),
    ).align(Uint8List.fromList([1]), page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(
      result.value.diagnostics.selectedHomographyMethod,
      AlignmentHomographyMethod.fourPoint,
    );
    expect(
      result.value.diagnostics.fallbackReason,
      'INLIER_REPROJECTION_EXCEEDED',
    );
    expect(backend.session!.warpCount, 1);
    expect(
      result.value.diagnostics.multiPointCandidate!.rejectionReason,
      'INLIER_REPROJECTION_EXCEEDED',
    );
  });

  test('both rejected estimates retain complete typed failure diagnostics', () {
    final page = _page();
    final backend = _FakeBackend(
      _detectionFor(page),
      fourPointHomography: HomographyMatrix([1, 0, 2, 0, 1, 0, 0, 0, 1]),
      multiPointHomography: HomographyMatrix([1, 0, 5, 0, 1, 0, 0, 0, 1]),
    );

    final result = ArucoAlignmentEngine(
      backend: backend,
    ).align(Uint8List.fromList([1]), page);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'ARUCO_REPROJECTION_FAILED');
    final diagnostics = AlignmentFailureDiagnostics.findInDetails(
      result.error.details,
    )!;
    expect(
      diagnostics.fourPoint.estimationStatus,
      HomographyEstimationStatus.succeeded,
    );
    expect(
      diagnostics.fourPoint.validationStatus,
      HomographyValidationStatus.rejected,
    );
    expect(
      diagnostics.fourPoint.rejectionReason,
      'FITTING_REPROJECTION_EXCEEDED',
    );
    expect(diagnostics.fourPoint.homography, isNotNull);
    expect(diagnostics.fourPoint.cornerResiduals, hasLength(16));
    expect(
      diagnostics.multiPoint.estimationStatus,
      HomographyEstimationStatus.succeeded,
    );
    expect(
      diagnostics.multiPoint.validationStatus,
      HomographyValidationStatus.rejected,
    );
    expect(
      diagnostics.multiPoint.rejectionReason,
      'INLIER_REPROJECTION_EXCEEDED',
    );
    expect(diagnostics.multiPoint.homography, isNotNull);
    expect(diagnostics.multiPoint.cornerResiduals, hasLength(16));
    expect(diagnostics.detectedRegistrationMarkerIds, hasLength(4));
    expect(diagnostics.selectionReason, 'NO_TRUSTWORTHY_HOMOGRAPHY');
    expect(backend.session!.estimationMethods, hasLength(2));
    expect(backend.session!.warpCount, 0);
  });

  test('estimation failure remains distinct while safe fallback is used', () {
    final page = _page();
    final backend = _FakeBackend(
      _detectionFor(page),
      failingMethods: const {HomographyEstimationMethod.multiPointRansac},
    );

    final result = ArucoAlignmentEngine(
      backend: backend,
      config: ArucoAlignmentConfig(
        selectionPolicy:
            HomographySelectionPolicy.validatedMultiPointPreference,
      ),
    ).align(Uint8List.fromList([1]), page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(
      result.value.diagnostics.selectedHomographyMethod,
      AlignmentHomographyMethod.fourPoint,
    );
    expect(
      result.value.diagnostics.multiPointEstimationFailureCode,
      'ARUCO_HOMOGRAPHY_FAILED',
    );
    expect(result.value.diagnostics.multiPointCandidate, isNull);
    expect(backend.session!.estimationMethods, hasLength(2));
    expect(backend.session!.warpCount, 1);
  });

  test('explicit rollback policy preserves four-point preference', () {
    final page = _page();
    final backend = _FakeBackend(
      _detectionFor(page),
      multiPointHomography: HomographyMatrix([1, 0, 0.5, 0, 1, 0, 0, 0, 1]),
    );

    final result = ArucoAlignmentEngine(
      backend: backend,
      config: ArucoAlignmentConfig(
        selectionPolicy: HomographySelectionPolicy.fourPointBaseline,
      ),
    ).align(Uint8List.fromList([1]), page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(
      result.value.diagnostics.selectedHomographyMethod,
      AlignmentHomographyMethod.fourPoint,
    );
    expect(backend.session!.warpCount, 1);
  });

  test(
    'multi-point fitting residual is not independent selection evidence',
    () {
      final page = _page();
      final backend = _FakeBackend(_detectionFor(page));

      final result = ArucoAlignmentEngine(
        backend: backend,
        config: ArucoAlignmentConfig(
          selectionPolicy:
              HomographySelectionPolicy.validatedMultiPointPreference,
        ),
      ).align(Uint8List.fromList([1]), page);

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      final multi = result.value.diagnostics.multiPointCandidate!;
      expect(multi.fittingResiduals!.maximum, 0);
      expect(multi.heldOutValidationResiduals, isNull);
      expect(multi.heldOutValidationMethod, isNull);
      expect(multi.accepted, isTrue);
      expect(multi.rejectionReason, isNull);
      expect(
        result.value.diagnostics.selectedHomographyMethod,
        AlignmentHomographyMethod.multiPoint,
      );
      expect(result.value.diagnostics.fallbackReason, isNull);
    },
  );

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

  test('reduced readable geometry scales localization tolerance', () {
    final page = _page();
    final canonicalToSource = HomographyMatrix([
      0.62,
      0,
      40,
      0,
      0.62,
      55,
      0,
      0,
      1,
    ]);
    final detection = _perturbDetection(
      _transformedDetection(page, canonicalToSource),
      0.75,
    );
    final backend = _FakeBackend(
      detection,
      homography: canonicalToSource.inverse(),
    );

    final result = ArucoAlignmentEngine(
      backend: backend,
    ).align(Uint8List.fromList([1]), page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(result.value.diagnostics.reprojectionScaleFactor, greaterThan(1));
    expect(
      result.value.diagnostics.effectiveReprojectionErrorPixels,
      greaterThan(1),
    );
    expect(
      result.value.diagnostics.maxReprojectionError,
      lessThanOrEqualTo(
        result.value.diagnostics.effectiveRansacReprojectionThresholdPixels!,
      ),
    );
  });

  test('scale-aware tolerance retains bounded gross-outlier ceiling', () {
    final page = _page();
    final canonicalToSource = HomographyMatrix([
      0.62,
      0,
      40,
      0,
      0.62,
      55,
      0,
      0,
      1,
    ]);
    final detection = _perturbDetection(
      _transformedDetection(page, canonicalToSource),
      3.0,
    );
    final backend = _FakeBackend(
      detection,
      homography: canonicalToSource.inverse(),
    );

    final result = ArucoAlignmentEngine(
      backend: backend,
    ).align(Uint8List.fromList([1]), page);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'ARUCO_REPROJECTION_FAILED');
    expect(backend.session!.warpCount, 0);
  });

  test('downsampled detector scale participates in localization tolerance', () {
    final page = _page();
    final canonicalToSource = HomographyMatrix([2, 0, 0, 0, 2, 0, 0, 0, 1]);
    final backend = _FakeBackend(
      _transformedDetection(page, canonicalToSource),
      homography: HomographyMatrix([0.5, 0, 1.2, 0, 0.5, 0, 0, 0, 1]),
      openTimings: const ArucoBackendOpenTimings(
        detectionScaleX: 3,
        detectionScaleY: 3,
      ),
    );

    final result = ArucoAlignmentEngine(
      backend: backend,
    ).align(Uint8List.fromList([1]), page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(result.value.diagnostics.reprojectionScaleFactor, closeTo(1.5, 0.1));
    expect(
      result.value.diagnostics.effectiveRansacReprojectionThresholdPixels,
      closeTo(2.25, 0.15),
    );
  });

  test('four-point baseline tolerates optional marker-corner disagreement', () {
    final page = _page();
    final detection = _detectionFor(page);
    final marker = detection.markers.first;
    final perturbed = ArucoDetection(
      sourceSize: detection.sourceSize,
      markers: [
        DetectedMarker(
          id: marker.id,
          topLeft: ImagePoint(
            marker.corner(MarkerCorner.topLeft).x - 12,
            marker.corner(MarkerCorner.topLeft).y - 12,
          ),
          topRight: ImagePoint(
            marker.corner(MarkerCorner.topRight).x,
            marker.corner(MarkerCorner.topRight).y - 12,
          ),
          bottomRight: marker.corner(MarkerCorner.bottomRight),
          bottomLeft: ImagePoint(
            marker.corner(MarkerCorner.bottomLeft).x - 12,
            marker.corner(MarkerCorner.bottomLeft).y,
          ),
        ),
        ...detection.markers.skip(1),
      ],
    );

    final result = ArucoAlignmentEngine(
      backend: _FakeBackend(perturbed),
      config: ArucoAlignmentConfig(enableMultipointHomography: false),
    ).align(Uint8List.fromList([1]), page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    final candidate = result.value.diagnostics.fourPointCandidate!;
    expect(candidate.accepted, isTrue);
    expect(candidate.fittingResiduals!.maximum, 0);
    expect(
      candidate.maxCommonReprojectionError,
      greaterThan(result.value.diagnostics.effectiveRejectedCornerErrorPixels!),
    );
  });

  test('four-point rejects an inaccurate fitted registration point', () {
    final page = _page();
    final detection = _detectionFor(page);
    final marker = detection.markers.first;
    final perturbed = ArucoDetection(
      sourceSize: detection.sourceSize,
      markers: [
        DetectedMarker(
          id: marker.id,
          topLeft: marker.corner(MarkerCorner.topLeft),
          topRight: marker.corner(MarkerCorner.topRight),
          bottomRight: ImagePoint(
            marker.corner(MarkerCorner.bottomRight).x + 2,
            marker.corner(MarkerCorner.bottomRight).y,
          ),
          bottomLeft: ImagePoint(
            marker.corner(MarkerCorner.bottomLeft).x + 2,
            marker.corner(MarkerCorner.bottomLeft).y,
          ),
        ),
        ...detection.markers.skip(1),
      ],
    );

    final result = ArucoAlignmentEngine(
      backend: _FakeBackend(perturbed),
      config: ArucoAlignmentConfig(enableMultipointHomography: false),
    ).align(Uint8List.fromList([1]), page);

    expect(result.isFailure, isTrue);
    expect(
      result.error.details['fourPointRejectionReason'],
      'FITTING_REPROJECTION_EXCEEDED',
    );
    expect(result.error.details['detectedCorners'], hasLength(16));
    expect(result.error.details['expectedCorners'], hasLength(16));
    expect(result.error.details['fourPointResiduals'], hasLength(16));
    expect(result.error.details['stageTimingsMs'], isA<Map>());
  });

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

  test(
    'capture replay compares legacy, current four, and current multi paths',
    () {
      final page = _page();
      var disposedBackends = 0;
      final replay = ArucoCaptureReplayHarness(
        backendFactory: () => _FakeBackend(_detectionFor(page)),
        disposeBackend: (_) => disposedBackends++,
      ).run(Uint8List.fromList([1, 2, 3]), page);

      expect(replay.legacyFourPoint.isSuccess, isTrue);
      expect(replay.legacyFourPoint.value.fittingResiduals, hasLength(4));
      expect(replay.legacyFourPoint.value.allCornerResiduals, hasLength(16));
      expect(replay.currentFourPointCandidate.isSuccess, isTrue);
      expect(replay.currentMultiPointCandidate.isSuccess, isTrue);
      expect(
        replay.currentMultiPointCandidate.value.candidate.method,
        AlignmentHomographyMethod.multiPoint,
      );
      expect(replay.currentMultiPointCandidate.value.homography, isNotNull);
      expect(replay.currentMultiPointCandidate.value.selectedForWarp, isTrue);
      expect(replay.currentMultiPointCandidate.value.canonicalPage, isNotNull);
      expect(replay.currentFourPointSelection.isSuccess, isTrue);
      expect(
        replay.currentFourPointSelection.value.canonicalPage,
        same(replay.currentFourPointCandidate.value.canonicalPage),
      );
      expect(
        replay.currentMultiPointSelection.value.canonicalPage,
        same(replay.currentMultiPointCandidate.value.canonicalPage),
      );
      expect(
        replay
            .currentMultiPointCandidate
            .value
            .candidate
            .heldOutValidationResiduals,
        isNull,
      );
      expect(replay.productionSelection.isSuccess, isTrue);
      expect(
        replay.productionSelection.value.diagnostics.selectedHomographyMethod,
        AlignmentHomographyMethod.fourPoint,
      );
      expect(
        replay.productionSelection.value.diagnostics.multiPointCandidate,
        isNull,
      );
      final repeated = ArucoCaptureReplayHarness(
        backendFactory: () => _FakeBackend(_detectionFor(page)),
        disposeBackend: (_) => disposedBackends++,
      ).run(Uint8List.fromList([1, 2, 3]), page);
      expect(
        repeated.currentMultiPointCandidate.value.homography!.values,
        replay.currentMultiPointCandidate.value.homography!.values,
      );
      expect(
        repeated
            .currentMultiPointCandidate
            .value
            .candidate
            .commonReprojectionErrors,
        replay
            .currentMultiPointCandidate
            .value
            .candidate
            .commonReprojectionErrors,
      );
      expect(disposedBackends, 8);
    },
  );

  test(
    'capture replay preserves both rejected candidates from failure diagnostics',
    () {
      final page = _page();
      final replay = ArucoCaptureReplayHarness(
        backendFactory: () => _FakeBackend(
          _detectionFor(page),
          fourPointHomography: HomographyMatrix([1, 0, 2, 0, 1, 0, 0, 0, 1]),
          multiPointHomography: HomographyMatrix([1, 0, 0, 0, 1, 0, 0, 0, 1]),
          multiPointInliers: const [
            false,
            false,
            false,
            false,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
            true,
          ],
        ),
      ).run(Uint8List.fromList([1, 2, 3]), page);

      expect(replay.productionSelection.isFailure, isTrue);
      expect(
        replay.productionSelection.error.code,
        'ARUCO_REPROJECTION_FAILED',
      );
      final four = replay.currentFourPointCandidate.value;
      final multi = replay.currentMultiPointCandidate.value;
      expect(four.candidate.accepted, isFalse);
      expect(four.candidate.rejectionReason, 'FITTING_REPROJECTION_EXCEEDED');
      expect(four.homography, isNotNull);
      expect(four.candidate.commonReprojectionErrors, hasLength(16));
      expect(
        four.failureAttempt!.effectiveReprojectionThresholdPixels,
        greaterThan(0),
      );
      expect(multi.candidate.accepted, isFalse);
      expect(multi.candidate.rejectionReason, 'UNSAFE_INLIER_DISTRIBUTION');
      expect(multi.homography, isNotNull);
      expect(multi.candidate.inlierMask, hasLength(16));
      expect(multi.candidate.inliersPerMarker, contains(0));
      expect(
        multi.failureAttempt!.effectiveRansacThresholdPixels,
        greaterThan(0),
      );
    },
  );

  test('capture replay keeps rejected and accepted candidates separate', () {
    final page = _page();
    final replay = ArucoCaptureReplayHarness(
      backendFactory: () => _FakeBackend(
        _detectionFor(page),
        fourPointHomography: HomographyMatrix([1, 0, 2, 0, 1, 0, 0, 0, 1]),
      ),
    ).run(Uint8List.fromList([1, 2, 3]), page);

    expect(replay.productionSelection.isSuccess, isTrue);
    expect(replay.currentFourPointCandidate.value.candidate.accepted, isFalse);
    expect(
      replay.currentFourPointCandidate.value.candidate.rejectionReason,
      'FITTING_REPROJECTION_EXCEEDED',
    );
    expect(replay.currentMultiPointCandidate.value.candidate.accepted, isTrue);
    expect(replay.currentMultiPointCandidate.value.failureAttempt, isNull);
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

  test(
    'final still accepts the sole fully validated duplicate interpretation',
    () {
      final page = _page();
      final detection = _detectionFor(page);
      final original = detection.markers.first;
      ImagePoint shifted(ImagePoint point) =>
          ImagePoint(point.x + 500, point.y + 400);
      final falseDuplicate = DetectedMarker(
        id: original.id,
        topLeft: shifted(original.corner(MarkerCorner.topLeft)),
        topRight: shifted(original.corner(MarkerCorner.topRight)),
        bottomRight: shifted(original.corner(MarkerCorner.bottomRight)),
        bottomLeft: shifted(original.corner(MarkerCorner.bottomLeft)),
      );
      final backend = _FakeBackend(
        ArucoDetection(
          sourceSize: detection.sourceSize,
          markers: [...detection.markers, falseDuplicate],
        ),
      );

      final result = ArucoAlignmentEngine(
        backend: backend,
      ).align(Uint8List.fromList([1]), page);

      expect(result.isSuccess, isTrue);
      expect(result.value.detectedMarkers, hasLength(4));
      expect(result.value.detectedMarkers.first.center, original.center);
    },
  );

  test('final still rejects two fully validated duplicate interpretations', () {
    final page = _page();
    final detection = _detectionFor(page);
    final original = detection.markers.first;
    final indistinguishable = DetectedMarker(
      id: original.id,
      topLeft: original.corner(MarkerCorner.topLeft),
      topRight: original.corner(MarkerCorner.topRight),
      bottomRight: original.corner(MarkerCorner.bottomRight),
      bottomLeft: original.corner(MarkerCorner.bottomLeft),
    );
    final backend = _FakeBackend(
      ArucoDetection(
        sourceSize: detection.sourceSize,
        markers: [...detection.markers, indistinguishable],
      ),
    );

    final result = ArucoAlignmentEngine(
      backend: backend,
    ).align(Uint8List.fromList([1]), page);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'SCAN_DUPLICATE_PAGE_MARKERS');
    expect(result.error.details['validInterpretations'], 2);
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

ArucoDetection _perturbDetection(ArucoDetection detection, double pixels) =>
    ArucoDetection(
      sourceSize: detection.sourceSize,
      markers: [
        for (var index = 0; index < detection.markers.length; index++)
          DetectedMarker(
            id: detection.markers[index].id,
            topLeft: _offsetCorner(
              detection.markers[index].corner(MarkerCorner.topLeft),
              pixels,
              index,
              0,
            ),
            topRight: _offsetCorner(
              detection.markers[index].corner(MarkerCorner.topRight),
              pixels,
              index,
              1,
            ),
            bottomRight: _offsetCorner(
              detection.markers[index].corner(MarkerCorner.bottomRight),
              pixels,
              index,
              2,
            ),
            bottomLeft: _offsetCorner(
              detection.markers[index].corner(MarkerCorner.bottomLeft),
              pixels,
              index,
              3,
            ),
          ),
      ],
    );

ImagePoint _offsetCorner(
  ImagePoint point,
  double pixels,
  int markerIndex,
  int cornerIndex,
) {
  final phase = markerIndex * 4 + cornerIndex;
  return ImagePoint(
    point.x + (phase.isEven ? pixels : -pixels),
    point.y + (phase % 3 == 0 ? -pixels : pixels),
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
    this.multiPointInliers,
    this.openTimings = const ArucoBackendOpenTimings(),
    this.failingMethods = const {},
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
  final List<bool>? multiPointInliers;
  final ArucoBackendOpenTimings openTimings;
  final Set<HomographyEstimationMethod> failingMethods;
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
      multiPointInliers,
      openTimings,
      failingMethods,
    );
    return EngineResult.success(session!);
  }
}

final class _FakeSession implements ArucoImageSession {
  _FakeSession(
    this.detection,
    this.fourPointHomography,
    this.multiPointHomography,
    this.multiPointInliers,
    this.openTimings,
    this.failingMethods,
  );

  @override
  final ArucoDetection detection;

  @override
  ImageSize get sourceSize => detection.sourceSize;

  @override
  final ArucoBackendOpenTimings openTimings;
  final HomographyMatrix fourPointHomography;
  final HomographyMatrix multiPointHomography;
  final List<bool>? multiPointInliers;
  final Set<HomographyEstimationMethod> failingMethods;
  bool disposed = false;
  int warpCount = 0;
  final List<HomographyEstimationMethod> estimationMethods = [];

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
    if (failingMethods.contains(method)) {
      return EngineResult.failure(
        EngineError(
          code: 'ARUCO_HOMOGRAPHY_FAILED',
          message: '${method.name} estimation failed.',
        ),
      );
    }
    final selectedHomography = switch (method) {
      HomographyEstimationMethod.fourPoint => fourPointHomography,
      HomographyEstimationMethod.multiPointRansac => multiPointHomography,
    };
    return EngineResult.success(
      BackendHomographyEstimate(
        homography: selectedHomography,
        inliers:
            method == HomographyEstimationMethod.multiPointRansac &&
                multiPointInliers != null
            ? multiPointInliers!
            : List<bool>.filled(sourcePoints.length, true),
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
