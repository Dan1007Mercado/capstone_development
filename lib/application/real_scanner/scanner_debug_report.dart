import 'dart:collection';

import '../../core/errors/engine_error.dart';
import '../../engines/aruco/domain/alignment_failure_diagnostics.dart';
import '../../engines/aruco/domain/image_geometry.dart';
import '../../engines/aruco/domain/page_alignment_result.dart';
import '../../engines/camera/domain/camera_models.dart';
import '../../engines/scanner/domain/scan_result.dart';
import '../camera_scanner/domain/camera_scan_state.dart';

enum ScannerDebugAttemptOutcome { succeeded, failed }

final class ScannerDebugAttempt {
  const ScannerDebugAttempt({
    required this.attemptNumber,
    required this.timestamp,
    required this.outcome,
    required this.pipelineStage,
    required this.cameraState,
    required this.timings,
    this.result,
    this.error,
    this.capture,
  });

  final int attemptNumber;
  final DateTime timestamp;
  final ScannerDebugAttemptOutcome outcome;
  final String pipelineStage;
  final CameraEngineState cameraState;
  final FinalScanTimings timings;
  final ScanResult? result;
  final EngineError? error;
  final FinalCaptureDiagnostics? capture;
}

/// Bounded, image-free history of meaningful final scan outcomes.
final class ScannerDebugHistory {
  ScannerDebugHistory({
    this.capacity = 5,
    Iterable<ScannerDebugAttempt> attempts = const [],
  }) : assert(capacity > 0),
       attempts = UnmodifiableListView(List.of(attempts));

  final int capacity;
  final List<ScannerDebugAttempt> attempts;

  ScannerDebugHistory record({
    required CameraScanState state,
    required ScannerDebugAttemptOutcome outcome,
    required DateTime timestamp,
    EngineError? error,
  }) {
    final effectiveError = error ?? state.error;
    final updated = [
      ...attempts,
      ScannerDebugAttempt(
        attemptNumber: (attempts.lastOrNull?.attemptNumber ?? 0) + 1,
        timestamp: timestamp,
        outcome: outcome,
        pipelineStage: scannerFailureStage(state, effectiveError),
        cameraState: state.cameraState,
        timings: state.finalScanTimings,
        result: state.result,
        error: effectiveError,
        capture: state.finalCaptureDiagnostics,
      ),
    ];
    final retained = updated.length <= capacity
        ? updated
        : updated.sublist(updated.length - capacity);
    return ScannerDebugHistory(capacity: capacity, attempts: retained);
  }
}

String scannerFailureStage(CameraScanState state, EngineError? error) {
  final code = _deepestErrorCode(error) ?? '';
  if (code.contains('PREPROCESS')) return 'PREPROCESSING';
  if (code.contains('MEASUREMENT')) return 'BUBBLE_MEASUREMENT';
  if (code.contains('CLASSIFICATION')) return 'OMR_CLASSIFICATION';
  if (code.contains('RESULT_INVALID')) return 'SCAN_VALIDATION';
  if (code.contains('REPROJECTION') || code.contains('HOMOGRAPHY')) {
    return 'HOMOGRAPHY';
  }
  if (code.contains('GEOMETRY') ||
      code.contains('REFLECTION') ||
      code.contains('MARKER_TOO_SMALL')) {
    return 'ALIGNMENT_GEOMETRY';
  }
  if (code.contains('MARKER') ||
      code.contains('ARUCO') ||
      code.contains('ALIGNMENT')) {
    return 'ARUCO_DETECTION_OR_ALIGNMENT';
  }
  if (code.contains('IMAGE_LOAD')) return 'IMAGE_LOADING';
  if (code.contains('CAPTURE') || code.contains('CAMERA')) return 'CAPTURE';
  final detailsStage = _deepestDetail(error, 'failedStage');
  if (detailsStage is String && detailsStage.isNotEmpty) {
    return detailsStage.toUpperCase();
  }
  return switch (state.phase) {
    CameraScanPhase.capturing => 'CAPTURE',
    CameraScanPhase.scanning => 'SCANNER',
    CameraScanPhase.scanCompleted => 'COMPLETE',
    CameraScanPhase.scanFailed => 'UNKNOWN_FAILURE_STAGE',
    _ => 'PREVIEW',
  };
}

