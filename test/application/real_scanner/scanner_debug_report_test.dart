import 'package:capstone_development/application/camera_scanner/domain/camera_scan_state.dart';
import 'package:capstone_development/application/real_scanner/scanner_debug_report.dart';
import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/aruco/domain/alignment_failure_diagnostics.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_alignment_config.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/camera/domain/camera_models.dart';
import 'package:capstone_development/engines/camera/domain/live_frame_analysis.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessed_page.dart';
import 'package:capstone_development/engines/scanner/domain/scan_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'successful report includes preview, final still, and homography data',
    () {
      final state = _successfulState();
      final history = ScannerDebugHistory().record(
        state: state,
        outcome: ScannerDebugAttemptOutcome.succeeded,
        timestamp: DateTime(2026, 10, 26, 12),
      );

      final report = const ScannerDebugReportBuilder().build(
        currentState: state,
        expectedMarkerIds: const [10, 11, 12, 13],
        history: history,
        platform: 'android',
      );

      expect(report, contains('Paper outline detected: YES'));
      expect(
        report,
        contains('Observed registration marker IDs: [10, 11, 12, 13]'),
      );
      expect(report, contains('Captured image size: 3000x4000'));
      expect(report, contains('All 16 corner correspondences obtained: YES'));
      expect(
        report,
        contains('Selection policy: validatedMultiPointPreference'),
      );
      expect(report, contains('Selected method: multiPoint'));
      expect(report, contains('Multi-point candidate: accepted'));
      expect(report, contains('Fallback reason: unavailable'));
      expect(report, contains('Final warp: succeeded'));
    },
  );

  test('nested alignment rejection preserves exact stage and root cause', () {
    final error = EngineError(
      code: 'CAPTURE_SCAN_SCANNER_FAILED',
      message: 'The offline scanner rejected the captured page.',
      details: {
        'causeCode': 'SCAN_ALIGNMENT_FAILED',
        'causeMessage': 'Offline scanning failed during alignment.',
        'causeDetails': {
          'failedStage': 'alignment',
          'causeCode': 'ARUCO_REPROJECTION_FAILED',
          'causeMessage': 'Neither homography candidate passed.',
          'causeDetails': {
            AlignmentFailureDiagnostics.detailsKey: _failureDiagnostics()
                .toMap(),
            'authToken': 'must-not-copy',
            'cause': r'C:\private\scanner.dart:10',
          },
        },
      },
    );
    final state = CameraScanState(
      phase: CameraScanPhase.scanFailed,
      cameraState: const CameraEngineState.uninitialized(),
      error: error,
      finalCaptureDiagnostics: FinalCaptureDiagnostics(
        width: 3000,
        height: 4000,
        timestamp: DateTime(2026, 10, 26, 12),
      ),
    );
    final history = ScannerDebugHistory().record(
      state: state,
      outcome: ScannerDebugAttemptOutcome.failed,
      timestamp: DateTime(2026, 10, 26, 12),
    );

    final report = const ScannerDebugReportBuilder().build(
      currentState: _trackingState(),
      expectedMarkerIds: const [10, 11, 12, 13],
      history: history,
      platform: 'android',
    );

    expect(history.attempts.single.pipelineStage, 'HOMOGRAPHY');
    expect(report, contains('Root cause code: ARUCO_REPROJECTION_FAILED'));
    expect(report, contains('Stage: HOMOGRAPHY'));
    expect(report, contains('SCANNER ALIGNMENT FAILURE'));
    expect(report, contains('Detected markers: [10, 11, 12, 13]'));
    expect(report, contains('Attempt observed marker IDs: [10, 11, 12, 13]'));
    expect(report, contains('FOUR-POINT'));
    expect(report, contains('16-POINT RANSAC'));
    expect(report, contains('Estimate: SUCCEEDED'));
    expect(report, contains('Validation: REJECTED'));
    expect(report, contains('Reason: FULL_CORNER_CONSISTENCY_EXCEEDED'));
    expect(report, contains('Reason: UNSAFE_INLIER_DISTRIBUTION'));
    expect(report, contains('RANSAC inliers: 12/16'));
    expect(report, contains('marker 13 corner bottomLeft: 9.000 px'));
    expect(report, contains('No homography selected.'));
    expect(report, contains('Detection resolution: 1050x1400'));
    expect(report, isNot(contains('must-not-copy')));
    expect(report, isNot(contains(r'C:\private')));
  });

  test('failed attempt survives retry state and history remains bounded', () {
    var history = ScannerDebugHistory();
    for (var index = 0; index < 7; index++) {
      final failure = EngineError(
        code: 'SCAN_FAILURE_$index',
        message: 'Failure $index',
      );
      history = history.record(
        state: CameraScanState(
          phase: CameraScanPhase.scanFailed,
          cameraState: _cameraState(),
          error: failure,
        ),
        outcome: ScannerDebugAttemptOutcome.failed,
        timestamp: DateTime(2026, 10, 26, 12, index),
      );
    }

    final report = const ScannerDebugReportBuilder().build(
      currentState: _trackingState(),
      expectedMarkerIds: const [10, 11, 12, 13],
      history: history,
      platform: 'android',
    );

    expect(history.attempts, hasLength(5));
    expect(history.attempts.first.attemptNumber, 3);
    expect(history.attempts.last.attemptNumber, 7);
    expect(report, contains('Error code: SCAN_FAILURE_6'));
    expect(report, contains('#3'));
    expect(report, isNot(contains('Failure 0')));
  });

  test('missing optional telemetry is reported as unavailable', () {
    const state = CameraScanState(
      phase: CameraScanPhase.tracking,
      cameraState: CameraEngineState.uninitialized(),
    );

    final report = const ScannerDebugReportBuilder().build(
      currentState: state,
      expectedMarkerIds: const [10, 11, 12, 13],
      history: ScannerDebugHistory(),
      platform: 'android',
    );

    expect(report, contains('Tracking polygon: unavailable'));
    expect(report, contains('Outcome: unavailable'));
    expect(report, contains('Selected method: unavailable'));
    expect(report, contains('Native marker detection: unavailable'));
  });
}

