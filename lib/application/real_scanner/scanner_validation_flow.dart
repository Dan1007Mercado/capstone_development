import '../../core/errors/engine_error.dart';
import '../../core/ids/identifiers.dart';
import '../../core/result/engine_result.dart';
import '../../engines/scanner/domain/scan_result.dart';
import '../camera_scanner/domain/camera_scan_state.dart';
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
  }) : _session = session,
       _latestCameraState = initialCameraState,
       _reviewResult = _resultBeingReviewed(session);

  ScannerValidationSession _session;
  CameraScanState _latestCameraState;
  ScanResult? _reviewResult;
  EngineError? _sessionError;

  ScannerValidationSession get session => _session;
  CameraScanState get latestCameraState => _latestCameraState;
  ScanResult? get reviewResult => _reviewResult;
  EngineError? get sessionError => _sessionError;
  Iterable<PageId> get completedPageIds => session.resultsByPageId.keys;

  ScannerValidationFlowAction handleCoordinatorState(CameraScanState state) {
    _latestCameraState = state;
    if (state.phase != CameraScanPhase.scanCompleted) {
      return ScannerValidationFlowAction.stateUpdated;
    }

    // A completed result is consumed exactly once. Later/repeated completion
    // events cannot replace the result currently being reviewed.
    if (_session.state != ScannerValidationSessionState.scanning) {
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

    final recorded = _session.recordResult(completedResult);
    if (recorded.isFailure) {
      _sessionError = recorded.error;
      return ScannerValidationFlowAction.resultRejected;
    }

    _session = recorded.value;
    _reviewResult = completedResult;
    _sessionError = null;
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
    return advanced;
  }

  void clearSessionError() {
    _sessionError = null;
  }

  static ScanResult? _resultBeingReviewed(ScannerValidationSession session) {
    final reviewingPageId = session.reviewingPageId;
    if (session.state != ScannerValidationSessionState.reviewing ||
        reviewingPageId == null) {
      return null;
    }
    return session.resultsByPageId[reviewingPageId];
  }
}
