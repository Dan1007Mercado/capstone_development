import 'package:capstone_development/application/real_scanner/scanner_user_feedback.dart';
import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wrong-sheet failure has a recoverable user presentation', () {
    final feedback = scannerUserFeedbackForError(
      EngineError(
        code: 'CAPTURE_SCAN_SCANNER_FAILED',
        message: 'technical wrapper',
        details: const {'causeCode': 'SCAN_UNKNOWN_PAGE_MARKERS'},
      ),
    );

    expect(feedback.kind, ScannerFailureKind.recoverable);
    expect(feedback.title, 'Incorrect answer sheet');
    expect(feedback.description, isNot(contains('SCAN_')));
    expect(feedback.actionLabel, 'Scan Again');
  });

  test('camera stream failure uses the fatal recovery interface', () {
    final feedback = scannerUserFeedbackForError(
      EngineError(code: 'CAMERA_STREAM_FAILED', message: 'native details'),
    );

    expect(feedback.kind, ScannerFailureKind.fatal);
    expect(feedback.title, 'Scanner unavailable');
    expect(feedback.actionLabel, 'Retry Camera');
  });

  test('unknown scanner failure does not invent a specific cause', () {
    final feedback = scannerUserFeedbackForError(
      EngineError(code: 'UNMAPPED_FAILURE', message: 'secret detail'),
    );

    expect(feedback.title, 'Sheet could not be recorded');
    expect(feedback.description, isNot(contains('secret detail')));
  });
}