AlignmentFailureDiagnostics _failureDiagnostics() {
  final corners = [
    for (final markerId in const [10, 11, 12, 13])
      for (final corner in const [
        'topLeft',
        'topRight',
        'bottomRight',
        'bottomLeft',
      ])
        {'id': markerId, 'corner': corner, 'x': 10.0, 'y': 20.0},
  ];
  HomographyAttemptDiagnostics attempt({
    required AlignmentHomographyMethod method,
    required String reason,
    required List<double> residuals,
    required List<int> perMarker,
  }) => HomographyAttemptDiagnostics(
    method: method,
    estimationStatus: HomographyEstimationStatus.succeeded,
    validationStatus: HomographyValidationStatus.rejected,
    estimationDuration: const Duration(milliseconds: 2),
    validationDuration: const Duration(milliseconds: 1),
    effectiveReprojectionThresholdPixels: 2.1,
    effectiveRansacThresholdPixels: 3.2,
    effectiveRejectedCornerThresholdPixels: 8.4,
    homography: HomographyMatrix([1, 0, 0, 0, 1, 0, 0, 0, 1]),
    rejectionReason: reason,
    meanResidual: residuals.reduce((a, b) => a + b) / residuals.length,
    medianResidual: 1,
    percentile95Residual: residuals.last,
    maximumResidual: residuals.reduce((a, b) => a > b ? a : b),
    cornerResiduals: residuals,
    inlierMask: [for (var index = 0; index < 16; index++) index < 12],
    inlierCount: 12,
    inliersPerMarker: perMarker,
    geometryValidationResult: 'passed',
    numericalValidationResult: 'passed',
  );
  return AlignmentFailureDiagnostics(
    sourceSize: ImageSize(width: 3000, height: 4000),
    detectionSize: ImageSize(width: 1050, height: 1400),
    detectionScaleX: 2.857,
    detectionScaleY: 2.857,
    expectedMarkerIds: const [10, 11, 12, 13],
    detectedRegistrationMarkerIds: const [10, 11, 12, 13],
    markerSideLengths: const [
      {
        'id': 10,
        'minimum': 30.0,
        'sides': [30.0, 30.0, 30.0, 30.0],
      },
    ],
    detectedCorners: corners,
    expectedCorners: corners,
    selectionPolicy: HomographySelectionPolicy.validatedMultiPointPreference,
    selectionReason: 'NO_TRUSTWORTHY_HOMOGRAPHY',
    fourPoint: attempt(
      method: AlignmentHomographyMethod.fourPoint,
      reason: 'FULL_CORNER_CONSISTENCY_EXCEEDED',
      residuals: [for (var index = 0; index < 16; index++) 2.0],
      perMarker: const [3, 3, 3, 3],
    ),
    multiPoint: attempt(
      method: AlignmentHomographyMethod.multiPoint,
      reason: 'UNSAFE_INLIER_DISTRIBUTION',
      residuals: [for (var index = 0; index < 15; index++) 1.0, 9.0],
      perMarker: const [4, 4, 4, 0],
    ),
    decodeDuration: const Duration(milliseconds: 8),
    detectionPreparationDuration: const Duration(milliseconds: 4),
    detectionDuration: const Duration(milliseconds: 120),
    coordinateRemapDuration: const Duration(milliseconds: 1),
    pageResolutionDuration: const Duration(milliseconds: 1),
    correspondenceDuration: const Duration(milliseconds: 3),
    totalDuration: const Duration(milliseconds: 180),
  );
}

