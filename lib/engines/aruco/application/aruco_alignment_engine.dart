import 'dart:typed_data';

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../layout/domain/page_layout.dart';
import '../domain/aruco_alignment_config.dart';
import '../domain/aruco_vision_backend.dart';
import '../domain/image_geometry.dart';
import '../domain/marker_correspondence.dart';
import '../domain/page_alignment_result.dart';
import 'homography_geometry_validator.dart';
import 'marker_correspondence_service.dart';
import 'marker_role_splitter.dart';

final class ArucoAlignmentEngine {
  const ArucoAlignmentEngine({
    required this.backend,
    this.correspondenceService = const MarkerCorrespondenceService(),
    this.geometryValidator = const HomographyGeometryValidator(),
    this.roleSplitter = const MarkerRoleSplitter(),
    this.config,
  });

  final ArucoVisionBackend backend;
  final MarkerCorrespondenceService correspondenceService;
  final HomographyGeometryValidator geometryValidator;
  final MarkerRoleSplitter roleSplitter;
  final ArucoAlignmentConfig? config;

  EngineResult<PageAlignmentResult> align(
    Uint8List encodedImage,
    PageLayout page,
  ) {
    final stopwatch = Stopwatch()..start();
    if (encodedImage.isEmpty) {
      return _failure('ARUCO_IMAGE_INVALID', 'Source image bytes are empty.');
    }
    final effectiveConfig = config ?? ArucoAlignmentConfig();
    final sessionResult = backend.open(encodedImage, effectiveConfig);
    if (sessionResult.isFailure) {
      return EngineResult.failure(sessionResult.error);
    }

    final session = sessionResult.value;
    try {
      final pageResolutionStopwatch = Stopwatch()..start();
      final detectedIds = session.detection.markers
          .map((marker) => marker.id)
          .toList(growable: false);
      final expectedIds = page.markerRegions
          .map((marker) => marker.markerId)
          .toSet();
      final split = roleSplitter.split(session.detection.markers, expectedIds);
      final registrationIds = split.registrationMarkers
          .map((marker) => marker.id)
          .toList(growable: false);
      if (registrationIds.toSet().length != registrationIds.length) {
        return _failure(
          'SCAN_DUPLICATE_PAGE_MARKERS',
          'A page marker ID was detected more than once.',
          {'detectedMarkerIds': detectedIds},
        );
      }
      if (registrationIds.length != expectedIds.length ||
          !registrationIds.toSet().containsAll(expectedIds)) {
        return _failure(
          'SCAN_UNKNOWN_PAGE_MARKERS',
          'The captured still does not match the live-resolved page markers.',
          {
            'expectedMarkerIds': expectedIds.toList()..sort(),
            'detectedMarkerIds': detectedIds.toList()..sort(),
          },
        );
      }
      pageResolutionStopwatch.stop();
      final correspondenceStopwatch = Stopwatch()..start();
      final correspondenceResult = correspondenceService.build(
        detection: session.detection,
        page: page,
        config: effectiveConfig,
      );
      correspondenceStopwatch.stop();
      if (correspondenceResult.isFailure) {
        return EngineResult.failure(correspondenceResult.error);
      }
      final correspondenceSet = correspondenceResult.value;
      final outputSize = ImageSize(
        width: page.canonicalPageSpec.widthPixels,
        height: page.canonicalPageSpec.heightPixels,
      );
      final fourPointEstimate = session.estimateHomography(
        sourcePoints: correspondenceSet.baselineSourcePoints,
        destinationPoints: correspondenceSet.baselineDestinationPoints,
        method: HomographyEstimationMethod.fourPoint,
        ransacReprojectionThresholdPixels:
            effectiveConfig.multipointRansacReprojectionThresholdPixels,
        maximumIterations: effectiveConfig.multipointMaximumIterations,
        confidence: effectiveConfig.multipointConfidence,
      );
      final validationStopwatch = Stopwatch()..start();
      final fourPointCandidate = fourPointEstimate.isSuccess
          ? _evaluateCandidate(
              estimate: fourPointEstimate.value,
              method: AlignmentHomographyMethod.fourPoint,
              fittingCorrespondences: correspondenceSet.baselineCorrespondences,
              fullCorrespondences: correspondenceSet.allCornerCorrespondences,
              heldOutValidationResiduals: _residualStatistics(
                fourPointEstimate.value.homography,
                _fourPointHeldOutCorrespondences(correspondenceSet),
              ),
              page: page,
              sourceSize: session.sourceSize,
              config: effectiveConfig,
            )
          : null;

      EngineResult<BackendHomographyEstimate>? multiPointEstimate;
      HomographyCandidateDiagnostics? multiPointCandidate;
      _CrossValidationResult? multiPointCrossValidation;
      if (effectiveConfig.enableMultipointHomography) {
        multiPointEstimate = session.estimateHomography(
          sourcePoints: correspondenceSet.allSourcePoints,
          destinationPoints: correspondenceSet.allDestinationPoints,
          method: HomographyEstimationMethod.multiPointRansac,
          ransacReprojectionThresholdPixels:
              effectiveConfig.multipointRansacReprojectionThresholdPixels,
          maximumIterations: effectiveConfig.multipointMaximumIterations,
          confidence: effectiveConfig.multipointConfidence,
        );
        if (multiPointEstimate.isSuccess) {
          multiPointCrossValidation = _crossValidateMultipoint(
            session: session,
            correspondences: correspondenceSet.allCornerCorrespondences,
            page: page,
            config: effectiveConfig,
          );
          multiPointCandidate = _evaluateCandidate(
            estimate: multiPointEstimate.value,
            method: AlignmentHomographyMethod.multiPoint,
            fittingCorrespondences: correspondenceSet.allCornerCorrespondences,
            fullCorrespondences: correspondenceSet.allCornerCorrespondences,
            heldOutValidationResiduals: multiPointCrossValidation.statistics,
            heldOutValidationUnavailableReason:
                multiPointCrossValidation.unavailableReason,
            page: page,
            sourceSize: session.sourceSize,
            config: effectiveConfig,
          );
        }
      }
      validationStopwatch.stop();

      final selection = _selectMethod(
        fourPointCandidate,
        multiPointCandidate,
        effectiveConfig,
      );
      final selectedMethod = selection.method;
      if (selectedMethod == null) {
        return _failure(
          'ARUCO_REPROJECTION_FAILED',
          'Neither homography candidate passed alignment validation '
              '(fourPoint=${fourPointCandidate?.rejectionReason ?? fourPointEstimate.errorOrNull?.code}, '
              'multiPoint=${multiPointCandidate?.rejectionReason ?? multiPointEstimate?.errorOrNull?.code}).',
          {
            'fourPointEstimateError': fourPointEstimate.errorOrNull?.code,
            'fourPointMaxError': fourPointCandidate?.maxCommonReprojectionError,
            'multiPointEstimateError': multiPointEstimate?.errorOrNull?.code,
            'multiPointMaxError':
                multiPointCandidate?.maxCommonReprojectionError,
            'multiPointInlierRatio': multiPointCandidate?.inlierRatio,
            'fourPointRejectionReason': fourPointCandidate?.rejectionReason,
            'multiPointRejectionReason': multiPointCandidate?.rejectionReason,
          },
        );
      }
      final selectedEstimate =
          selectedMethod == AlignmentHomographyMethod.multiPoint
          ? multiPointEstimate!.value
          : fourPointEstimate.value;
      final selectedCandidate =
          selectedMethod == AlignmentHomographyMethod.multiPoint
          ? multiPointCandidate!
          : fourPointCandidate!;
      final warp = session.warp(
        homography: selectedEstimate.homography,
        outputSize: outputSize,
      );
      if (warp.isFailure) return EngineResult.failure(warp.error);

      stopwatch.stop();
      return EngineResult.success(
        PageAlignmentResult(
          canonicalPage: warp.value.canonicalPage,
          homography: selectedEstimate.homography,
          observations: correspondenceSet.observations,
          correspondences: correspondenceSet.allCornerCorrespondences,
          diagnostics: PageAlignmentDiagnostics(
            expectedMarkerIds: page.markerRegions.map(
              (region) => region.markerId,
            ),
            detectedMarkerIds: session.detection.markers.map(
              (marker) => marker.id,
            ),
            sourceMarkerSideLengths: correspondenceSet.observations.map(
              (observation) => observation.detectedMarker.minimumSideLength,
            ),
            sourceRegistrationPoints: correspondenceSet.baselineSourcePoints,
            destinationRegistrationPoints:
                correspondenceSet.baselineDestinationPoints,
            registrationQuality: correspondenceSet.quality,
            reprojectionErrors: selectedCandidate.commonReprojectionErrors,
            meanReprojectionError:
                selectedCandidate.meanCommonReprojectionError,
            maxReprojectionError: selectedCandidate.maxCommonReprojectionError,
            processingDuration: stopwatch.elapsed,
            sourceSize: session.sourceSize,
            canonicalSize: outputSize,
            decodeDuration: session.openTimings.decode,
            detectionPreparationDuration:
                session.openTimings.detectionPreparation,
            detectionDuration: session.openTimings.detection,
            coordinateRemapDuration: session.openTimings.coordinateRemap,
            pageResolutionDuration: pageResolutionStopwatch.elapsed,
            correspondenceDuration: correspondenceStopwatch.elapsed,
            homographyDuration:
                (fourPointEstimate.valueOrNull?.duration ?? Duration.zero) +
                (multiPointEstimate?.valueOrNull?.duration ?? Duration.zero) +
                (multiPointCrossValidation?.estimationDuration ??
                    Duration.zero),
            warpDuration: warp.value.duration,
            detectionSize: session.openTimings.detectionSize,
            detectionScaleX: session.openTimings.detectionScaleX,
            detectionScaleY: session.openTimings.detectionScaleY,
            selectedHomographyMethod: selectedMethod,
            fourPointCandidate: fourPointCandidate,
            multiPointCandidate: multiPointCandidate,
            fourPointHomographyDuration:
                fourPointEstimate.valueOrNull?.duration ?? Duration.zero,
            multiPointHomographyDuration:
                multiPointEstimate?.valueOrNull?.duration ?? Duration.zero,
            candidateValidationDuration: validationStopwatch.elapsed,
            selectionReason: selection.selectionReason,
            fallbackReason: selection.fallbackReason,
          ),
          detectedMarkers: session.detection.markers,
        ),
      );
    } finally {
      session.dispose();
    }
  }

