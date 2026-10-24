import '../../core/errors/engine_error.dart';
import '../../core/ids/identifiers.dart';
import '../../core/result/engine_result.dart';
import '../../engines/scanner/domain/scan_result.dart';
import '../camera_scanner/domain/camera_scan_state.dart';
import 'multi_page_validation_recorder.dart';
import 'scan_acceptance_policy.dart';
import 'scanner_validation_session.dart';

const scannerReviewResultMissingCode = 'SCAN_REVIEW_RESULT_MISSING';

EngineError scannerReviewResultMissingError() => EngineError(
  code: scannerReviewResultMissingCode,
  message:
      'The scanner entered review without a retained page result. '
      'Restart this scanner session and scan the page again.',
);

enum ScannerValidationFlowAction {
  stateUpdated,
  resultRecorded,
  resultRejected,
  completionIgnored,
}

/// Owns the durable review result independently from transient camera states.
///
/// Camera tracking may continue while final scanning completes. Consequently,
/// [latestCameraState] is diagnostic state only and is never the source of the
/// result rendered during review.
final class ScannerValidationFlowController {
  ScannerValidationFlowController({
    required ScannerValidationSession session,
    required CameraScanState initialCameraState,
    ScanAcceptancePolicy acceptancePolicy = const ScanAcceptancePolicy(),
  }) : _session = session,
       _latestCameraState = initialCameraState,
       _reviewResult = _resultBeingReviewed(session),
       _acceptancePolicy = acceptancePolicy;

  ScannerValidationSession _session;
  CameraScanState _latestCameraState;
  ScanResult? _reviewResult;
  EngineError? _sessionError;
  ScanAcceptanceResult? _acceptanceRejection;
  final ScanAcceptancePolicy _acceptancePolicy;

  ScannerValidationSession get session => _session;
  CameraScanState get latestCameraState => _latestCameraState;
  ScanResult? get reviewResult => _reviewResult;
  EngineError? get sessionError => _sessionError;
  ScanAcceptanceResult? get acceptanceRejection => _acceptanceRejection;
  Iterable<PageId> get completedPageIds => session.resultsByPageId.keys;