CameraScanState _successfulState() => CameraScanState(
  phase: CameraScanPhase.scanCompleted,
  cameraState: _cameraState(),
  result: _result(),
  finalScanTimings: const FinalScanTimings(
    captureDuration: Duration(milliseconds: 120),
    byteLoadDuration: Duration(milliseconds: 8),
    totalDuration: Duration(milliseconds: 360),
  ),
  finalCaptureDiagnostics: FinalCaptureDiagnostics(
    width: 3000,
    height: 4000,
    timestamp: DateTime(2026, 10, 26, 12),
  ),
);

CameraScanState _trackingState() => CameraScanState(
  phase: CameraScanPhase.tracking,
  cameraState: _cameraState(),
);

CameraEngineState _cameraState() => CameraEngineState(
  lifecycle: CameraLifecycleState.analyzing,
  diagnostics: const CameraDiagnostics(),
  readiness: const CaptureReadiness(
    status: CaptureReadinessStatus.verifyingMarkers,
    stableFrameCount: 2,
    requiredStableFrameCount: 4,
  ),
  analysis: CameraAnalysisState(
    tracking: MarkerTrackingState(
      detectedMarkerIds: const [10, 11, 12, 13],
      registrationPoints: [
        ImagePoint(10, 10),
        ImagePoint(90, 10),
        ImagePoint(90, 190),
        ImagePoint(10, 190),
      ],
    ),
    quality: const FrameQuality(
      brightness: 120,
      sharpness: 80,
      pageAreaRatio: 0.5,
      perspectiveRatio: 1.2,
    ),
    readiness: const CaptureReadiness(
      status: CaptureReadinessStatus.verifyingMarkers,
      stableFrameCount: 2,
      requiredStableFrameCount: 4,
    ),
    stabilityScore: 0.9,
    processingDuration: const Duration(milliseconds: 16),
    sourceFrameSize: ImageSize(width: 1080, height: 1920),
    analysisFrameSize: ImageSize(width: 720, height: 1280),
    analysisScaleX: 1.5,
    analysisScaleY: 1.5,
    timings: const CameraAnalysisTimings(
      arucoDetectionDuration: Duration(milliseconds: 4),
      paperEdgeDetectionDuration: Duration(milliseconds: 3),
    ),
    document: DetectedDocument(
      geometry: DocumentGeometry(
        corners: [
          ImagePoint(5, 5),
          ImagePoint(95, 5),
          ImagePoint(95, 195),
          ImagePoint(5, 195),
        ],
        areaRatio: 0.5,
        centroid: ImagePoint(50, 100),
        perspectiveRatio: 1.1,
      ),
      confidence: 0.95,
    ),
  ),
);

