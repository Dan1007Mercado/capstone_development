import 'dart:math' as math;
import 'dart:typed_data';

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../layout/domain/page_layout.dart';
import '../domain/aruco_alignment_config.dart';
import '../domain/aruco_vision_backend.dart';
import '../domain/image_geometry.dart';
import '../domain/page_alignment_result.dart';
import 'marker_correspondence_service.dart';

final class ArucoAlignmentEngine {
  const ArucoAlignmentEngine({
    required this.backend,
    this.correspondenceService = const MarkerCorrespondenceService(),
    this.config,
  });

  final ArucoVisionBackend backend;
  final MarkerCorrespondenceService correspondenceService;
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
      if (detectedIds.toSet().length != detectedIds.length) {
        return _failure(
          'SCAN_DUPLICATE_PAGE_MARKERS',
          'A page marker ID was detected more than once.',
          {'detectedMarkerIds': detectedIds},
        );
      }
      if (detectedIds.length != expectedIds.length ||
          !detectedIds.toSet().containsAll(expectedIds)) {
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
      final rectification = session.rectify(
        sourcePoints: correspondenceSet.sourcePoints,
        destinationPoints: correspondenceSet.destinationPoints,
        outputSize: outputSize,
      );
      if (rectification.isFailure) {
        return EngineResult.failure(rectification.error);
      }

      final reprojectionErrors = <double>[];
      try {
        for (final correspondence in correspondenceSet.correspondences) {
          final projected = rectification.value.homography.project(
            correspondence.sourcePoint,
          );
          reprojectionErrors.add(
            projected.distanceTo(correspondence.destinationPoint),
          );
        }
      } on Object {
        return _failure(
          'ARUCO_HOMOGRAPHY_FAILED',
          'Homography could not project registration points safely.',
        );
      }
      final meanError =
          reprojectionErrors.reduce((first, second) => first + second) /
          reprojectionErrors.length;
      final maxError = reprojectionErrors.reduce(math.max);
      if (!meanError.isFinite ||
          !maxError.isFinite ||
          maxError > effectiveConfig.maximumReprojectionErrorPixels) {
        return _failure(
          'ARUCO_REPROJECTION_FAILED',
          'Homography reprojection exceeds the configured tolerance.',
          {
            'meanReprojectionError': meanError,
            'maxReprojectionError': maxError,
            'maximumAllowedError':
                effectiveConfig.maximumReprojectionErrorPixels,
          },
        );
      }

      stopwatch.stop();
      return EngineResult.success(
        PageAlignmentResult(
          canonicalPage: rectification.value.canonicalPage,
          homography: rectification.value.homography,
          observations: correspondenceSet.observations,
          correspondences: correspondenceSet.correspondences,
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
            sourceRegistrationPoints: correspondenceSet.sourcePoints,
            destinationRegistrationPoints: correspondenceSet.destinationPoints,
            registrationQuality: correspondenceSet.quality,
            reprojectionErrors: reprojectionErrors,
            meanReprojectionError: meanError,
            maxReprojectionError: maxError,
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
            homographyDuration: rectification.value.timings.homography,
            warpDuration: rectification.value.timings.warp,
            detectionSize: session.openTimings.detectionSize,
            detectionScaleX: session.openTimings.detectionScaleX,
            detectionScaleY: session.openTimings.detectionScaleY,
          ),
        ),
      );
    } finally {
      session.dispose();
    }
  }

  EngineResult<PageAlignmentResult> _failure(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );
}