  HomographyCandidateDiagnostics _evaluateCandidate({
    required BackendHomographyEstimate estimate,
    required AlignmentHomographyMethod method,
    required List<MarkerCorrespondence> fittingCorrespondences,
    required List<MarkerCorrespondence> fullCorrespondences,
    required ReprojectionStatistics? heldOutValidationResiduals,
    String? heldOutValidationUnavailableReason,
    required PageLayout page,
    required ImageSize sourceSize,
    required ArucoAlignmentConfig config,
  }) {
    final fitting = _residualStatistics(
      estimate.homography,
      fittingCorrespondences,
    );
    final full = _residualStatistics(estimate.homography, fullCorrespondences);
    final maskIsValid =
        method == AlignmentHomographyMethod.fourPoint ||
        estimate.inliers.length == fittingCorrespondences.length;
    final inlierCount = method == AlignmentHomographyMethod.fourPoint
        ? fittingCorrespondences.length
        : estimate.inliers.where((value) => value).length;
    final perMarkerInliersAreSafe =
        method == AlignmentHomographyMethod.fourPoint ||
        (maskIsValid && _eachMarkerHasThreeInliers(estimate.inliers));
    final inlierErrorsAreSafe =
        method == AlignmentHomographyMethod.fourPoint ||
        (maskIsValid &&
            [
              for (var index = 0; index < fitting.errors.length; index++)
                if (estimate.inliers[index]) fitting.errors[index],
            ].every((error) => error <= config.maximumReprojectionErrorPixels));
    final stabilityFailure = geometryValidator.validationFailure(
      matrix: estimate.homography,
      page: page,
      sourceSize: sourceSize,
      config: config,
    );
    String? rejectionReason;
    if (!fitting.mean.isFinite || !full.mean.isFinite) {
      rejectionReason = 'NON_FINITE_REPROJECTION';
    } else if (!maskIsValid) {
      rejectionReason = 'INVALID_INLIER_MASK';
    } else if (!perMarkerInliersAreSafe) {
      rejectionReason = 'UNSAFE_INLIER_DISTRIBUTION';
    } else if (!inlierErrorsAreSafe) {
      rejectionReason = 'INLIER_REPROJECTION_EXCEEDED';
    } else if (stabilityFailure != null) {
      rejectionReason = stabilityFailure;
    } else if (method == AlignmentHomographyMethod.fourPoint &&
        full.maximum > config.maximumReprojectionErrorPixels) {
      rejectionReason = 'FULL_CORNER_CONSISTENCY_EXCEEDED';
    } else if (method == AlignmentHomographyMethod.multiPoint &&
        inlierCount / fitting.errors.length <
            config.minimumMultipointInlierRatio) {
      rejectionReason = 'INSUFFICIENT_MULTIPOINT_INLIERS';
    } else if (method == AlignmentHomographyMethod.multiPoint &&
        full.maximum > config.maximumRejectedCornerErrorPixels) {
      rejectionReason = 'REJECTED_CORNER_ERROR_EXCEEDED';
    } else if (heldOutValidationResiduals == null) {
      rejectionReason =
          'HELD_OUT_VALIDATION_UNAVAILABLE${heldOutValidationUnavailableReason == null ? '' : ':$heldOutValidationUnavailableReason'}';
    } else if (heldOutValidationResiduals.maximum >
        (method == AlignmentHomographyMethod.fourPoint
            ? config.maximumReprojectionErrorPixels
            : config.maximumHeldOutReprojectionErrorPixels)) {
      rejectionReason = 'HELD_OUT_REPROJECTION_EXCEEDED';
    }
    final inliersPerMarker = method == AlignmentHomographyMethod.fourPoint
        ? const [1, 1, 1, 1]
        : [
            for (var marker = 0; marker < 4; marker++)
              estimate.inliers
                  .skip(marker * 4)
                  .take(4)
                  .where((value) => value)
                  .length,
          ];
    return HomographyCandidateDiagnostics(
      method: method,
      commonReprojectionErrors: full.errors,
      meanCommonReprojectionError: full.mean,
      medianCommonReprojectionError: full.median,
      maxCommonReprojectionError: full.maximum,
      inlierCount: inlierCount,
      totalPointCount: fittingCorrespondences.length,
      accepted: rejectionReason == null,
      duration: estimate.duration,
      fittingResiduals: fitting,
      heldOutValidationResiduals: heldOutValidationResiduals,
      heldOutValidationMethod: method == AlignmentHomographyMethod.fourPoint
          ? HomographyValidationMethod.unusedFittingCorners
          : HomographyValidationMethod.leaveOneMarkerOut,
      inliersPerMarker: inliersPerMarker,
      rejectionReason: rejectionReason,
    );
  }

