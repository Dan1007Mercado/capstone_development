import 'package:capstone_development/application/camera_scanner/domain/camera_scan_state.dart';
import 'package:capstone_development/application/real_scanner/multi_page_validation_recorder.dart';
import 'package:capstone_development/application/real_scanner/published_scanner_resolver.dart';
import 'package:capstone_development/application/real_scanner/scanner_validation_flow.dart';
import 'package:capstone_development/application/real_scanner/scanner_validation_session.dart';
import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/debug/p11_1_scanner_validation_sheet.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/aruco/domain/page_marker_signature_resolver.dart';
import 'package:capstone_development/engines/camera/domain/camera_models.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessed_page.dart';
import 'package:capstone_development/engines/scanner/domain/scan_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PublishedScannerArtifact artifact;
  late MultiPageValidationPlan plan;

  setUp(() {
    final inputs = buildP11ScannerValidationSheetInputs();
    artifact = PublishedScannerArtifact(
      template: inputs.template,
      layout: inputs.layout,
    );
    plan = buildP13_9MultiPageValidationPlan(artifact)!;
  });

  test('fixture has deterministic PageIds and unique marker signatures', () {
    final second = buildP11ScannerValidationSheetInputs();
    final pageIds = artifact.layout.pages.map((page) => page.pageId.value);

    expect(artifact.layout.pages, hasLength(3));
    expect(pageIds, [
      'p11-1-scanner-validation-v1-p1',
      'p11-1-scanner-validation-v1-p2',
      'p11-1-scanner-validation-v1-p3',
    ]);
    expect(
      second.layout.pages.map((page) => page.pageId),
      artifact.layout.pages.map((page) => page.pageId),
    );
    expect(artifact.layout.pages.map(markerIdsForPage), [
      [10, 11, 12, 13],
      [14, 15, 16, 17],
      [18, 19, 20, 21],
    ]);
    final allMarkerIds = artifact.layout.pages.expand(markerIdsForPage);
    expect(allMarkerIds.toSet(), hasLength(12));
  });

  test(
    'exact resolver rejects incomplete, mixed, unknown, and duplicate IDs',
    () {
      final resolver = PageMarkerSignatureResolver.fromPages(
        artifact.layout.pages,
      );

      expect(
        resolver.resolve([14, 15, 16, 17]).value.pageId,
        plan.requiredPageIds[1],
      );
      expect(
        resolver.resolve([10, 11, 12]).error.code,
        'SCAN_PAGE_MARKERS_INCOMPLETE',
      );
      expect(
        resolver.resolve([10, 11, 16, 17]).error.code,
        'SCAN_UNKNOWN_PAGE_MARKERS',
      );
      expect(
        resolver.resolve([10, 11, 12, 14]).error.code,
        'SCAN_UNKNOWN_PAGE_MARKERS',
        reason: 'The resolver must not guess the closest page signature.',
      );
      expect(
        resolver.resolve([30, 31, 32, 33]).error.code,
        'SCAN_UNKNOWN_PAGE_MARKERS',
      );
      expect(
        resolver.resolve([14, 15, 16, 16]).error.code,
        'SCAN_DUPLICATE_PAGE_MARKERS',
      );
    },
  );

  test('2 → 1 → 3 → duplicate 2 records safely and orders final results', () {
    final initial = ScannerValidationSession.start(
      artifact: artifact,
      multiPageValidationPlan: plan,
    );
    final flow = ScannerValidationFlowController(
      session: initial,
      initialCameraState: _tracking(),
    );
    final pages = artifact.layout.pages;
    for (final index in const [1, 0]) {
      final result = _result(artifact, pages[index], index + 1);
      expect(
        flow.handleCoordinatorState(_completed(result)),
        ScannerValidationFlowAction.resultRecorded,
      );
      expect(flow.session.isComplete, isFalse);
      expect(flow.continueAfterReview().isSuccess, isTrue);
      expect(flow.session.state, ScannerValidationSessionState.scanning);
    }

    final third = _result(artifact, pages[2], 3);
    expect(
      flow.handleCoordinatorState(_completed(third)),
      ScannerValidationFlowAction.resultRecorded,
    );
    expect(flow.session.isComplete, isTrue);
    expect(flow.session.completedPageCount, 3);
    expect(flow.session.resultsByPageId, hasLength(3));
    final originalPage2 = flow.session.resultsByPageId[pages[1].pageId];

    expect(flow.beginDuplicateCheck().isSuccess, isTrue);
    expect(flow.session.state, ScannerValidationSessionState.duplicateChecking);
    final duplicatePage2 = _result(artifact, pages[1], 99);
    expect(
      flow.handleCoordinatorState(_completed(duplicatePage2)),
      ScannerValidationFlowAction.resultRejected,
    );

    expect(flow.sessionError?.code, 'SCAN_PAGE_ALREADY_COMPLETED');
    expect(flow.session.state, ScannerValidationSessionState.complete);
    expect(flow.session.completedPageCount, 3);
    expect(flow.session.resultsByPageId, hasLength(3));
    expect(flow.session.resultsByPageId[pages[1].pageId], same(originalPage2));
    expect(
      flow.session.resultsByPageId[pages[1].pageId],
      isNot(same(duplicatePage2)),
    );
    expect(flow.session.remainingPageIds, isEmpty);
    expect(
      flow.session.orderedResults.map((result) => result.pageId),
      pages.map((page) => page.pageId),
    );

    final report = flow.session.multiPageValidationReport!;
    expect(report.attempts, hasLength(4));
    expect(report.attempts.map((attempt) => attempt.expectedPageId), [
      pages[1].pageId,
      pages[0].pageId,
      pages[2].pageId,
      pages[1].pageId,
    ]);
    expect(report.attempts.map((attempt) => attempt.detectedPageId), [
      pages[1].pageId,
      pages[0].pageId,
      pages[2].pageId,
      pages[1].pageId,
    ]);
    expect(report.attempts.last.duplicate, isTrue);
    expect(report.attempts.last.accepted, isFalse);
    expect(report.attempts.last.completedUniquePageCount, 3);
    expect(report.attempts.last.missingPageIds, isEmpty);
    expect(report.summary.requiredPages, 3);
    expect(report.summary.uniqueAcceptedPages, 3);
    expect(report.summary.duplicateAttempts, 1);
    expect(report.summary.wrongPageDetections, 0);
    expect(report.summary.rejectedIdentityAttempts, 0);
    expect(report.summary.sessionComplete, isTrue);
    expect(report.summary.finalPageOrder, pages.map((page) => page.pageId));
    expect(
      report.summary.totalProcessingDuration,
      const Duration(milliseconds: 40),
    );
    expect(
      report.summary.averageProcessingDuration,
      const Duration(milliseconds: 10),
    );
  });

  test('wrong template/version result cannot enter the session', () {
    final session = ScannerValidationSession.start(artifact: artifact);
    final page = artifact.layout.pages.first;
    final wrongTemplate = session.recordResult(
      _result(artifact, page, 1, templateId: TemplateId('wrong-template')),
    );
    final wrongVersion = session.recordResult(
      _result(artifact, page, 2, templateVersion: TemplateVersion(2)),
    );

    expect(wrongTemplate.error.code, 'SCAN_UNKNOWN_PAGE_MARKERS');
    expect(wrongVersion.error.code, 'SCAN_UNKNOWN_PAGE_MARKERS');
    expect(session.resultsByPageId, isEmpty);
    expect(session.completedPageCount, 0);
    expect(session.isComplete, isFalse);
  });

  test('identity rejection is retained without accepting a page', () {
    final flow = ScannerValidationFlowController(
      session: ScannerValidationSession.start(
        artifact: artifact,
        multiPageValidationPlan: plan,
      ),
      initialCameraState: _tracking(),
    );

    final action = flow.handleCoordinatorState(
      CameraScanState(
        phase: CameraScanPhase.scanFailed,
        cameraState: const CameraEngineState.uninitialized(),
        error: EngineError(
          code: 'SCAN_UNKNOWN_PAGE_MARKERS',
          message: 'Mixed page signature.',
          details: const {
            'detectedMarkerIds': [10, 11, 16, 17],
          },
        ),
        finalScanTimings: const FinalScanTimings(
          totalDuration: Duration(milliseconds: 7),
        ),
      ),
    );

    expect(action, ScannerValidationFlowAction.stateUpdated);
    expect(flow.session.completedPageCount, 0);
    expect(flow.session.multiPageAttempts.single.accepted, isFalse);
    expect(
      flow.session.multiPageAttempts.single.outcome,
      MultiPageValidationAttemptOutcome.identityRejected,
    );
    expect(flow.session.multiPageAttempts.single.detectedMarkerIds, [
      10,
      11,
      16,
      17,
    ]);
    expect(
      flow.session.multiPageValidationReport!.summary.rejectedIdentityAttempts,
      1,
    );
  });
}