final class ScannerDebugReportBuilder {
  const ScannerDebugReportBuilder();

  String build({
    required CameraScanState currentState,
    required Iterable<int> expectedMarkerIds,
    required ScannerDebugHistory history,
    required String platform,
  }) {
    final expected = List<int>.of(expectedMarkerIds);
    final latest = history.attempts.lastOrNull;
    final result = latest?.result ?? currentState.result;
    final alignment = result?.diagnostics.alignment;
    final analysis = currentState.cameraState.analysis;
    final cameraDiagnostics = currentState.cameraState.diagnostics;
    final observed = analysis?.tracking.detectedMarkerIds ?? const <int>[];
    final missing = expected.where((id) => !observed.contains(id)).toList();
    final duplicates = _duplicates(observed);
    final error = latest?.error ?? currentState.error;
    final failureAlignment = error == null
        ? null
        : AlignmentFailureDiagnostics.findInDetails(error.details);
    final finalObserved =
        alignment?.detectedMarkerIds ??
        failureAlignment?.detectedRegistrationMarkerIds ??
        _detailIntList(error, 'detectedMarkerIds');
    final document = analysis?.document;
    final buffer = StringBuffer()
      ..writeln('SCANNER DEBUG REPORT')
      ..writeln('App: Capstone OMR')
      ..writeln('Phase: P15.2.5')
      ..writeln('Platform: $platform')
      ..writeln()
      ..writeln('CURRENT STATE')
      ..writeln('Scanner state: ${currentState.phase.name.toUpperCase()}')
      ..writeln('Camera lifecycle: ${currentState.cameraState.lifecycle.name}')
      ..writeln(
        'Current error code: ${currentState.error?.code ?? 'unavailable'}',
      )
      ..writeln(
        'Current root cause code: '
        '${_deepestErrorCode(currentState.error) ?? 'unavailable'}',
      )
      ..writeln('Paper outline detected: ${_yesNo(document != null)}')
      ..writeln(
        'Document tracking phase: '
        '${analysis?.documentTrackingPhase.name ?? 'unavailable'}',
      )
      ..writeln(
        'Tracking polygon: ${document == null ? 'unavailable' : 'available'}',
      )
      ..writeln(
        'Tracked polygon vertices: '
        '${document?.geometry.corners.length ?? 'unavailable'}',
      )
      ..writeln('Document confidence: ${_number(document?.confidence)}')
      ..writeln('Capture ready: ${_yesNo(currentState.canCapture)}')
      ..writeln()
      ..writeln('PREVIEW')
      ..writeln(
        'Preview size: ${_previewSize(currentState.cameraState.previewInfo)}',
      )
      ..writeln('Source frame size: ${_size(analysis?.sourceFrameSize)}')
      ..writeln('Analysis frame size: ${_size(analysis?.analysisFrameSize)}')
      ..writeln('ArUco markers detected: ${observed.length}')
      ..writeln('Required registration marker IDs: ${_list(expected)}')
      ..writeln('Observed registration marker IDs: ${_list(observed)}')
      ..writeln('Missing registration marker IDs: ${_list(missing)}')
      ..writeln('Duplicate registration marker IDs: ${_list(duplicates)}')
      ..writeln(
        'Marker registration points: '
        '${analysis?.tracking.registrationPoints.length ?? 'unavailable'}',
      )
      ..writeln('Minimum marker side: unavailable')
      ..writeln('Readiness: ${currentState.cameraState.readiness.status.name}')
      ..writeln(
        'Stable frames: ${currentState.cameraState.readiness.stableFrameCount}/'
        '${currentState.cameraState.readiness.requiredStableFrameCount}',
      )
      ..writeln('Stability score: ${_number(analysis?.stabilityScore)}')
      ..writeln(
        'Last preview rejection: '
        '${currentState.error?.code ?? analysis?.tracking.pageResolutionErrorCode ?? _readinessRejection(currentState)}',
      )
      ..writeln(
        'Preview analysis latency: ${_ms(analysis?.processingDuration)}',
      )
      ..writeln(
        'ArUco preview latency: ${_ms(analysis?.timings.arucoDetectionDuration)}',
      )
      ..writeln(
        'Document-edge latency: '
        '${_ms(analysis?.timings.paperEdgeDetectionDuration)}',
      )
      ..writeln(
        'Latest camera diagnostic: '
        '${cameraDiagnostics.lastErrorCode ?? 'unavailable'}',
      )
      ..writeln()
      ..writeln('LAST ATTEMPT')
      ..writeln('Attempt: ${latest?.attemptNumber ?? 'unavailable'}')
      ..writeln(
        'Timestamp: ${latest?.timestamp.toIso8601String() ?? 'unavailable'}',
      )
      ..writeln(
        'Outcome: ${latest?.outcome.name.toUpperCase() ?? 'unavailable'}',
      )
      ..writeln('Stage: ${latest?.pipelineStage ?? 'unavailable'}')
      ..writeln('Error code: ${error?.code ?? 'unavailable'}')
      ..writeln('Root cause code: ${_deepestErrorCode(error) ?? 'unavailable'}')
      ..writeln('Error message: ${error?.message ?? 'unavailable'}')
      ..writeln(
        'Root cause message: ${_deepestErrorMessage(error) ?? 'unavailable'}',
      )
      ..writeln('Error details: ${_safeErrorDetails(error)}')
      ..writeln(
        'Attempt readiness: '
        '${latest?.cameraState.readiness.status.name ?? 'unavailable'}',
      )
      ..writeln(
        'Attempt observed marker IDs: '
        '${_list(latest?.result?.diagnostics.alignment.detectedMarkerIds ?? failureAlignment?.detectedRegistrationMarkerIds ?? latest?.cameraState.analysis?.tracking.detectedMarkerIds)}',
      )
      ..writeln('Attempt total duration: ${_ms(latest?.timings.totalDuration)}')
      ..writeln()
      ..writeln('FINAL STILL')
      ..writeln(
        'Captured image size: '
        '${_captureSize(latest?.capture ?? currentState.finalCaptureDiagnostics)}',
      )
      ..writeln(
        'Decoded source size: '
        '${_size(alignment?.sourceSize ?? failureAlignment?.sourceSize)}',
      )
      ..writeln(
        'Detection resolution: '
        '${_size(alignment?.detectionSize ?? failureAlignment?.detectionSize)}',
      )
      ..writeln(
        'Detection resize factors: ${alignment != null
            ? '${_fixed(alignment.detectionScaleX)} x ${_fixed(alignment.detectionScaleY)}'
            : failureAlignment != null
            ? '${_fixed(failureAlignment.detectionScaleX)} x ${_fixed(failureAlignment.detectionScaleY)}'
            : 'unavailable'}',
      )
      ..writeln(
        'Detected marker count: ${finalObserved?.length ?? 'unavailable'}',
      )
      ..writeln(
        'Expected marker IDs: ${_list(alignment?.expectedMarkerIds ?? expected)}',
      )
      ..writeln('Observed marker IDs: ${_list(finalObserved)}')
      ..writeln(
        'Corner correspondences: '
        '${alignment?.reprojectionErrors.length ?? 'unavailable'}',
      )
      ..writeln(
        'All 16 corner correspondences obtained: '
        '${alignment == null ? 'unavailable' : _yesNo(alignment.reprojectionErrors.length == 16)}',
      )
      ..writeln(
        'Marker side lengths: ${_list(alignment?.sourceMarkerSideLengths)}',
      )
      ..writeln(
        'Registration corner coordinates: '
        '${_points(alignment?.sourceRegistrationPoints)}',
      );
    if (failureAlignment != null) {
      _writeAlignmentFailure(buffer, failureAlignment);
    }
    buffer
      ..writeln()
      ..writeln('HOMOGRAPHY')
      ..writeln(
        'Selection policy: ${alignment?.selectionPolicy.name ?? 'unavailable'}',
      )
      ..writeln(
        'Selected method: '
        '${alignment?.selectedHomographyMethod.name ?? 'unavailable'}',
      )
      ..writeln(
        'Selection reason: ${alignment?.selectionReason ?? 'unavailable'}',
      )
      ..writeln(
        'Fallback reason: ${alignment?.fallbackReason ?? 'unavailable'}',
      )
      ..writeln(
        'Compact alignment summary: ${_alignmentSummary(alignment, error)}',
      )
      ..writeln('Worst corners: ${_worstCorners(alignment)}');
    _writeCandidate(buffer, 'Four-point', alignment?.fourPointCandidate);
    _writeCandidate(buffer, 'Multi-point', alignment?.multiPointCandidate);
    buffer
      ..writeln('Failure source size: ${_failureSize(error, 'sourceSize')}')
      ..writeln(
        'Failure detection size: ${_failureSize(error, 'detectionSize')}',
      )
      ..writeln(
        'Failure detection scale: '
        '${_deepestDetail(error, 'detectionScaleX') ?? 'unavailable'} x '
        '${_deepestDetail(error, 'detectionScaleY') ?? 'unavailable'}',
      )
      ..writeln(
        'Failure registration IDs: '
        '${_compactDetail(_deepestDetail(error, 'detectedRegistrationIds'))}',
      )
      ..writeln(
        'Failure marker sides: '
        '${_compactDetail(_deepestDetail(error, 'sourceMarkerSideLengths'))}',
      )
      ..writeln(
        'Failure detected corners: '
        '${_compactDetail(_deepestDetail(error, 'detectedCorners'))}',
      )
      ..writeln(
        'Failure expected corners: '
        '${_compactDetail(_deepestDetail(error, 'expectedCorners'))}',
      )
      ..writeln(
        'Failure four-point residuals/mask/per-marker: '
        '${_compactDetail(_deepestDetail(error, 'fourPointResiduals'))} / '
        '${_compactDetail(_deepestDetail(error, 'fourPointInlierMask'))} / '
        '${_compactDetail(_deepestDetail(error, 'fourPointInliersPerMarker'))}',
      )
      ..writeln(
        'Failure multi-point residuals/mask/per-marker: '
        '${_compactDetail(_deepestDetail(error, 'multiPointResiduals'))} / '
        '${_compactDetail(_deepestDetail(error, 'multiPointInlierMask'))} / '
        '${_compactDetail(_deepestDetail(error, 'multiPointInliersPerMarker'))}',
      )
      ..writeln(
        'Failure four-point rejection reason: '
        '${_deepestDetail(error, 'fourPointRejectionReason') ?? 'unavailable'}',
      )
      ..writeln(
        'Failure multi-point rejection reason: '
        '${_deepestDetail(error, 'multiPointRejectionReason') ?? 'unavailable'}',
      )
      ..writeln(
        'Failure multi-point inlier ratio: '
        '${_deepestDetail(error, 'multiPointInlierRatio') ?? 'unavailable'}',
      )
      ..writeln(
        'Failure thresholds (RANSAC/four/tail/scale): '
        '${_deepestDetail(error, 'effectiveRansacThreshold') ?? 'unavailable'} / '
        '${_deepestDetail(error, 'effectiveFourPointConsistencyThreshold') ?? 'unavailable'} / '
        '${_deepestDetail(error, 'effectiveRejectedCornerThreshold') ?? 'unavailable'} / '
        '${_deepestDetail(error, 'reprojectionScaleFactor') ?? 'unavailable'}',
      )
      ..writeln(
        'Failure numerical validation (four/multi): '
        '${_deepestDetail(error, 'fourPointNumericalValidation') ?? 'unavailable'} / '
        '${_deepestDetail(error, 'multiPointNumericalValidation') ?? 'unavailable'}',
      )
      ..writeln(
        'Failure geometry validation (four/multi): '
        '${_deepestDetail(error, 'fourPointGeometryValidation') ?? 'unavailable'} / '
        '${_deepestDetail(error, 'multiPointGeometryValidation') ?? 'unavailable'}',
      )
      ..writeln(
        'Failure stage timings: '
        '${_compactDetail(_deepestDetail(error, 'stageTimingsMs'))}',
      )
      ..writeln(
        'Reprojection mean/max: '
        '${_number(alignment?.meanReprojectionError)}/'
        '${_number(alignment?.maxReprojectionError)}',
      )
      ..writeln(
        'Reprojection scale factor: '
        '${_number(alignment?.reprojectionScaleFactor)}',
      )
      ..writeln(
        'Effective reprojection threshold: '
        '${_pixels(alignment?.effectiveReprojectionErrorPixels)}',
      )
      ..writeln(
        'Effective RANSAC threshold: '
        '${_pixels(alignment?.effectiveRansacReprojectionThresholdPixels)}',
      )
      ..writeln(
        'Effective rejected-corner threshold: '
        '${_pixels(alignment?.effectiveRejectedCornerErrorPixels)}',
      )
      ..writeln(
        'Geometry validation result: '
        '${result != null
            ? 'passed'
            : latest?.pipelineStage == 'ALIGNMENT_GEOMETRY'
            ? 'failed (${_deepestErrorCode(error)})'
            : 'unavailable'}',
      )
      ..writeln('Final warp: ${result == null ? 'unavailable' : 'succeeded'}')
      ..writeln()
      ..writeln('TIMINGS')
      ..writeln('Preview analysis: ${_ms(analysis?.processingDuration)}')
      ..writeln('Camera capture: ${_ms(latest?.timings.captureDuration)}')
      ..writeln('Image load: ${_ms(latest?.timings.byteLoadDuration)}')
      ..writeln('Image decode: ${_ms(alignment?.decodeDuration)}')
      ..writeln('Native marker detection: ${_ms(alignment?.detectionDuration)}')
      ..writeln(
        'Marker correspondence: ${_ms(alignment?.correspondenceDuration)}',
      )
      ..writeln(
        'Four-point estimation: '
        '${_ms(alignment?.fourPointHomographyDuration)}',
      )
      ..writeln(
        'Multi-point estimation: '
        '${_ms(alignment?.multiPointHomographyDuration)}',
      )
      ..writeln(
        'Candidate validation: '
        '${_ms(alignment?.candidateValidationDuration)}',
      )
      ..writeln('Canonical warp: ${_ms(alignment?.warpDuration)}')
      ..writeln(
        'Preprocessing: ${_ms(result?.diagnostics.stageDurations.preprocessing)}',
      )
      ..writeln(
        'OMR classification: '
        '${_ms(result?.diagnostics.stageDurations.classification)}',
      )
      ..writeln(
        'Total scan processing: '
        '${_ms(latest?.timings.totalDuration ?? result?.diagnostics.totalProcessingDuration)}',
      )
      ..writeln()
      ..writeln('RECENT FAILURES');
    final earlierFailures = history.attempts
        .where(
          (attempt) =>
              attempt.outcome == ScannerDebugAttemptOutcome.failed &&
              attempt != latest,
        )
        .toList(growable: false);
    if (earlierFailures.isEmpty) {
      buffer.writeln('No earlier recorded failures');
    } else {
      for (final attempt in earlierFailures) {
        buffer.writeln(
          '#${attempt.attemptNumber} ${attempt.timestamp.toIso8601String()} '
          '${attempt.pipelineStage} '
          '${attempt.error?.code ?? 'unavailable'}: '
          '${attempt.error?.message ?? 'unavailable'}; '
          'markers=${_list(attempt.cameraState.analysis?.tracking.detectedMarkerIds)}; '
          'total=${_ms(attempt.timings.totalDuration)}',
        );
      }
    }
    return buffer.toString().trimRight();
  }

  static void _writeAlignmentFailure(
    StringBuffer buffer,
    AlignmentFailureDiagnostics diagnostics,
  ) {
    buffer
      ..writeln()
      ..writeln('SCANNER ALIGNMENT FAILURE')
      ..writeln('Required markers: ${_list(diagnostics.expectedMarkerIds)}')
      ..writeln(
        'Detected markers: '
        '${_list(diagnostics.detectedRegistrationMarkerIds)}',
      );
    _writeFailedAttempt(buffer, 'FOUR-POINT', diagnostics.fourPoint);
    _writeFailedAttempt(buffer, '16-POINT RANSAC', diagnostics.multiPoint);
    buffer
      ..writeln()
      ..writeln('WORST CORNERS');
    final worst = _failureWorstCorners(diagnostics);
    if (worst.isEmpty) {
      buffer.writeln('unavailable: neither estimator produced residuals');
    } else {
      for (final item in worst) {
        buffer.writeln(
          '${item.method}: marker ${item.markerId} corner ${item.corner}: '
          '${_fixed(item.error)} px',
        );
      }
    }
    buffer
      ..writeln()
      ..writeln('FINAL DECISION')
      ..writeln('Alignment rejected.')
      ..writeln('No homography selected.')
      ..writeln('Reason: ${diagnostics.selectionReason}')
      ..writeln(
        'Marker side lengths: ${_compactDetail(diagnostics.markerSideLengths)}',
      )
      ..writeln(
        'Detected corners: ${_compactDetail(diagnostics.detectedCorners)}',
      )
      ..writeln(
        'Expected corners: ${_compactDetail(diagnostics.expectedCorners)}',
      )
      ..writeln(
        'Detection/correspondence/total: '
        '${_ms(diagnostics.detectionDuration)}/'
        '${_ms(diagnostics.correspondenceDuration)}/'
        '${_ms(diagnostics.totalDuration)}',
      );
  }

  static void _writeFailedAttempt(
    StringBuffer buffer,
    String label,
    HomographyAttemptDiagnostics attempt,
  ) {
    buffer
      ..writeln()
      ..writeln(label)
      ..writeln('Estimate: ${attempt.estimationStatus.name.toUpperCase()}')
      ..writeln('Validation: ${attempt.validationStatus.name.toUpperCase()}')
      ..writeln(
        'Reason: '
        '${attempt.rejectionReason ?? attempt.estimationFailureCode ?? 'none'}',
      )
      ..writeln('Homography: ${_list(attempt.homography?.values)}')
      ..writeln(
        'Residual mean/median/P95/max: '
        '${_number(attempt.meanResidual)}/'
        '${_number(attempt.medianResidual)}/'
        '${_number(attempt.percentile95Residual)}/'
        '${_number(attempt.maximumResidual)} px',
      )
      ..writeln('All corner residuals: ${_list(attempt.cornerResiduals)}')
      ..writeln(
        'RANSAC inliers: ${attempt.inlierCount}/'
        '${attempt.inlierMask.length}',
      )
      ..writeln('Inlier mask: ${_list(attempt.inlierMask)}')
      ..writeln('Inlier counts per marker: ${_list(attempt.inliersPerMarker)}')
      ..writeln(
        'Geometry validation: '
        '${attempt.geometryValidationResult ?? 'unavailable'}',
      )
      ..writeln(
        'Numerical validation: '
        '${attempt.numericalValidationResult ?? 'unavailable'}',
      )
      ..writeln(
        'Effective thresholds (consistency/RANSAC/tail): '
        '${_fixed(attempt.effectiveReprojectionThresholdPixels)}/'
        '${_fixed(attempt.effectiveRansacThresholdPixels)}/'
        '${_fixed(attempt.effectiveRejectedCornerThresholdPixels)} px',
      )
      ..writeln(
        'Estimator/validation duration: '
        '${_ms(attempt.estimationDuration)}/'
        '${_ms(attempt.validationDuration)}',
      );
  }

  static List<({String method, int markerId, String corner, double error})>
  _failureWorstCorners(AlignmentFailureDiagnostics diagnostics) {
    final values =
        <({String method, int markerId, String corner, double error})>[];
    for (final entry in [
      (method: 'four-point', attempt: diagnostics.fourPoint),
      (method: '16-point', attempt: diagnostics.multiPoint),
    ]) {
      for (
        var index = 0;
        index < entry.attempt.cornerResiduals.length &&
            index < diagnostics.detectedCorners.length;
        index++
      ) {
        final point = diagnostics.detectedCorners[index];
        values.add((
          method: entry.method,
          markerId: point['id'] as int,
          corner: point['corner'] as String,
          error: entry.attempt.cornerResiduals[index],
        ));
      }
    }
    values.sort((left, right) => right.error.compareTo(left.error));
    return values.take(4).toList(growable: false);
  }

  static void _writeCandidate(
    StringBuffer buffer,
    String label,
    HomographyCandidateDiagnostics? candidate,
  ) {
    buffer
      ..writeln(
        '$label candidate: '
        '${candidate == null
            ? 'unavailable'
            : candidate.accepted
            ? 'accepted'
            : 'rejected'}',
      )
      ..writeln(
        '$label rejection reason: '
        '${candidate?.rejectionReason ?? 'unavailable'}',
      )
      ..writeln(
        '$label reprojection mean/P95/max: '
        '${_number(candidate?.fittingResiduals?.mean)}/'
        '${_number(candidate?.fittingResiduals?.percentile95)}/'
        '${_number(candidate?.fittingResiduals?.maximum)}',
      )
      ..writeln(
        '$label inliers: ${candidate == null ? 'unavailable' : '${candidate.inlierCount}/${candidate.totalPointCount} (${_fixed(candidate.inlierRatio)})'}',
      )
      ..writeln(
        '$label inliers per marker: ${_list(candidate?.inliersPerMarker)}',
      )
      ..writeln('$label inlier mask: ${_list(candidate?.inlierMask)}')
      ..writeln(
        '$label geometry validation: '
        '${candidate == null ? 'unavailable' : candidate.geometryValidationFailure ?? 'passed'}',
      );
  }

  static String _alignmentSummary(
    PageAlignmentDiagnostics? alignment,
    EngineError? error,
  ) {
    if (alignment != null) {
      final allMarkers = alignment.expectedMarkerIds
          .toSet()
          .difference(alignment.detectedMarkerIds.toSet())
          .isEmpty;
      final multi = alignment.multiPointCandidate;
      return 'markers=${allMarkers ? 'all detected' : 'missing'}; '
          'selected=${alignment.selectedHomographyMethod.name}; '
          'multi=${multi == null
              ? 'not run'
              : multi.accepted
              ? 'accepted'
              : 'rejected (${multi.rejectionReason})'}';
    }
    final four = _deepestDetail(error, 'fourPointRejectionReason');
    final multi = _deepestDetail(error, 'multiPointRejectionReason');
    return 'alignment failed; four=${four ?? 'unavailable'}; '
        'multi=${multi ?? 'unavailable'}';
  }

  static String _worstCorners(PageAlignmentDiagnostics? alignment) {
    if (alignment == null || alignment.reprojectionErrors.isEmpty) {
      return 'unavailable';
    }
    final indexed = [
      for (var index = 0; index < alignment.reprojectionErrors.length; index++)
        (index: index, error: alignment.reprojectionErrors[index]),
    ]..sort((left, right) => right.error.compareTo(left.error));
    return indexed
        .take(4)
        .map((entry) {
          final markerIndex = entry.index ~/ 4;
          final marker = markerIndex < alignment.expectedMarkerIds.length
              ? alignment.expectedMarkerIds[markerIndex]
              : '?';
          const corners = ['TL', 'TR', 'BR', 'BL'];
          return 'marker $marker ${corners[entry.index % 4]}=${_fixed(entry.error)}px';
        })
        .join(', ');
  }
}

