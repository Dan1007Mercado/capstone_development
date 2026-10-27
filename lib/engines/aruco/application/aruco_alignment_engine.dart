import 'dart:math' as math;
import 'dart:typed_data';

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../layout/domain/page_layout.dart';
import '../domain/alignment_failure_diagnostics.dart';
import '../domain/aruco_alignment_config.dart';
import '../domain/aruco_vision_backend.dart';
import '../domain/detected_marker.dart';
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
      var effectiveDetection = session.detection;
      var split = roleSplitter.split(effectiveDetection.markers, expectedIds);
      var registrationIds = split.registrationMarkers
          .map((marker) => marker.id)
          .toList(growable: false);
      if (registrationIds.toSet().length != registrationIds.length) {
        final resolved = _resolveSingleDuplicate(
          session: session,
          detection: effectiveDetection,
          page: page,
          config: effectiveConfig,
        );
        if (resolved.isFailure) return EngineResult.failure(resolved.error);
        effectiveDetection = resolved.value;
        split = roleSplitter.split(effectiveDetection.markers, expectedIds);
        registrationIds = split.registrationMarkers
            .map((marker) => marker.id)
            .toList(growable: false);
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
        detection: effectiveDetection,
        page: page,
        config: effectiveConfig,
      );
      correspondenceStopwatch.stop();
      if (correspondenceResult.isFailure) {
        return EngineResult.failure(correspondenceResult.error);
      }
      final correspondenceSet = correspondenceResult.value;
      final reprojectionScaleFactor = _reprojectionScaleFactor(
        page,
        correspondenceSet,
        effectiveConfig,
        detectionScaleX: session.openTimings.detectionScaleX,
        detectionScaleY: session.openTimings.detectionScaleY,
      );
      final effectiveReprojectionError =
          effectiveConfig.maximumReprojectionErrorPixels *
          reprojectionScaleFactor;
      final effectiveRansacThreshold = math.min(
        effectiveConfig.maximumRejectedCornerErrorPixels *
            reprojectionScaleFactor,
        effectiveConfig.multipointRansacReprojectionThresholdPixels *
            reprojectionScaleFactor,
      );
      final effectiveRejectedCornerError =
          effectiveConfig.maximumRejectedCornerErrorPixels *
          reprojectionScaleFactor;
      final outputSize = ImageSize(
        width: page.canonicalPageSpec.widthPixels,
        height: page.canonicalPageSpec.heightPixels,
      );
      final fourPointEstimate = session.estimateHomography(
        sourcePoints: correspondenceSet.baselineSourcePoints,
        destinationPoints: correspondenceSet.baselineDestinationPoints,
        method: HomographyEstimationMethod.fourPoint,
        ransacReprojectionThresholdPixels: effectiveRansacThreshold,
        maximumIterations: effectiveConfig.multipointMaximumIterations,
        confidence: effectiveConfig.multipointConfidence,
      );
      final validationStopwatch = Stopwatch()..start();
      var fourPointValidationDuration = Duration.zero;
      HomographyCandidateDiagnostics? fourPointCandidate;
      if (fourPointEstimate.isSuccess) {
        final candidateStopwatch = Stopwatch()..start();
        fourPointCandidate = _evaluateCandidate(
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
          effectiveReprojectionErrorPixels: effectiveReprojectionError,
          effectiveInlierReprojectionErrorPixels: effectiveRansacThreshold,
          effectiveRejectedCornerErrorPixels: effectiveRejectedCornerError,
        );
        candidateStopwatch.stop();
        fourPointValidationDuration = candidateStopwatch.elapsed;
      }

      EngineResult<BackendHomographyEstimate>? multiPointEstimate;
      HomographyCandidateDiagnostics? multiPointCandidate;
      var multiPointValidationDuration = Duration.zero;
      // A safe baseline wins under this policy regardless of the multi-point
      // residuals. Fit the optional candidate only when it can affect selection.
      if (effectiveConfig.enableMultipointHomography &&
          (fourPointCandidate?.accepted != true ||
              effectiveConfig.selectionPolicy ==
                  HomographySelectionPolicy.validatedMultiPointPreference)) {
        multiPointEstimate = session.estimateHomography(
          sourcePoints: correspondenceSet.allSourcePoints,
          destinationPoints: correspondenceSet.allDestinationPoints,
          method: HomographyEstimationMethod.multiPointRansac,
          ransacReprojectionThresholdPixels: effectiveRansacThreshold,
          maximumIterations: effectiveConfig.multipointMaximumIterations,
          confidence: effectiveConfig.multipointConfidence,
        );
        if (multiPointEstimate.isSuccess) {
          final candidateStopwatch = Stopwatch()..start();
          multiPointCandidate = _evaluateCandidate(
            estimate: multiPointEstimate.value,
            method: AlignmentHomographyMethod.multiPoint,
            fittingCorrespondences: correspondenceSet.allCornerCorrespondences,
            fullCorrespondences: correspondenceSet.allCornerCorrespondences,
            heldOutValidationResiduals: null,
            heldOutValidationMethod: null,
            page: page,
            sourceSize: session.sourceSize,
            config: effectiveConfig,
            effectiveReprojectionErrorPixels: effectiveReprojectionError,
            effectiveInlierReprojectionErrorPixels: effectiveRansacThreshold,
            effectiveRejectedCornerErrorPixels: effectiveRejectedCornerError,
          );
          candidateStopwatch.stop();
          multiPointValidationDuration = candidateStopwatch.elapsed;
        }
      }
      validationStopwatch.stop();

      final selection = _selectMethod(
        fourPointCandidate,
        multiPointCandidate,
        effectiveConfig.selectionPolicy,
      );
      final selectedMethod = selection.method;
      if (selectedMethod == null) {
        final failureDiagnostics = AlignmentFailureDiagnostics(
          sourceSize: session.sourceSize,
          detectionSize: session.openTimings.detectionSize,
          detectionScaleX: session.openTimings.detectionScaleX,
          detectionScaleY: session.openTimings.detectionScaleY,
          expectedMarkerIds: expectedIds.toList()..sort(),
          detectedRegistrationMarkerIds: registrationIds,
          markerSideLengths: [
            for (final observation in correspondenceSet.observations)
              {
                'id': observation.detectedMarker.id,
                'minimum': observation.detectedMarker.minimumSideLength,
                'sides': observation.detectedMarker.sideLengths,
              },
          ],
          detectedCorners: _correspondencePoints(
            correspondenceSet.allCornerCorrespondences,
            source: true,
          ),
          expectedCorners: _correspondencePoints(
            correspondenceSet.allCornerCorrespondences,
            source: false,
          ),
          selectionPolicy: effectiveConfig.selectionPolicy,
          selectionReason: selection.selectionReason,
          fourPoint: _attemptDiagnostics(
            method: AlignmentHomographyMethod.fourPoint,
            estimate: fourPointEstimate,
            candidate: fourPointCandidate,
            validationDuration: fourPointValidationDuration,
            effectiveReprojectionError: effectiveReprojectionError,
            effectiveRansacThreshold: effectiveRansacThreshold,
            effectiveRejectedCornerError: effectiveRejectedCornerError,
          ),
          multiPoint: _attemptDiagnostics(
            method: AlignmentHomographyMethod.multiPoint,
            estimate: multiPointEstimate,
            candidate: multiPointCandidate,
            validationDuration: multiPointValidationDuration,
            effectiveReprojectionError: effectiveReprojectionError,
            effectiveRansacThreshold: effectiveRansacThreshold,
            effectiveRejectedCornerError: effectiveRejectedCornerError,
          ),
          decodeDuration: session.openTimings.decode,
          detectionPreparationDuration:
              session.openTimings.detectionPreparation,
          detectionDuration: session.openTimings.detection,
          coordinateRemapDuration: session.openTimings.coordinateRemap,
          pageResolutionDuration: pageResolutionStopwatch.elapsed,
          correspondenceDuration: correspondenceStopwatch.elapsed,
          totalDuration: stopwatch.elapsed,
        );
        return _failure(
          'ARUCO_REPROJECTION_FAILED',
          'Neither homography candidate passed alignment validation '
              '(fourPoint=${fourPointCandidate?.rejectionReason ?? fourPointEstimate.errorOrNull?.code}, '
              'multiPoint=${multiPointCandidate?.rejectionReason ?? multiPointEstimate?.errorOrNull?.code}).',
          {
            AlignmentFailureDiagnostics.detailsKey: failureDiagnostics.toMap(),
            'sourceSize': _sizeDetails(session.sourceSize),
            'detectionSize': _sizeDetails(session.openTimings.detectionSize),
            'detectionScaleX': session.openTimings.detectionScaleX,
            'detectionScaleY': session.openTimings.detectionScaleY,
            'detectedRegistrationIds': registrationIds,
            'sourceMarkerSideLengths': [
              for (final observation in correspondenceSet.observations)
                {
                  'id': observation.detectedMarker.id,
                  'minimum': observation.detectedMarker.minimumSideLength,
                  'sides': observation.detectedMarker.sideLengths,
                },
            ],
            'detectedCorners': _correspondencePoints(
              correspondenceSet.allCornerCorrespondences,
              source: true,
            ),
            'expectedCorners': _correspondencePoints(
              correspondenceSet.allCornerCorrespondences,
              source: false,
            ),
            'fourPointResiduals': fourPointCandidate?.commonReprojectionErrors,
            'fourPointInlierMask': fourPointCandidate?.inlierMask,
            'fourPointInliersPerMarker': fourPointCandidate?.inliersPerMarker,
            'multiPointResiduals':
                multiPointCandidate?.commonReprojectionErrors,
            'multiPointInlierMask': multiPointCandidate?.inlierMask,
            'multiPointInliersPerMarker': multiPointCandidate?.inliersPerMarker,
            'effectiveRansacThreshold': effectiveRansacThreshold,
            'effectiveFourPointConsistencyThreshold':
                effectiveReprojectionError,
            'effectiveRejectedCornerThreshold': effectiveRejectedCornerError,
            'reprojectionScaleFactor': reprojectionScaleFactor,
            'fourPointEstimateError': fourPointEstimate.errorOrNull?.code,
            'fourPointMaxError': fourPointCandidate?.maxCommonReprojectionError,
            'multiPointEstimateError': multiPointEstimate?.errorOrNull?.code,
            'multiPointMaxError':
                multiPointCandidate?.maxCommonReprojectionError,
            'multiPointInlierRatio': multiPointCandidate?.inlierRatio,
            'fourPointRejectionReason': fourPointCandidate?.rejectionReason,
            'multiPointRejectionReason': multiPointCandidate?.rejectionReason,
            'fourPointNumericalValidation': fourPointCandidate == null
                ? fourPointEstimate.errorOrNull?.code ?? 'notRun'
                : _numericalValidationResult(fourPointCandidate),
            'multiPointNumericalValidation':
                !effectiveConfig.enableMultipointHomography
                ? 'notRun'
                : multiPointCandidate == null
                ? multiPointEstimate?.errorOrNull?.code ?? 'notRun'
                : _numericalValidationResult(multiPointCandidate),
            'fourPointGeometryValidation': fourPointCandidate == null
                ? 'notRun'
                : fourPointCandidate.geometryValidationFailure ?? 'passed',
            'multiPointGeometryValidation': multiPointCandidate == null
                ? 'notRun'
                : multiPointCandidate.geometryValidationFailure ?? 'passed',
            'stageTimingsMs': {
              'decode': _milliseconds(session.openTimings.decode),
              'detectionPreparation': _milliseconds(
                session.openTimings.detectionPreparation,
              ),
              'detection': _milliseconds(session.openTimings.detection),
              'coordinateRemap': _milliseconds(
                session.openTimings.coordinateRemap,
              ),
              'pageResolution': _milliseconds(pageResolutionStopwatch.elapsed),
              'correspondence': _milliseconds(correspondenceStopwatch.elapsed),
              'fourPointHomography': _milliseconds(
                fourPointEstimate.valueOrNull?.duration ?? Duration.zero,
              ),
              'multiPointHomography': _milliseconds(
                multiPointEstimate?.valueOrNull?.duration ?? Duration.zero,
              ),
              'candidateValidation': _milliseconds(validationStopwatch.elapsed),
              'alignmentElapsed': _milliseconds(stopwatch.elapsed),
            },
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
            detectedMarkerIds: effectiveDetection.markers.map(
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
                (multiPointEstimate?.valueOrNull?.duration ?? Duration.zero),
            warpDuration: warp.value.duration,
            detectionSize: session.openTimings.detectionSize,
            detectionScaleX: session.openTimings.detectionScaleX,
            detectionScaleY: session.openTimings.detectionScaleY,
            selectedHomographyMethod: selectedMethod,
            selectionPolicy: effectiveConfig.selectionPolicy,
            fourPointCandidate: fourPointCandidate,
            multiPointCandidate: multiPointCandidate,
            fourPointHomographyDuration:
                fourPointEstimate.valueOrNull?.duration ?? Duration.zero,
            multiPointHomographyDuration:
                multiPointEstimate?.valueOrNull?.duration ?? Duration.zero,
            candidateValidationDuration: validationStopwatch.elapsed,
            reprojectionScaleFactor: reprojectionScaleFactor,
            effectiveReprojectionErrorPixels: effectiveReprojectionError,
            effectiveRansacReprojectionThresholdPixels:
                effectiveRansacThreshold,
            effectiveRejectedCornerErrorPixels: effectiveRejectedCornerError,
            selectionReason: selection.selectionReason,
            fallbackReason: selection.fallbackReason,
            fourPointEstimationFailureCode: fourPointEstimate.errorOrNull?.code,
            multiPointEstimationFailureCode:
                multiPointEstimate?.errorOrNull?.code,
          ),
          detectedMarkers: effectiveDetection.markers,
        ),
      );
    } finally {
      session.dispose();
    }
  }

  /// Resolves only the narrow case where one required ID has two detections
  /// and exactly one complete interpretation passes the normal four-point
  /// candidate checks. Any other duplicate pattern remains an ambiguity.
  EngineResult<ArucoDetection> _resolveSingleDuplicate({
    required ArucoImageSession session,
    required ArucoDetection detection,
    required PageLayout page,
    required ArucoAlignmentConfig config,
  }) {
    final expectedIds = page.markerRegions
        .map((region) => region.markerId)
        .toSet();
    final byId = <int, List<DetectedMarker>>{};
    for (final marker in detection.markers) {
      if (expectedIds.contains(marker.id)) {
        byId.putIfAbsent(marker.id, () => []).add(marker);
      }
    }
    final duplicated = byId.entries
        .where((entry) => entry.value.length > 1)
        .toList(growable: false);
    final complete = expectedIds.every((id) => byId[id]?.isNotEmpty == true);
    if (!complete ||
        duplicated.length != 1 ||
        duplicated.single.value.length != 2 ||
        byId.entries.any(
          (entry) =>
              entry.key != duplicated.single.key && entry.value.length != 1,
        )) {
      return EngineResult.failure(
        EngineError(
          code: 'SCAN_DUPLICATE_PAGE_MARKERS',
          message: 'A page marker ID was detected more than once.',
          details: {
            'detectedMarkerIds': detection.markers
                .map((marker) => marker.id)
                .toList(),
          },
        ),
      );
    }
    final duplicateId = duplicated.single.key;
    final accepted = <ArucoDetection>[];
    final rejectionReasons = <String>[];
    for (final candidateMarker in duplicated.single.value) {
      final candidateDetection = ArucoDetection(
        sourceSize: detection.sourceSize,
        markers: [
          for (final marker in detection.markers)
            if (marker.id != duplicateId || identical(marker, candidateMarker))
              marker,
        ],
      );
      final correspondence = correspondenceService.build(
        detection: candidateDetection,
        page: page,
        config: config,
      );
      if (correspondence.isFailure) {
        rejectionReasons.add(correspondence.error.code);
        continue;
      }
      final set = correspondence.value;
      final scale = _reprojectionScaleFactor(
        page,
        set,
        config,
        detectionScaleX: session.openTimings.detectionScaleX,
        detectionScaleY: session.openTimings.detectionScaleY,
      );
      final fittingThreshold = config.maximumReprojectionErrorPixels * scale;
      final ransacThreshold = math.min(
        config.maximumRejectedCornerErrorPixels * scale,
        config.multipointRansacReprojectionThresholdPixels * scale,
      );
      final rejectedCornerThreshold =
          config.maximumRejectedCornerErrorPixels * scale;
      final estimate = session.estimateHomography(
        sourcePoints: set.baselineSourcePoints,
        destinationPoints: set.baselineDestinationPoints,
        method: HomographyEstimationMethod.fourPoint,
        ransacReprojectionThresholdPixels: ransacThreshold,
        maximumIterations: config.multipointMaximumIterations,
        confidence: config.multipointConfidence,
      );
      if (estimate.isFailure) {
        rejectionReasons.add(estimate.error.code);
        continue;
      }
      final evaluated = _evaluateCandidate(
        estimate: estimate.value,
        method: AlignmentHomographyMethod.fourPoint,
        fittingCorrespondences: set.baselineCorrespondences,
        fullCorrespondences: set.allCornerCorrespondences,
        heldOutValidationResiduals: _residualStatistics(
          estimate.value.homography,
          _fourPointHeldOutCorrespondences(set),
        ),
        page: page,
        sourceSize: session.sourceSize,
        config: config,
        effectiveReprojectionErrorPixels: fittingThreshold,
        effectiveInlierReprojectionErrorPixels: ransacThreshold,
        effectiveRejectedCornerErrorPixels: rejectedCornerThreshold,
      );
      if (evaluated.accepted) {
        accepted.add(candidateDetection);
        rejectionReasons.add('accepted');
      } else {
        rejectionReasons.add(evaluated.rejectionReason ?? 'unsafe');
      }
    }
    if (accepted.length == 1) return EngineResult.success(accepted.single);
    return EngineResult.failure(
      EngineError(
        code: 'SCAN_DUPLICATE_PAGE_MARKERS',
        message:
            'A duplicated page marker did not have exactly one valid interpretation.',
        details: {
          'duplicateMarkerId': duplicateId,
          'validInterpretations': accepted.length,
          'candidateResults': rejectionReasons,
        },
      ),
    );
  }

  HomographyCandidateDiagnostics _evaluateCandidate({
    required BackendHomographyEstimate estimate,
    required AlignmentHomographyMethod method,
    required List<MarkerCorrespondence> fittingCorrespondences,
    required List<MarkerCorrespondence> fullCorrespondences,
    required ReprojectionStatistics? heldOutValidationResiduals,
    HomographyValidationMethod? heldOutValidationMethod =
        HomographyValidationMethod.unusedFittingCorners,
    required PageLayout page,
    required ImageSize sourceSize,
    required ArucoAlignmentConfig config,
    required double effectiveReprojectionErrorPixels,
    required double effectiveInlierReprojectionErrorPixels,
    required double effectiveRejectedCornerErrorPixels,
  }) {
    final fitting = _residualStatistics(
      estimate.homography,
      fittingCorrespondences,
    );
    final full = _residualStatistics(estimate.homography, fullCorrespondences);
    final estimatorMaskIsValid =
        estimate.inliers.length == fittingCorrespondences.length;
    final validationInliers = method == AlignmentHomographyMethod.fourPoint
        ? [
            for (final error in full.errors)
              error <= effectiveReprojectionErrorPixels,
          ]
        : estimate.inliers;
    final maskIsValid =
        estimatorMaskIsValid &&
        validationInliers.length == fullCorrespondences.length;
    final inlierCount = validationInliers.where((value) => value).length;
    final inliersPerMarker = maskIsValid
        ? _inliersPerMarker(fullCorrespondences, validationInliers)
        : const <int>[];
    final perMarkerInliersAreSafe =
        maskIsValid && inliersPerMarker.every((count) => count >= 3);
    final fittingErrorsAreSafe =
        fitting.errors.isNotEmpty &&
        fitting.errors.every((error) => error.isFinite) &&
        fitting.maximum <= effectiveReprojectionErrorPixels;
    final inlierErrorsAreSafe =
        method == AlignmentHomographyMethod.fourPoint ||
        (maskIsValid &&
            [
              for (var index = 0; index < fitting.errors.length; index++)
                if (validationInliers[index]) fitting.errors[index],
            ].every(
              (error) => error <= effectiveInlierReprojectionErrorPixels,
            ));
    final stabilityFailure = geometryValidator.validationFailure(
      matrix: estimate.homography,
      page: page,
      sourceSize: sourceSize,
      config: config,
    );
    final maximumErrorIsSafe =
        full.maximum <= effectiveRejectedCornerErrorPixels;
    final strictInlierRatioIsSafe =
        inlierCount / full.errors.length >= config.minimumMultipointInlierRatio;
    final fourPointIsReliable =
        method == AlignmentHomographyMethod.fourPoint &&
        estimatorMaskIsValid &&
        fittingErrorsAreSafe &&
        stabilityFailure == null;
    final multiPointIsReliable =
        method == AlignmentHomographyMethod.multiPoint &&
        maskIsValid &&
        inlierErrorsAreSafe &&
        stabilityFailure == null &&
        maximumErrorIsSafe &&
        perMarkerInliersAreSafe &&
        strictInlierRatioIsSafe;
    final reliable = fourPointIsReliable || multiPointIsReliable;
    final localizedUncertaintyIsAcceptable =
        !reliable &&
        maskIsValid &&
        inlierErrorsAreSafe &&
        stabilityFailure == null &&
        maximumErrorIsSafe &&
        method == AlignmentHomographyMethod.multiPoint &&
        _hasSpatiallyDistributedLocalizedSupport(
          fullCorrespondences,
          validationInliers,
          inliersPerMarker,
        ) &&
        full.median <= effectiveReprojectionErrorPixels &&
        full.mean <= effectiveInlierReprojectionErrorPixels;
    final acceptance = reliable
        ? HomographyCandidateAcceptance.reliable
        : localizedUncertaintyIsAcceptable
        ? HomographyCandidateAcceptance.acceptableWithLocalizedUncertainty
        : HomographyCandidateAcceptance.unsafe;
    String? rejectionReason;
    if (!fitting.mean.isFinite ||
        (method == AlignmentHomographyMethod.multiPoint &&
            !full.mean.isFinite)) {
      rejectionReason = 'NON_FINITE_REPROJECTION';
    } else if (!estimatorMaskIsValid ||
        (method == AlignmentHomographyMethod.multiPoint && !maskIsValid)) {
      rejectionReason = 'INVALID_INLIER_MASK';
    } else if (stabilityFailure != null) {
      rejectionReason = stabilityFailure;
    } else if (method == AlignmentHomographyMethod.fourPoint &&
        !fittingErrorsAreSafe) {
      rejectionReason = 'FITTING_REPROJECTION_EXCEEDED';
    } else if (method == AlignmentHomographyMethod.multiPoint &&
        !inlierErrorsAreSafe) {
      rejectionReason = 'INLIER_REPROJECTION_EXCEEDED';
    } else if (method == AlignmentHomographyMethod.multiPoint &&
        full.maximum > effectiveRejectedCornerErrorPixels) {
      rejectionReason = 'REJECTED_CORNER_ERROR_EXCEEDED';
    } else if (method == AlignmentHomographyMethod.fourPoint) {
      rejectionReason = null;
    } else if (localizedUncertaintyIsAcceptable) {
      rejectionReason = null;
    } else if (method == AlignmentHomographyMethod.multiPoint &&
        !perMarkerInliersAreSafe) {
      rejectionReason = 'UNSAFE_INLIER_DISTRIBUTION';
    } else if (method == AlignmentHomographyMethod.multiPoint &&
        inlierCount / fitting.errors.length <
            config.minimumMultipointInlierRatio) {
      rejectionReason = 'INSUFFICIENT_MULTIPOINT_INLIERS';
    }
    return HomographyCandidateDiagnostics(
      method: method,
      commonReprojectionErrors: full.errors,
      meanCommonReprojectionError: full.mean,
      medianCommonReprojectionError: full.median,
      maxCommonReprojectionError: full.maximum,
      inlierCount: inlierCount,
      totalPointCount: fullCorrespondences.length,
      accepted: rejectionReason == null,
      acceptance: acceptance,
      duration: estimate.duration,
      homography: estimate.homography,
      fittingResiduals: fitting,
      heldOutValidationResiduals: heldOutValidationResiduals,
      heldOutValidationMethod: heldOutValidationMethod,
      inliersPerMarker: inliersPerMarker,
      inlierMask: validationInliers,
      geometryValidationFailure: stabilityFailure,
      rejectionReason: rejectionReason,
    );
  }

  _SelectionDecision _selectMethod(
    HomographyCandidateDiagnostics? fourPoint,
    HomographyCandidateDiagnostics? multiPoint,
    HomographySelectionPolicy policy,
  ) {
    if (fourPoint?.accepted == true && multiPoint?.accepted == true) {
      if (policy == HomographySelectionPolicy.fourPointBaseline) {
        return const _SelectionDecision(
          method: AlignmentHomographyMethod.fourPoint,
          selectionReason: 'FOUR_POINT_VALIDATED_BASELINE',
          fallbackReason: 'MULTIPOINT_RESERVED_FOR_UNSAFE_BASELINE',
        );
      }
      if (policy == HomographySelectionPolicy.validatedMultiPointPreference &&
          multiPoint!.acceptance == HomographyCandidateAcceptance.reliable) {
        return const _SelectionDecision(
          method: AlignmentHomographyMethod.multiPoint,
          selectionReason: 'EXTERNALLY_VALIDATED_MULTIPOINT_PREFERENCE',
        );
      }
      return const _SelectionDecision(
        method: AlignmentHomographyMethod.fourPoint,
        selectionReason: 'FOUR_POINT_STRONGER_VALIDATED_CANDIDATE',
        fallbackReason: 'MULTIPOINT_NOT_DEMONSTRABLY_MORE_ACCURATE',
      );
    }
    if (fourPoint?.accepted == true) {
      return _SelectionDecision(
        method: AlignmentHomographyMethod.fourPoint,
        selectionReason: 'FOUR_POINT_VALIDATED_BASELINE',
        fallbackReason: multiPoint?.rejectionReason,
      );
    }
    if (multiPoint?.accepted == true) {
      return _SelectionDecision(
        method: AlignmentHomographyMethod.multiPoint,
        selectionReason: 'FOUR_POINT_REJECTED_MULTIPOINT_VALIDATED',
        fallbackReason: fourPoint?.rejectionReason ?? 'FOUR_POINT_UNAVAILABLE',
      );
    }
    return const _SelectionDecision(
      selectionReason: 'NO_TRUSTWORTHY_HOMOGRAPHY',
    );
  }

  bool _hasSpatiallyDistributedLocalizedSupport(
    List<MarkerCorrespondence> correspondences,
    List<bool> inliers,
    List<int> inliersPerMarker,
  ) {
    if (inliersPerMarker.length != 4 ||
        correspondences.length != inliers.length) {
      return false;
    }
    final cornerCount = MarkerCorner.values.length;
    final localizedMinimum = cornerCount ~/ 2;
    final reliableMinimum = cornerCount - 1;
    final minimumDistributedInliers =
        localizedMinimum * inliersPerMarker.length +
        (reliableMinimum - localizedMinimum) * (inliersPerMarker.length - 1);
    final supported = [
      for (var index = 0; index < correspondences.length; index++)
        if (inliers[index]) correspondences[index],
    ];
    if (inliersPerMarker.any((count) => count < localizedMinimum) ||
        supported.length < minimumDistributedInliers) {
      return false;
    }

    return _hasProportionalHullCoverage(
          allPoints: [
            for (final correspondence in correspondences)
              correspondence.sourcePoint,
          ],
          supportedPoints: [
            for (final correspondence in supported) correspondence.sourcePoint,
          ],
        ) &&
        _hasProportionalHullCoverage(
          allPoints: [
            for (final correspondence in correspondences)
              correspondence.destinationPoint,
          ],
          supportedPoints: [
            for (final correspondence in supported)
              correspondence.destinationPoint,
          ],
        );
  }

  bool _hasProportionalHullCoverage({
    required List<ImagePoint> allPoints,
    required List<ImagePoint> supportedPoints,
  }) {
    final allArea = _convexHullArea(allPoints);
    final supportedArea = _convexHullArea(supportedPoints);
    if (!allArea.isFinite ||
        !supportedArea.isFinite ||
        allArea <= 0 ||
        supportedArea <= 0) {
      return false;
    }
    return supportedArea / allArea >= supportedPoints.length / allPoints.length;
  }

  double _convexHullArea(List<ImagePoint> points) {
    if (points.length < 3) return 0;
    final sorted = List<ImagePoint>.of(points)
      ..sort((first, second) {
        final xComparison = first.x.compareTo(second.x);
        return xComparison != 0 ? xComparison : first.y.compareTo(second.y);
      });
    final lower = <ImagePoint>[];
    for (final point in sorted) {
      while (lower.length >= 2 &&
          _cross(lower[lower.length - 2], lower.last, point) <= 0) {
        lower.removeLast();
      }
      lower.add(point);
    }
    final upper = <ImagePoint>[];
    for (final point in sorted.reversed) {
      while (upper.length >= 2 &&
          _cross(upper[upper.length - 2], upper.last, point) <= 0) {
        upper.removeLast();
      }
      upper.add(point);
    }
    final hull = [
      ...lower.take(lower.length - 1),
      ...upper.take(upper.length - 1),
    ];
    if (hull.length < 3) return 0;
    var twiceArea = 0.0;
    for (var index = 0; index < hull.length; index++) {
      final current = hull[index];
      final next = hull[(index + 1) % hull.length];
      twiceArea += current.x * next.y - next.x * current.y;
    }
    return twiceArea.abs() / 2;
  }

  double _cross(ImagePoint origin, ImagePoint first, ImagePoint second) =>
      (first.x - origin.x) * (second.y - origin.y) -
      (first.y - origin.y) * (second.x - origin.x);

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

  List<int> _inliersPerMarker(
    List<MarkerCorrespondence> correspondences,
    List<bool> inliers,
  ) {
    final counts = <int, int>{};
    for (var index = 0; index < correspondences.length; index++) {
      final markerId = correspondences[index].markerId;
      counts.putIfAbsent(markerId, () => 0);
      if (inliers[index]) counts[markerId] = counts[markerId]! + 1;
    }
    return counts.values.toList(growable: false);
  }

  double _reprojectionScaleFactor(
    PageLayout page,
    MarkerCorrespondenceSet correspondences,
    ArucoAlignmentConfig config, {
    required double detectionScaleX,
    required double detectionScaleY,
  }) {
    final canonicalWidth = page.canonicalPageSpec.widthPixels.toDouble();
    final canonicalHeight = page.canonicalPageSpec.heightPixels.toDouble();
    final scaleFactors = [
      for (final observation in correspondences.observations)
        math.max(
              observation.expectedRegion.normalizedMarkerBounds.width.value *
                  canonicalWidth,
              observation.expectedRegion.normalizedMarkerBounds.height.value *
                  canonicalHeight,
            ) /
            _minimumDetectionMarkerSide(
              observation.detectedMarker,
              detectionScaleX,
              detectionScaleY,
            ),
    ];
    return scaleFactors
        .reduce(math.max)
        .clamp(1.0, config.maximumLocalizationScaleFactor);
  }

  double _minimumDetectionMarkerSide(
    DetectedMarker marker,
    double detectionScaleX,
    double detectionScaleY,
  ) {
    final detectionCorners = [
      for (final corner in marker.corners)
        ImagePoint(corner.x / detectionScaleX, corner.y / detectionScaleY),
    ];
    return [
      for (var index = 0; index < detectionCorners.length; index++)
        detectionCorners[index].distanceTo(
          detectionCorners[(index + 1) % detectionCorners.length],
        ),
    ].reduce(math.min);
  }

  List<Map<String, Object>> _correspondencePoints(
    List<MarkerCorrespondence> correspondences, {
    required bool source,
  }) => [
    for (final correspondence in correspondences)
      {
        'id': correspondence.markerId,
        'corner': correspondence.sourceCorner.name,
        'x': source
            ? correspondence.sourcePoint.x
            : correspondence.destinationPoint.x,
        'y': source
            ? correspondence.sourcePoint.y
            : correspondence.destinationPoint.y,
      },
  ];

  Map<String, int>? _sizeDetails(ImageSize? size) =>
      size == null ? null : {'width': size.width, 'height': size.height};

  HomographyAttemptDiagnostics _attemptDiagnostics({
    required AlignmentHomographyMethod method,
    required EngineResult<BackendHomographyEstimate>? estimate,
    required HomographyCandidateDiagnostics? candidate,
    required Duration validationDuration,
    required double effectiveReprojectionError,
    required double effectiveRansacThreshold,
    required double effectiveRejectedCornerError,
  }) {
    final succeeded = estimate?.isSuccess == true;
    return HomographyAttemptDiagnostics(
      method: method,
      estimationStatus: succeeded
          ? HomographyEstimationStatus.succeeded
          : HomographyEstimationStatus.failed,
      validationStatus: !succeeded
          ? HomographyValidationStatus.notRun
          : candidate?.accepted == true
          ? HomographyValidationStatus.accepted
          : HomographyValidationStatus.rejected,
      estimationFailureCode:
          estimate?.errorOrNull?.code ??
          (estimate == null ? 'ESTIMATOR_DISABLED' : null),
      estimationFailureMessage: estimate?.errorOrNull?.message,
      homography: estimate?.valueOrNull?.homography,
      rejectionReason: candidate?.rejectionReason,
      meanResidual: candidate?.meanCommonReprojectionError,
      medianResidual: candidate?.medianCommonReprojectionError,
      percentile95Residual: candidate == null
          ? null
          : ReprojectionStatistics(
              candidate.commonReprojectionErrors,
            ).percentile95,
      maximumResidual: candidate?.maxCommonReprojectionError,
      cornerResiduals: candidate?.commonReprojectionErrors ?? const [],
      inlierMask: candidate?.inlierMask ?? const [],
      inlierCount: candidate?.inlierCount ?? 0,
      inliersPerMarker: candidate?.inliersPerMarker ?? const [],
      geometryValidationResult:
          candidate?.geometryValidationFailure ??
          (succeeded ? 'passed' : 'notRun'),
      numericalValidationResult: candidate == null
          ? succeeded
                ? 'unavailable'
                : 'notRun'
          : _numericalValidationResult(candidate),
      effectiveReprojectionThresholdPixels: effectiveReprojectionError,
      effectiveRansacThresholdPixels: effectiveRansacThreshold,
      effectiveRejectedCornerThresholdPixels: effectiveRejectedCornerError,
      estimationDuration: estimate?.valueOrNull?.duration ?? Duration.zero,
      validationDuration: validationDuration,
    );
  }

  double _milliseconds(Duration duration) =>
      duration.inMicroseconds / Duration.microsecondsPerMillisecond;

  String _numericalValidationResult(HomographyCandidateDiagnostics candidate) =>
      switch (candidate.rejectionReason) {
        'NON_FINITE_REPROJECTION' ||
        'INVALID_INLIER_MASK' => candidate.rejectionReason!,
        _ => 'passed',
      };

  EngineResult<PageAlignmentResult> _failure(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );
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