  _SelectionDecision _selectMethod(
    HomographyCandidateDiagnostics? fourPoint,
    HomographyCandidateDiagnostics? multiPoint,
    ArucoAlignmentConfig config,
  ) {
    if (multiPoint?.accepted == true && fourPoint?.accepted != true) {
      return const _SelectionDecision(
        method: AlignmentHomographyMethod.multiPoint,
        selectionReason: 'FOUR_POINT_REJECTED_MULTIPOINT_VALIDATED',
        fallbackReason: 'FOUR_POINT_REJECTED',
      );
    }
    if (multiPoint?.accepted == true && fourPoint?.accepted == true) {
      final multiScore = multiPoint!.heldOutValidationScore;
      final fourScore = fourPoint!.heldOutValidationScore;
      if (multiScore != null &&
          fourScore != null &&
          multiScore + config.minimumMultipointScoreImprovementPixels <
              fourScore) {
        return const _SelectionDecision(
          method: AlignmentHomographyMethod.multiPoint,
          selectionReason: 'MULTIPOINT_HELD_OUT_IMPROVEMENT',
        );
      }
      return const _SelectionDecision(
        method: AlignmentHomographyMethod.fourPoint,
        selectionReason: 'BASELINE_PRESERVED_WITHOUT_HELD_OUT_BENEFIT',
        fallbackReason: 'MULTIPOINT_NO_VALIDATED_BENEFIT',
      );
    }
    if (fourPoint?.accepted == true) {
      return _SelectionDecision(
        method: AlignmentHomographyMethod.fourPoint,
        selectionReason: 'FOUR_POINT_ONLY_TRUSTWORTHY_CANDIDATE',
        fallbackReason: multiPoint?.rejectionReason ?? 'MULTIPOINT_UNAVAILABLE',
      );
    }
    return const _SelectionDecision(
      selectionReason: 'NO_TRUSTWORTHY_HOMOGRAPHY',
    );
  }

