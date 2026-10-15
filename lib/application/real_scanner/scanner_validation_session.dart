import 'dart:collection';

import '../../core/errors/engine_error.dart';
import '../../core/ids/identifiers.dart';
import '../../core/result/engine_result.dart';
import '../../engines/layout/domain/page_layout.dart';
import '../../engines/scanner/domain/scan_result.dart';
import '../../engines/scanner/domain/scanner_config.dart';
import '../camera_scanner/domain/camera_scan_context.dart';
import 'published_scanner_resolver.dart';
import 'scanner_identity_validation.dart';

enum ScannerValidationSessionState { scanning, reviewing, complete }

/// Process-local P13.5 validation state. This deliberately is not persistence.
final class ScannerValidationSession {
  ScannerValidationSession._({
    required this.artifact,
    required this.scannerConfig,
    required this.currentPageIndex,
    required Map<PageId, ScanResult> resultsByPageId,
    required this.state,
  }) : resultsByPageId = UnmodifiableMapView(resultsByPageId);

  factory ScannerValidationSession.start({
    required PublishedScannerArtifact artifact,
    ScannerConfig? scannerConfig,
  }) => ScannerValidationSession._(
    artifact: artifact,
    scannerConfig: scannerConfig ?? ScannerConfig(),
    currentPageIndex: 0,
    resultsByPageId: const {},
    state: ScannerValidationSessionState.scanning,
  );

  final PublishedScannerArtifact artifact;
  final ScannerConfig scannerConfig;
  final int currentPageIndex;
  final Map<PageId, ScanResult> resultsByPageId;
  final ScannerValidationSessionState state;

  List<PageLayout> get pages => artifact.layout.pages;
  PageLayout get currentPage => pages[currentPageIndex];
  int get completedPageCount => resultsByPageId.length;
  bool get isLastPage => currentPageIndex == pages.length - 1;

  CameraScanContext get currentContext => CameraScanContext(
    template: artifact.template,
    pageLayout: currentPage,
    templateId: artifact.templateId,
    templateVersion: artifact.templateVersion,
    pageId: currentPage.pageId,
    scannerConfig: scannerConfig,
  );

  EngineResult<ScannerValidationSession> recordResult(ScanResult result) {
    if (state != ScannerValidationSessionState.scanning) {
      return EngineResult.failure(
        EngineError(
          code: 'SCAN_SESSION_STATE_INVALID',
          message: 'A result can only be recorded while scanning.',
        ),
      );
    }
    if (resultsByPageId.containsKey(currentPage.pageId)) {
      return EngineResult.failure(
        EngineError(
          code: 'SCAN_PAGE_ALREADY_COMPLETED',
          message: 'The expected page has already been completed.',
          details: {'pageId': currentPage.pageId.value},
        ),
      );
    }
    final identity = validateScanResultIdentity(result, currentContext);
    if (identity.isFailure) return EngineResult.failure(identity.error);
    return EngineResult.success(
      ScannerValidationSession._(
        artifact: artifact,
        scannerConfig: scannerConfig,
        currentPageIndex: currentPageIndex,
        resultsByPageId: {...resultsByPageId, currentPage.pageId: result},
        state: ScannerValidationSessionState.reviewing,
      ),
    );
  }

  EngineResult<ScannerValidationSession> continueAfterReview() {
    if (state != ScannerValidationSessionState.reviewing ||
        !resultsByPageId.containsKey(currentPage.pageId)) {
      return EngineResult.failure(
        EngineError(
          code: 'SCAN_SESSION_STATE_INVALID',
          message: 'The current page must be reviewed before continuing.',
        ),
      );
    }
    final complete = isLastPage;
    return EngineResult.success(
      ScannerValidationSession._(
        artifact: artifact,
        scannerConfig: scannerConfig,
        currentPageIndex: complete ? currentPageIndex : currentPageIndex + 1,
        resultsByPageId: resultsByPageId,
        state: complete
            ? ScannerValidationSessionState.complete
            : ScannerValidationSessionState.scanning,
      ),
    );
  }
}