ScanResult _result(
  PublishedScannerArtifact artifact,
  PageLayout page,
  int token, {
  TemplateId? templateId,
  TemplateVersion? templateVersion,
}) {
  const statistics = ImageStatistics(
    meanIntensity: 200,
    intensityStandardDeviation: 20,
    minimumIntensity: 0,
    maximumIntensity: 255,
    darkPixelRatio: 0.1,
    brightPixelRatio: 0.8,
  );
  final markerIds = markerIdsForPage(page);
  return ScanResult(
    templateId: templateId ?? artifact.templateId,
    templateVersion: templateVersion ?? artifact.templateVersion,
    pageId: page.pageId,
    questions: const [],
    pageState: ScanPageState.accepted,
    reviewReasons: const [],
    reviewQuestionIds: const [],
    diagnostics: ScanDiagnostics(
      totalProcessingDuration: const Duration(milliseconds: 10),
      stageDurations: const ScanStageDurations(
        alignment: Duration(milliseconds: 4),
        preprocessing: Duration(milliseconds: 2),
        measurement: Duration(milliseconds: 2),
        classification: Duration(milliseconds: 1),
        validation: Duration(milliseconds: 1),
      ),
      alignment: PageAlignmentDiagnostics(
        expectedMarkerIds: markerIds,
        detectedMarkerIds: markerIds,
        sourceMarkerSideLengths: [(20 + token).toDouble(), 20, 20, 20],
        sourceRegistrationPoints: const [],
        destinationRegistrationPoints: const [],
        registrationQuality: const RegistrationQuality(
          quadrilateralAreaRatio: 0.5,
          minimumMarkerSidePixels: 20,
          maximumPerspectiveRatio: 1,
        ),
        reprojectionErrors: const [0, 0, 0, 0],
        meanReprojectionError: 0,
        maxReprojectionError: 0,
        processingDuration: Duration.zero,
      ),
      preprocessing: const PreprocessingDiagnostics(
        sourceStatistics: statistics,
        normalizedStatistics: statistics,
        binaryForegroundRatio: 0.1,
        processingDuration: Duration.zero,
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

CameraScanState _completed(ScanResult result) => CameraScanState(
  phase: CameraScanPhase.scanCompleted,
  cameraState: const CameraEngineState.uninitialized(),
  result: result,
  finalScanTimings: const FinalScanTimings(
    totalDuration: Duration(milliseconds: 10),
  ),
);

CameraScanState _tracking() => const CameraScanState(
  phase: CameraScanPhase.tracking,
  cameraState: CameraEngineState.uninitialized(),
);
