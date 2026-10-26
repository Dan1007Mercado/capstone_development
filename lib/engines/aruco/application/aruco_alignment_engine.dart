import 'dart:math' as math;
import 'dart:typed_data';

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../layout/domain/page_layout.dart';
import '../domain/aruco_alignment_config.dart';
import '../domain/aruco_vision_backend.dart';
import '../domain/image_geometry.dart';
import '../domain/marker_correspondence.dart';
import '../domain/page_alignment_result.dart';
import 'marker_correspondence_service.dart';
import 'marker_role_splitter.dart';

final class ArucoAlignmentEngine {
  const ArucoAlignmentEngine({
    required this.backend,
    this.correspondenceService = const MarkerCorrespondenceService(),
    this.roleSplitter = const MarkerRoleSplitter(),
    this.config,
  });

  final ArucoVisionBackend backend;
  final MarkerCorrespondenceService correspondenceService;
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
      final fourPointCandidate = fourPointEstimate.isSuccess
          ? _evaluateCandidate(
              estimate: fourPointEstimate.value,
              method: AlignmentHomographyMethod.fourPoint,
              correspondences: correspondenceSet.allCornerCorrespondences,
              config: effectiveConfig,
            )
          : null;

      EngineResult<BackendHomographyEstimate>? multiPointEstimate;
      HomographyCandidateDiagnostics? multiPointCandidate;
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
          multiPointCandidate = _evaluateCandidate(
            estimate: multiPointEstimate.value,
            method: AlignmentHomographyMethod.multiPoint,
            correspondences: correspondenceSet.allCornerCorrespondences,
            config: effectiveConfig,
          );
        }
      }

      final selectedMethod = _selectMethod(
        fourPointCandidate,
        multiPointCandidate,
        effectiveConfig,
      );
      if (selectedMethod == null) {
        return _failure(
          'ARUCO_REPROJECTION_FAILED',
          'Neither homography candidate passed common marker-corner validation.',
          {
            'fourPointEstimateError': fourPointEstimate.errorOrNull?.code,
            'fourPointMaxError': fourPointCandidate?.maxCommonReprojectionError,
            'multiPointEstimateError': multiPointEstimate?.errorOrNull?.code,
            'multiPointMaxError':
                multiPointCandidate?.maxCommonReprojectionError,
            'multiPointInlierRatio': multiPointCandidate?.inlierRatio,
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
                (multiPointEstimate?.valueOrNull?.duration ?? Duration.zero),
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
    required List<MarkerCorrespondence> correspondences,
    required ArucoAlignmentConfig config,
  }) {
    final errors = <double>[];
    var projectionFailed = false;
    for (final correspondence in correspondences) {
      try {
        errors.add(
          estimate.homography
              .project(correspondence.sourcePoint)
              .distanceTo(correspondence.destinationPoint),
        );
      } on Object {
        projectionFailed = true;
        errors.add(double.infinity);
      }
    }
    final sorted = List<double>.of(errors)..sort();
    final mean =
        errors.reduce((first, second) => first + second) / errors.length;
    final median =
        (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2;
    final maxError = errors.reduce(math.max);
    final maskIsValid =
        method == AlignmentHomographyMethod.fourPoint ||
        estimate.inliers.length == errors.length;
    final inlierCount = method == AlignmentHomographyMethod.fourPoint
        ? errors.length
        : estimate.inliers.where((value) => value).length;
    final perMarkerInliersAreSafe =
        method == AlignmentHomographyMethod.fourPoint ||
        (maskIsValid && _eachMarkerHasThreeInliers(estimate.inliers));
    final inlierErrorsAreSafe =
        method == AlignmentHomographyMethod.fourPoint ||
        (maskIsValid &&
            [
              for (var index = 0; index < errors.length; index++)
                if (estimate.inliers[index]) errors[index],
            ].every((error) => error <= config.maximumReprojectionErrorPixels));
    final accepted =
        !projectionFailed &&
        _isNumericallyStable(estimate.homography) &&
        mean.isFinite &&
        median.isFinite &&
        maxError.isFinite &&
        maskIsValid &&
        perMarkerInliersAreSafe &&
        inlierErrorsAreSafe &&
        (method == AlignmentHomographyMethod.fourPoint
            ? maxError <= config.maximumReprojectionErrorPixels
            : inlierCount / errors.length >=
                      config.minimumMultipointInlierRatio &&
                  maxError <= config.maximumRejectedCornerErrorPixels);
    return HomographyCandidateDiagnostics(
      method: method,
      commonReprojectionErrors: errors,
      meanCommonReprojectionError: mean,
      medianCommonReprojectionError: median,
      maxCommonReprojectionError: maxError,
      inlierCount: inlierCount,
      totalPointCount: errors.length,
      accepted: accepted,
      duration: estimate.duration,
    );
  }

  AlignmentHomographyMethod? _selectMethod(
    HomographyCandidateDiagnostics? fourPoint,
    HomographyCandidateDiagnostics? multiPoint,
    ArucoAlignmentConfig config,
  ) {
    if (multiPoint?.accepted == true &&
        (fourPoint?.accepted != true ||
            multiPoint!.commonScore +
                    config.minimumMultipointScoreImprovementPixels <
                fourPoint!.commonScore)) {
      return AlignmentHomographyMethod.multiPoint;
    }
    if (fourPoint?.accepted == true) return AlignmentHomographyMethod.fourPoint;
    if (multiPoint?.accepted == true) {
      return AlignmentHomographyMethod.multiPoint;
    }
    return null;
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

  bool _isNumericallyStable(HomographyMatrix matrix) {
    final h = matrix.values;
    final scale = h.map((value) => value.abs()).reduce(math.max);
    if (!scale.isFinite || scale == 0) return false;
    final determinant =
        h[0] * (h[4] * h[8] - h[5] * h[7]) -
        h[1] * (h[3] * h[8] - h[5] * h[6]) +
        h[2] * (h[3] * h[7] - h[4] * h[6]);
    return determinant.isFinite &&
        determinant.abs() / (scale * scale * scale) > 1e-12;
  }

  EngineResult<PageAlignmentResult> _failure(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );
}