  List<MarkerCorrespondence> _fourPointHeldOutCorrespondences(
    MarkerCorrespondenceSet set,
  ) => [
    for (final correspondence in set.allCornerCorrespondences)
      if (correspondence.sourceCorner !=
          DetectedRegistrationCorner.forRole(correspondence.role))
        correspondence,
  ];

  ReprojectionStatistics _residualStatistics(
    HomographyMatrix homography,
    List<MarkerCorrespondence> correspondences,
  ) => ReprojectionStatistics([
    for (final correspondence in correspondences)
      _reprojectionError(homography, correspondence),
  ]);

  double _reprojectionError(
    HomographyMatrix homography,
    MarkerCorrespondence correspondence,
  ) {
    try {
      return homography
          .project(correspondence.sourcePoint)
          .distanceTo(correspondence.destinationPoint);
    } on Object {
      return double.infinity;
    }
  }

  _CrossValidationResult _crossValidateMultipoint({
    required ArucoImageSession session,
    required List<MarkerCorrespondence> correspondences,
    required PageLayout page,
    required ArucoAlignmentConfig config,
  }) {
    final errors = <double>[];
    var estimationDuration = Duration.zero;
    final markerIds = correspondences.map((item) => item.markerId).toSet();
    if (markerIds.length != 4) {
      return const _CrossValidationResult(
        unavailableReason: 'EXPECTED_FOUR_MARKERS',
      );
    }
    for (final heldOutMarkerId in markerIds) {
      final training = correspondences
          .where((item) => item.markerId != heldOutMarkerId)
          .toList(growable: false);
      final heldOut = correspondences
          .where((item) => item.markerId == heldOutMarkerId)
          .toList(growable: false);
      if (training.length != 12 || heldOut.length != 4) {
        return const _CrossValidationResult(
          unavailableReason: 'INVALID_MARKER_PARTITION',
        );
      }
      final estimate = session.estimateHomography(
        sourcePoints: training.map((item) => item.sourcePoint).toList(),
        destinationPoints: training
            .map((item) => item.destinationPoint)
            .toList(),
        method: HomographyEstimationMethod.multiPointRansac,
        ransacReprojectionThresholdPixels:
            config.multipointRansacReprojectionThresholdPixels,
        maximumIterations: config.multipointMaximumIterations,
        confidence: config.multipointConfidence,
      );
      if (estimate.isFailure) {
        return _CrossValidationResult(
          unavailableReason: 'ESTIMATION_FAILED_${estimate.error.code}',
          estimationDuration: estimationDuration,
        );
      }
      estimationDuration += estimate.value.duration;
      final stabilityFailure = geometryValidator.validationFailure(
        matrix: estimate.value.homography,
        page: page,
        sourceSize: session.sourceSize,
        config: config,
      );
      if (stabilityFailure != null) {
        return _CrossValidationResult(
          unavailableReason: 'VALIDATION_MODEL_$stabilityFailure',
          estimationDuration: estimationDuration,
        );
      }
      errors.addAll([
        for (final correspondence in heldOut)
          _reprojectionError(estimate.value.homography, correspondence),
      ]);
    }
    return _CrossValidationResult(
      statistics: ReprojectionStatistics(errors),
      estimationDuration: estimationDuration,
    );
  }

  bool _eachMarkerHasThreeInliers(List<bool> inliers) {
    if (inliers.length != 16) return false;
    for (var marker = 0; marker < 4; marker++) {
      var count = 0;
      for (var corner = 0; corner < 4; corner++) {
        if (inliers[marker * 4 + corner]) count++;
      }
      if (count < 3) return false;
    }
    return true;
  }

  EngineResult<PageAlignmentResult> _failure(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );
}

final class _CrossValidationResult {
  const _CrossValidationResult({
    this.statistics,
    this.unavailableReason,
    this.estimationDuration = Duration.zero,
  });

  final ReprojectionStatistics? statistics;
  final String? unavailableReason;
  final Duration estimationDuration;
}

final class _SelectionDecision {
  const _SelectionDecision({
    this.method,
    required this.selectionReason,
    this.fallbackReason,
  });

  final AlignmentHomographyMethod? method;
  final String selectionReason;
  final String? fallbackReason;
}
