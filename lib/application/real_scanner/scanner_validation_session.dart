import 'dart:collection';

import '../../core/errors/engine_error.dart';
import '../../core/ids/identifiers.dart';
import '../../core/result/engine_result.dart';
import '../../engines/layout/domain/page_layout.dart';
import '../../engines/scanner/domain/scan_result.dart';
import '../../engines/scanner/domain/scanner_config.dart';
import '../camera_scanner/domain/camera_scan_context.dart';
import 'physical_validation_recorder.dart';
import 'published_scanner_resolver.dart';

enum ScannerValidationSessionState { scanning, reviewing, complete }

/// Process-local P13.5 validation state. This deliberately is not persistence.
final class ScannerValidationSession {
  ScannerValidationSession._({
    required this.artifact,
    required this.scannerConfig,
    required Map<PageId, ScanResult> resultsByPageId,
    required this.state,
    this.validationPlan,
    this.reviewingPageId,
  }) : resultsByPageId = UnmodifiableMapView(resultsByPageId);

  factory ScannerValidationSession.start({
    required PublishedScannerArtifact artifact,
    ScannerConfig? scannerConfig,
    PhysicalValidationPlan? validationPlan,
  }) => ScannerValidationSession._(
    artifact: artifact,
    scannerConfig: scannerConfig ?? ScannerConfig(),
    resultsByPageId: const {},
    state: ScannerValidationSessionState.scanning,
    validationPlan: validationPlan,
  );

  final PublishedScannerArtifact artifact;
  final ScannerConfig scannerConfig;
  final Map<PageId, ScanResult> resultsByPageId;
  final ScannerValidationSessionState state;
  final PhysicalValidationPlan? validationPlan;
  final PageId? reviewingPageId;

  PhysicalValidationReport? get validationReport {
    final plan = validationPlan;
    if (plan == null) return null;
    return PhysicalValidationReport.record(
      plan: plan,
      results: [for (final page in pages) ?resultsByPageId[page.pageId]],
    );
  }

  List<PageLayout> get pages => artifact.layout.pages;
  int get pageCount => pages.length;
  int get completedPageCount => resultsByPageId.length;
  bool get isComplete => completedPageCount == pageCount;
  List<PageId> get remainingPageIds => [
    for (final page in pages)
      if (!resultsByPageId.containsKey(page.pageId)) page.pageId,
  ];
  bool isPageCompleted(PageId pageId) => resultsByPageId.containsKey(pageId);
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
    if (state != ScannerValidationSessionState.scanning) {
      return EngineResult.failure(
        EngineError(
          code: 'SCAN_SESSION_STATE_INVALID',
          message: 'A result can only be recorded while scanning.',
        ),
      );
    }
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
    return EngineResult.success(
      ScannerValidationSession._(
        artifact: artifact,
        scannerConfig: scannerConfig,
        resultsByPageId: {...resultsByPageId, result.pageId: result},
        state: ScannerValidationSessionState.reviewing,
        validationPlan: validationPlan,
        reviewingPageId: result.pageId,
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
        state: complete
            ? ScannerValidationSessionState.complete
            : ScannerValidationSessionState.scanning,
        validationPlan: validationPlan,
        reviewingPageId: null,
      ),
    );
  }
}