ScanResult _result() {
  final candidate = HomographyCandidateDiagnostics(
    method: AlignmentHomographyMethod.multiPoint,
    commonReprojectionErrors: List.filled(16, 0.2),
    meanCommonReprojectionError: 0.2,
    medianCommonReprojectionError: 0.2,
    maxCommonReprojectionError: 0.2,
    inlierCount: 16,
    totalPointCount: 16,
    accepted: true,
    acceptance: HomographyCandidateAcceptance.reliable,
    duration: const Duration(milliseconds: 2),
    fittingResiduals: ReprojectionStatistics(List.filled(16, 0.2)),
    inliersPerMarker: const [4, 4, 4, 4],
  );
  const statistics = ImageStatistics(
    meanIntensity: 180,
    intensityStandardDeviation: 20,
    minimumIntensity: 0,
    maximumIntensity: 255,
    darkPixelRatio: 0.1,
    brightPixelRatio: 0.7,
  );
  return ScanResult(
    templateId: TemplateId('template'),
    templateVersion: TemplateVersion(1),
    pageId: PageId('page'),
    questions: const [],
    pageState: ScanPageState.accepted,
    reviewReasons: const [],
    reviewQuestionIds: const [],
    diagnostics: ScanDiagnostics(
      totalProcessingDuration: const Duration(milliseconds: 220),
      stageDurations: const ScanStageDurations(
        alignment: Duration(milliseconds: 30),
        preprocessing: Duration(milliseconds: 40),
        measurement: Duration(milliseconds: 80),
        classification: Duration(milliseconds: 20),
      ),
      alignment: PageAlignmentDiagnostics(
        expectedMarkerIds: const [10, 11, 12, 13],
        detectedMarkerIds: const [10, 11, 12, 13],
        sourceMarkerSideLengths: const [30, 31, 30, 31],
        sourceRegistrationPoints: [
          ImagePoint(10, 10),
          ImagePoint(90, 10),
          ImagePoint(10, 190),
          ImagePoint(90, 190),
        ],
        destinationRegistrationPoints: [
          ImagePoint(20, 20),
          ImagePoint(180, 20),
          ImagePoint(20, 280),
          ImagePoint(180, 280),
        ],
        registrationQuality: const RegistrationQuality(
          quadrilateralAreaRatio: 0.5,
          minimumMarkerSidePixels: 30,
          maximumPerspectiveRatio: 1.1,
        ),
        reprojectionErrors: List.filled(16, 0.2),
        meanReprojectionError: 0.2,
        maxReprojectionError: 0.2,
        processingDuration: const Duration(milliseconds: 30),
        sourceSize: ImageSize(width: 3000, height: 4000),
        detectionSize: ImageSize(width: 1050, height: 1400),
        selectedHomographyMethod: AlignmentHomographyMethod.multiPoint,
        fourPointCandidate: candidate,
        multiPointCandidate: candidate,
        selectionReason: 'EMPIRICALLY_VALIDATED_MULTIPOINT_PREFERENCE',
        effectiveReprojectionErrorPixels: 1.5,
        effectiveRansacReprojectionThresholdPixels: 2.25,
      ),
      preprocessing: const PreprocessingDiagnostics(
        sourceStatistics: statistics,
        normalizedStatistics: statistics,
        binaryForegroundRatio: 0.1,
        processingDuration: Duration(milliseconds: 40),
      ),
      summary: const ScanSummary(
        totalQuestions: 0,
        marked: 0,
        blank: 0,
        multiple: 0,
        ambiguous: 0,
        invalid: 0,
        requiredBlank: 0,
        measuredBubbles: 0,
      ),
    ),
  );
}