String? _deepestErrorCode(EngineError? error) {
  if (error == null) return null;
  var code = error.code;
  Object? details = error.details;
  while (details is Map) {
    final causeCode = details['causeCode'];
    if (causeCode is String && causeCode.isNotEmpty) code = causeCode;
    details = details['causeDetails'];
  }
  return code;
}

String? _deepestErrorMessage(EngineError? error) {
  if (error == null) return null;
  var message = error.message;
  Object? details = error.details;
  while (details is Map) {
    final causeMessage = details['causeMessage'];
    if (causeMessage is String && causeMessage.isNotEmpty) {
      message = causeMessage;
    }
    details = details['causeDetails'];
  }
  return message;
}

Object? _deepestDetail(EngineError? error, String key) {
  Object? value;
  Object? details = error?.details;
  while (details is Map) {
    if (details[key] != null) value = details[key];
    details = details['causeDetails'];
  }
  return value;
}

String _safeErrorDetails(EngineError? error) {
  if (error == null) return 'unavailable';
  const allowed = {
    'failedStage',
    'pageId',
    'causeCode',
    'causeMessage',
    'detectedMarkerIds',
    'expectedMarkerIds',
    'missingMarkerIds',
    'duplicateMarkerIds',
    'fourPointEstimateError',
    'fourPointMaxError',
    'multiPointEstimateError',
    'multiPointMaxError',
    'multiPointInlierRatio',
    'fourPointRejectionReason',
    'multiPointRejectionReason',
    'cameraLifecycle',
    'readiness',
    'freshReadinessRequired',
    'markerId',
    'minimumMarkerSidePixels',
    'actualMarkerSidePixels',
    'minimumSidePixels',
    'requiredMinimumPixels',
  };
  final values = <String>[];
  Object? details = error.details;
  while (details is Map) {
    for (final entry in details.entries) {
      if (entry.key is String && allowed.contains(entry.key)) {
        values.add('${entry.key}=${entry.value}');
      }
    }
    details = details['causeDetails'];
  }
  return values.isEmpty ? 'unavailable' : values.join(', ');
}

