import '../../core/errors/engine_error.dart';
import 'scan_acceptance_policy.dart';

enum ScannerFailureKind { recoverable, fatal }

final class ScannerUserFeedback {
  const ScannerUserFeedback({
    required this.kind,
    required this.title,
    required this.description,
    required this.actionLabel,
  });

  final ScannerFailureKind kind;
  final String title;
  final String description;
  final String actionLabel;
}

ScannerUserFeedback scannerUserFeedbackForError(EngineError error) {
  final code = _deepestCode(error);
  if (code == 'CAMERA_PERMISSION_DENIED') {
    return const ScannerUserFeedback(
      kind: ScannerFailureKind.fatal,
      title: 'Camera permission needed',
      description: 'Allow camera access, then try opening the scanner again.',
      actionLabel: 'Retry Camera',
    );
  }
  if (const {
    'CAMERA_UNAVAILABLE',
    'CAMERA_INITIALIZATION_FAILED',
    'CAMERA_STREAM_FAILED',
    'CAMERA_ANALYSIS_FAILED',
    'CAPTURE_SCAN_CAMERA_FAILED',
    'CAPTURE_SCAN_CAMERA_INITIALIZATION_FAILED',
    'CAPTURE_SCAN_CAMERA_STREAM_FAILED',
    'ARUCO_BACKEND_UNAVAILABLE',
    'NATIVE_BACKEND_UNAVAILABLE',
    'CAPTURE_SCAN_UNEXPECTED_FAILURE',
  }.contains(code)) {
    return const ScannerUserFeedback(
      kind: ScannerFailureKind.fatal,
      title: 'Scanner unavailable',
      description: 'The camera scanner stopped unexpectedly. Please retry it.',
      actionLabel: 'Retry Camera',
    );
  }
  if (const {
    'SCAN_UNKNOWN_PAGE_MARKERS',
    'SCAN_TEMPLATE_ID_MISMATCH',
    'SCAN_TEMPLATE_VERSION_MISMATCH',
    'SCAN_PAGE_ID_MISMATCH',
    'PACKET_PAGE_IDENTITY_MISMATCH',
  }.contains(code)) {
    return const ScannerUserFeedback(
      kind: ScannerFailureKind.recoverable,
      title: 'Incorrect answer sheet',
      description: 'Use a sheet that belongs to the selected form or packet.',
      actionLabel: 'Scan Again',
    );
  }
  if (const {
    'SCAN_DUPLICATE_PAGE_MARKERS',
    'ARUCO_REQUIRED_MARKER_DUPLICATE',
  }.contains(code)) {
    return const ScannerUserFeedback(
      kind: ScannerFailureKind.recoverable,
      title: 'Duplicate registration marker detected',
      description:
          'Use an undamaged sheet with one copy of each expected ArUco marker.',
      actionLabel: 'Scan Again',
    );
  }
  if (code == 'SCAN_PAGE_ALREADY_COMPLETED') {
    return const ScannerUserFeedback(
      kind: ScannerFailureKind.recoverable,
      title: 'Page already scanned',
      description:
          'This page is already recorded. Scan a missing page instead.',
      actionLabel: 'Continue Scanning',
    );
  }
  if (const {
    'SCAN_PAGE_MARKERS_INCOMPLETE',
    'ARUCO_REQUIRED_MARKER_MISSING',
    'ARUCO_DETECTION_FAILED',
  }.contains(code)) {
    return const ScannerUserFeedback(
      kind: ScannerFailureKind.recoverable,
      title: 'Registration markers not found',
      description:
          'Keep all four square ArUco registration markers visible and in focus.',
      actionLabel: 'Scan Again',
    );
  }
  if (code == 'ARUCO_MARKER_TOO_SMALL') {
    return const ScannerUserFeedback(
      kind: ScannerFailureKind.recoverable,
      title: 'Registration markers are too small',
      description: 'Move closer while keeping all four ArUco markers visible.',
      actionLabel: 'Scan Again',
    );
  }
  if (const {
    'ARUCO_GEOMETRY_INVALID',
    'ARUCO_REFLECTION_DETECTED',
  }.contains(code)) {
    return const ScannerUserFeedback(
      kind: ScannerFailureKind.recoverable,
      title: 'Page angle is too steep',
      description: 'Hold the camera more parallel to the flat answer sheet.',
      actionLabel: 'Scan Again',
    );
  }
  if (const {
    'ARUCO_REPROJECTION_FAILED',
    'ARUCO_HOMOGRAPHY_FAILED',
    'SCAN_ALIGNMENT_FAILED',
  }.contains(code)) {
    return const ScannerUserFeedback(
      kind: ScannerFailureKind.recoverable,
      title: 'Alignment failed validation',
      description:
          'Keep the sheet flat and all four ArUco registration markers sharp.',
      actionLabel: 'Scan Again',
    );
  }
  if (const {
    'SCAN_PREPROCESSING_FAILED',
    'SCAN_MEASUREMENT_FAILED',
    'SCAN_CLASSIFICATION_FAILED',
    'SCAN_RESULT_INVALID',
  }.contains(code)) {
    return const ScannerUserFeedback(
      kind: ScannerFailureKind.recoverable,
      title: 'Answers could not be read',
      description: 'Flatten the page, improve the lighting, and scan again.',
      actionLabel: 'Scan Again',
    );
  }
  return const ScannerUserFeedback(
    kind: ScannerFailureKind.recoverable,
    title: 'Sheet could not be recorded',
    description: 'Check the page and corner markers, then scan again.',
    actionLabel: 'Scan Again',
  );
}

ScannerUserFeedback scannerUserFeedbackForAcceptance(
  ScanAcceptanceResult result,
) => switch (result.decision) {
  ScanAcceptanceDecision.accept => const ScannerUserFeedback(
    kind: ScannerFailureKind.recoverable,
    title: 'Sheet accepted',
    description: '',
    actionLabel: 'Continue',
  ),
  ScanAcceptanceDecision.rescanBlankPage => ScannerUserFeedback(
    kind: ScannerFailureKind.recoverable,
    title: 'No answers were detected',
    description: result.guidance,
    actionLabel: 'Scan Again',
  ),
  ScanAcceptanceDecision.rescanAmbiguous => ScannerUserFeedback(
    kind: ScannerFailureKind.recoverable,
    title: 'Some answers are unclear',
    description: result.guidance,
    actionLabel: 'Scan Again',
  ),
  ScanAcceptanceDecision.rescanInvalid => ScannerUserFeedback(
    kind: ScannerFailureKind.recoverable,
    title: 'Answer regions were unreadable',
    description: result.guidance,
    actionLabel: 'Scan Again',
  ),
};

String _deepestCode(EngineError error) {
  var code = error.code;
  Object? details = error.details;
  while (details is Map) {
    final cause = details['causeCode'];
    if (cause is String && cause.isNotEmpty) code = cause;
    details = details['causeDetails'];
  }
  return code;
}
