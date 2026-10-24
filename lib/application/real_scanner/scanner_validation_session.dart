import 'dart:collection';

import '../../core/errors/engine_error.dart';
import '../../core/ids/identifiers.dart';
import '../../core/result/engine_result.dart';
import '../../engines/layout/domain/page_layout.dart';
import '../../engines/scanner/domain/scan_result.dart';
import '../../engines/scanner/domain/scanner_config.dart';
import '../../engines/scanner/domain/packet_scan_identity.dart';
import '../camera_scanner/domain/camera_scan_context.dart';
import 'multi_page_validation_recorder.dart';
import 'physical_validation_recorder.dart';
import 'published_scanner_resolver.dart';

enum ScannerValidationSessionState {
  scanning,
  reviewing,
  duplicateChecking,
  complete,
}

/// Process-local P13.5 validation state. This deliberately is not persistence.
final class ScannerValidationSession {
  ScannerValidationSession._({
    required this.artifact,
    required this.scannerConfig,
    required Map<PageId, ScanResult> resultsByPageId,
    required Iterable<MultiPageValidationAttempt> multiPageAttempts,
    required this.state,
    this.validationPlan,
    this.multiPageValidationPlan,
    this.reviewingPageId,
    this.packetScanContext,
  }) : resultsByPageId = UnmodifiableMapView(resultsByPageId),
       multiPageAttempts = UnmodifiableListView(List.of(multiPageAttempts));

  factory ScannerValidationSession.start({
    required PublishedScannerArtifact artifact,
    ScannerConfig? scannerConfig,
    PhysicalValidationPlan? validationPlan,
    MultiPageValidationPlan? multiPageValidationPlan,
    PacketScanContext? packetScanContext,
  }) => ScannerValidationSession._(
    artifact: artifact,
    scannerConfig: scannerConfig ?? ScannerConfig(),
    resultsByPageId: const {},
    multiPageAttempts: const [],
    state: ScannerValidationSessionState.scanning,
    validationPlan: validationPlan,
    multiPageValidationPlan: multiPageValidationPlan,
    packetScanContext: packetScanContext,
  );

  final PublishedScannerArtifact artifact;
  final ScannerConfig scannerConfig;
  final Map<PageId, ScanResult> resultsByPageId;
  final List<MultiPageValidationAttempt> multiPageAttempts;
  final ScannerValidationSessionState state;
  final PhysicalValidationPlan? validationPlan;
  final MultiPageValidationPlan? multiPageValidationPlan;
  final PageId? reviewingPageId;
  final PacketScanContext? packetScanContext;

  PhysicalValidationReport? get validationReport {
    final plan = validationPlan;
    if (plan == null) return null;
    return PhysicalValidationReport.record(
      plan: plan,
      results: [for (final page in pages) ?resultsByPageId[page.pageId]],
    );
  }

  List<PageLayout> get pages => artifact.layout.pages;
  List<ScanResult> get orderedResults => [
    for (final page in pages) ?resultsByPageId[page.pageId],
  ];
  int get pageCount => pages.length;
  int get completedPageCount => resultsByPageId.length;
  bool get isComplete => completedPageCount == pageCount;
  List<PageId> get remainingPageIds => [
    for (final page in pages)
      if (!resultsByPageId.containsKey(page.pageId)) page.pageId,
  ];
  bool isPageCompleted(PageId pageId) => resultsByPageId.containsKey(pageId);
  MultiPageValidationReport? get multiPageValidationReport {
    final plan = multiPageValidationPlan;
    if (plan == null) return null;
    return MultiPageValidationReport.build(
      plan: plan,
      attempts: multiPageAttempts,
      orderedResults: orderedResults,
      sessionComplete: isComplete,
    );
  }

  int get currentPageIndex {
    final id =
        reviewingPageId ??
        (remainingPageIds.isEmpty ? pages.last.pageId : remainingPageIds.first);
    return pages.indexWhere((page) => page.pageId == id);
  }

  PageLayout get currentPage => pages[currentPageIndex];

  CameraScanContext get currentContext => CameraScanContext(
    template: artifact.template,
    pageLayout: currentPage,
    templateId: artifact.templateId,
    templateVersion: artifact.templateVersion,
    pageId: currentPage.pageId,
    scannerConfig: scannerConfig,
    candidatePageLayouts: pages,
    packetScanContext: packetScanContext,
  );

  EngineResult<CameraScanContext> contextForPage(PageId pageId) {
    final page = pages
        .where((candidate) => candidate.pageId == pageId)
        .firstOrNull;
    if (page == null) {
      return EngineResult.failure(
        EngineError(
          code: 'SCAN_UNKNOWN_PAGE_MARKERS',
          message:
              'The detected page does not belong to the selected template version.',
          details: {'pageId': pageId.value},
        ),
      );
    }
    return EngineResult.success(currentContext.withPage(page));
  }