List<int>? _detailIntList(EngineError? error, String key) {
  final value = _deepestDetail(error, key);
  if (value is! Iterable) return null;
  return value.whereType<int>().toList(growable: false);
}

List<int> _duplicates(Iterable<int> values) {
  final counts = <int, int>{};
  for (final value in values) {
    counts[value] = (counts[value] ?? 0) + 1;
  }
  return [
    for (final entry in counts.entries)
      if (entry.value > 1) entry.key,
  ];
}

String _readinessRejection(CameraScanState state) =>
    state.cameraState.readiness.isReady
    ? 'none'
    : state.cameraState.readiness.status.name;

String _captureSize(FinalCaptureDiagnostics? capture) =>
    capture?.width == null || capture?.height == null
    ? 'unavailable'
    : '${capture!.width}x${capture.height}';

String _failureSize(EngineError? error, String key) {
  final value = _deepestDetail(error, key);
  if (value is! Map) return 'unavailable';
  return '${value['width'] ?? '?'}x${value['height'] ?? '?'}';
}

String _compactDetail(Object? value) {
  if (value == null) return 'unavailable';
  if (value is double) return _fixed(value);
  if (value is Iterable) {
    return '[${value.map(_compactDetail).join(', ')}]';
  }
  if (value is Map) {
    return '{${value.entries.map((entry) => '${entry.key}:${_compactDetail(entry.value)}').join(', ')}}';
  }
  return value.toString();
}

String _previewSize(CameraPreviewInfo? preview) =>
    preview == null ? 'unavailable' : '${preview.width}x${preview.height}';

String _size(ImageSize? size) =>
    size == null ? 'unavailable' : '${size.width}x${size.height}';

String _points(Iterable<ImagePoint>? points) => points == null
    ? 'unavailable'
    : points
          .map((point) => '(${_fixed(point.x)}, ${_fixed(point.y)})')
          .join(', ');

String _list(Iterable<Object?>? values) =>
    values == null ? 'unavailable' : '[${values.join(', ')}]';

String _yesNo(bool value) => value ? 'YES' : 'NO';
String _number(num? value) => value == null ? 'unavailable' : _fixed(value);
String _pixels(num? value) =>
    value == null ? 'unavailable' : '${_fixed(value)} px';
String _fixed(num value) => value.toStringAsFixed(3);
String _ms(Duration? duration) => duration == null
    ? 'unavailable'
    : '${(duration.inMicroseconds / 1000).toStringAsFixed(1)} ms';