  ScannerValidationFlowAction handleCoordinatorState(CameraScanState state) {
    _latestCameraState = state;
    if (state.phase == CameraScanPhase.scanFailed &&
        _isIdentityFailure(state.error?.code)) {
      _session = _session.recordMultiPageAttempt(
        detectedPageId: state.cameraState.analysis?.tracking.resolvedPageId,
        detectedMarkerIds: _detectedMarkerIds(state),
        outcome: MultiPageValidationAttemptOutcome.identityRejected,
        processingDuration: state.finalScanTimings.totalDuration,
        rejectionCode: state.error?.code,
      );
      return ScannerValidationFlowAction.stateUpdated;
    }
    if (state.phase != CameraScanPhase.scanCompleted) {
      return ScannerValidationFlowAction.stateUpdated;
    }

    // A completed result is consumed exactly once. Later/repeated completion
    // events cannot replace the result currently being reviewed.
    if (_session.state != ScannerValidationSessionState.scanning &&
        _session.state != ScannerValidationSessionState.duplicateChecking) {
      return ScannerValidationFlowAction.completionIgnored;
    }

    final completedResult = state.result;
    if (completedResult == null) {
      _sessionError = EngineError(
        code: 'SCAN_COMPLETED_RESULT_MISSING',
        message: 'The scanner completed without returning a page result.',
      );
      return ScannerValidationFlowAction.resultRejected;
    }

    final duplicateCheckActive =
        _session.state == ScannerValidationSessionState.duplicateChecking;
    final acceptance = _acceptancePolicy.evaluate(completedResult);
    if (!acceptance.accepted) {
      _reviewResult = null;
      _sessionError = null;
      _acceptanceRejection = acceptance;
      _session = _session.recordMultiPageAttempt(
        detectedPageId: completedResult.pageId,
        detectedMarkerIds: _detectedMarkerIds(state),
        outcome: MultiPageValidationAttemptOutcome.sessionRejected,
        processingDuration: _processingDuration(state, completedResult),
        rejectionCode: acceptance.decision.name,
      );
      return ScannerValidationFlowAction.resultRejected;
    }
    final recorded = _session.recordResult(completedResult);
    if (recorded.isFailure) {
      _sessionError = recorded.error;
      final duplicate = recorded.error.code == 'SCAN_PAGE_ALREADY_COMPLETED';
      _session = _session.recordMultiPageAttempt(
        detectedPageId: completedResult.pageId,
        detectedMarkerIds: _detectedMarkerIds(state),
        outcome: duplicate
            ? MultiPageValidationAttemptOutcome.duplicateRejected
            : MultiPageValidationAttemptOutcome.sessionRejected,
        processingDuration: _processingDuration(state, completedResult),
        rejectionCode: recorded.error.code,
      );
      final attempt = _session.multiPageAttempts.lastOrNull;
      if (duplicateCheckActive &&
          duplicate &&
          attempt?.expectedPageId == completedResult.pageId) {
        final finished = _session.finishDuplicateCheck();
        if (finished.isSuccess) _session = finished.value;
      }
      return ScannerValidationFlowAction.resultRejected;
    }

    _session = recorded.value.recordMultiPageAttempt(
      detectedPageId: completedResult.pageId,
      detectedMarkerIds: _detectedMarkerIds(state),
      outcome: MultiPageValidationAttemptOutcome.accepted,
      processingDuration: _processingDuration(state, completedResult),
    );
    _reviewResult = completedResult;
    _sessionError = null;
    _acceptanceRejection = null;
    return ScannerValidationFlowAction.resultRecorded;
  }

  EngineResult<ScannerValidationSession> continueAfterReview() {
    final advanced = _session.continueAfterReview();
    if (advanced.isFailure) {
      _sessionError = advanced.error;
      return advanced;
    }
    _session = advanced.value;
    _reviewResult = null;
    _sessionError = null;
    _acceptanceRejection = null;
    return advanced;
  }

  EngineResult<ScannerValidationSession> beginDuplicateCheck() {
    final started = _session.beginDuplicateCheck();
    if (started.isFailure) {
      _sessionError = started.error;
      return started;
    }
    _session = started.value;
    _reviewResult = null;
    _sessionError = null;
    return started;
  }

  void clearSessionError() {
    _sessionError = null;
    _acceptanceRejection = null;
  }

  static ScanResult? _resultBeingReviewed(ScannerValidationSession session) {
    final reviewingPageId = session.reviewingPageId;
    if (session.state != ScannerValidationSessionState.reviewing ||
        reviewingPageId == null) {
      return null;
    }
    return session.resultsByPageId[reviewingPageId];
  }

  static bool _isIdentityFailure(String? code) => const {
    'SCAN_PAGE_MARKERS_INCOMPLETE',
    'SCAN_UNKNOWN_PAGE_MARKERS',
    'SCAN_DUPLICATE_PAGE_MARKERS',
  }.contains(code);

  static List<int> _detectedMarkerIds(CameraScanState state) {
    final resultIds = state.result?.diagnostics.alignment.detectedMarkerIds;
    if (resultIds != null) return List.of(resultIds);
    final detailIds = state.error?.details['detectedMarkerIds'];
    if (detailIds is Iterable) {
      return detailIds.whereType<int>().toList(growable: false);
    }
    return List.of(
      state.cameraState.analysis?.tracking.detectedMarkerIds ?? const [],
    );
  }

  static Duration _processingDuration(
    CameraScanState state,
    ScanResult result,
  ) => state.finalScanTimings.totalDuration == Duration.zero
      ? result.diagnostics.totalProcessingDuration
      : state.finalScanTimings.totalDuration;
}