  EngineResult<ScannerValidationSession> recordResult(ScanResult result) {
    final page = pages
        .where((candidate) => candidate.pageId == result.pageId)
        .firstOrNull;
    if (page == null ||
        result.templateId != artifact.templateId ||
        result.templateVersion != artifact.templateVersion) {
      return EngineResult.failure(
        EngineError(
          code: 'SCAN_UNKNOWN_PAGE_MARKERS',
          message:
              'The scan result does not belong to the selected template version.',
          details: {'pageId': result.pageId.value},
        ),
      );
    }
    if (resultsByPageId.containsKey(result.pageId)) {
      return EngineResult.failure(
        EngineError(
          code: 'SCAN_PAGE_ALREADY_COMPLETED',
          message: 'This page has already been completed.',
          details: {'pageId': result.pageId.value},
        ),
      );
    }
    if (state != ScannerValidationSessionState.scanning) {
      return EngineResult.failure(
        EngineError(
          code: 'SCAN_SESSION_STATE_INVALID',
          message: 'A new result can only be recorded while scanning.',
        ),
      );
    }
    return EngineResult.success(
      ScannerValidationSession._(
        artifact: artifact,
        scannerConfig: scannerConfig,
        resultsByPageId: {...resultsByPageId, result.pageId: result},
        multiPageAttempts: multiPageAttempts,
        state: ScannerValidationSessionState.reviewing,
        validationPlan: validationPlan,
        multiPageValidationPlan: multiPageValidationPlan,
        reviewingPageId: result.pageId,
        packetScanContext: packetScanContext,
      ),
    );
  }

  EngineResult<ScannerValidationSession> continueAfterReview() {
    if (state != ScannerValidationSessionState.reviewing ||
        reviewingPageId == null ||
        !resultsByPageId.containsKey(reviewingPageId)) {
      return EngineResult.failure(
        EngineError(
          code: 'SCAN_SESSION_STATE_INVALID',
          message: 'The current page must be reviewed before continuing.',
        ),
      );
    }
    final complete = isComplete;
    return EngineResult.success(
      ScannerValidationSession._(
        artifact: artifact,
        scannerConfig: scannerConfig,
        resultsByPageId: resultsByPageId,
        multiPageAttempts: multiPageAttempts,
        state: complete
            ? ScannerValidationSessionState.complete
            : ScannerValidationSessionState.scanning,
        validationPlan: validationPlan,
        multiPageValidationPlan: multiPageValidationPlan,
        reviewingPageId: null,
        packetScanContext: packetScanContext,
      ),
    );
  }

  EngineResult<ScannerValidationSession> beginDuplicateCheck() {
    if (state != ScannerValidationSessionState.reviewing ||
        !isComplete ||
        multiPageValidationPlan == null) {
      return EngineResult.failure(
        EngineError(
          code: 'SCAN_SESSION_STATE_INVALID',
          message:
              'Duplicate validation requires all unique pages to be reviewed.',
        ),
      );
    }
    return EngineResult.success(
      ScannerValidationSession._(
        artifact: artifact,
        scannerConfig: scannerConfig,
        resultsByPageId: resultsByPageId,
        multiPageAttempts: multiPageAttempts,
        state: ScannerValidationSessionState.duplicateChecking,
        validationPlan: validationPlan,
        multiPageValidationPlan: multiPageValidationPlan,
        reviewingPageId: null,
        packetScanContext: packetScanContext,
      ),
    );
  }

  EngineResult<ScannerValidationSession> finishDuplicateCheck() {
    if (state != ScannerValidationSessionState.duplicateChecking) {
      return EngineResult.failure(
        EngineError(
          code: 'SCAN_SESSION_STATE_INVALID',
          message: 'No duplicate-page validation is active.',
        ),
      );
    }
    return EngineResult.success(
      ScannerValidationSession._(
        artifact: artifact,
        scannerConfig: scannerConfig,
        resultsByPageId: resultsByPageId,
        multiPageAttempts: multiPageAttempts,
        state: ScannerValidationSessionState.complete,
        validationPlan: validationPlan,
        multiPageValidationPlan: multiPageValidationPlan,
        reviewingPageId: null,
        packetScanContext: packetScanContext,
      ),
    );
  }

  ScannerValidationSession recordMultiPageAttempt({
    required PageId? detectedPageId,
    required Iterable<int> detectedMarkerIds,
    required MultiPageValidationAttemptOutcome outcome,
    required Duration processingDuration,
    String? rejectionCode,
  }) {
    final plan = multiPageValidationPlan;
    if (plan == null) return this;
    final index = multiPageAttempts.length;
    final expectedPageId = index < plan.expectedCaptureOrder.length
        ? plan.expectedCaptureOrder[index]
        : null;
    final attempt = MultiPageValidationAttempt(
      templateId: artifact.templateId,
      templateVersion: artifact.templateVersion,
      expectedPageId: expectedPageId,
      detectedPageId: detectedPageId,
      detectedMarkerIds: detectedMarkerIds,
      captureSequenceIndex: index + 1,
      outcome: outcome,
      rejectionCode: rejectionCode,
      processingDuration: processingDuration,
      completedUniquePageCount: completedPageCount,
      missingPageIds: remainingPageIds,
    );
    return ScannerValidationSession._(
      artifact: artifact,
      scannerConfig: scannerConfig,
      resultsByPageId: resultsByPageId,
      multiPageAttempts: [...multiPageAttempts, attempt],
      state: state,
      validationPlan: validationPlan,
      multiPageValidationPlan: multiPageValidationPlan,
      reviewingPageId: reviewingPageId,
      packetScanContext: packetScanContext,
    );
  }
}
