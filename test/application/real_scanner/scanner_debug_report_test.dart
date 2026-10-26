import 'package:capstone_development/application/camera_scanner/domain/camera_scan_state.dart';
import 'package:capstone_development/application/real_scanner/scanner_debug_report.dart';
import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
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
            'sourceSize': {'width': 3000, 'height': 4000},
            'detectionSize': {'width': 1050, 'height': 1400},
            'detectionScaleX': 2.857,
            'detectionScaleY': 2.857,
            'detectedRegistrationIds': [10, 11, 12, 13],
            'multiPointResiduals': [0.5, 1.2, 5.9],
            'multiPointInlierMask': [true, true, false],
            'multiPointInliersPerMarker': [4, 3, 3, 2],
            'effectiveRansacThreshold': 3.2,
            'effectiveFourPointConsistencyThreshold': 2.1,
            'effectiveRejectedCornerThreshold': 8.4,
            'reprojectionScaleFactor': 2.1,
            'fourPointNumericalValidation': 'passed',
            'multiPointNumericalValidation': 'passed',
            'fourPointGeometryValidation': 'passed',
            'multiPointGeometryValidation': 'passed',
            'stageTimingsMs': {'detection': 120.0, 'alignmentElapsed': 180.0},
            'fourPointRejectionReason': 'FULL_CORNER_CONSISTENCY_EXCEEDED',
            'multiPointRejectionReason': 'INSUFFICIENT_INLIERS',
            'multiPointInlierRatio': 0.75,
            'authToken': 'must-not-copy',
            'cause': r'C:\private\scanner.dart:10',
          },
        },
      },
    );
    final state = CameraScanState(
      phase: CameraScanPhase.scanFailed,
      cameraState: _cameraState(),
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
    expect(
      report,
      contains(
        'Failure four-point rejection reason: FULL_CORNER_CONSISTENCY_EXCEEDED',
      ),
    );
    expect(
      report,
      contains('Failure multi-point rejection reason: INSUFFICIENT_INLIERS'),
    );
    expect(report, contains('Failure source size: 3000x4000'));
    expect(report, contains('Failure detection size: 1050x1400'));
    expect(report, contains('Failure registration IDs: [10, 11, 12, 13]'));
    expect(report, contains('Failure multi-point residuals/mask/per-marker:'));
    expect(report, contains('Failure thresholds (RANSAC/four/tail/scale):'));
    expect(report, contains('Failure stage timings:'));
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
