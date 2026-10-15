import 'dart:io';

import 'package:capstone_development/application/camera_scanner/domain/camera_scan_state.dart';
import 'package:capstone_development/application/real_scanner/published_scanner_resolver.dart';
import 'package:capstone_development/application/real_scanner/scanner_validation_flow.dart';
import 'package:capstone_development/application/real_scanner/scanner_validation_session.dart';
import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/debug/p11_1_scanner_validation_sheet.dart';
import 'package:capstone_development/debug/real_scanner_validation_screen.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/camera/domain/camera_models.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessed_page.dart';
import 'package:capstone_development/engines/scanner/domain/scan_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scanner review flow', () {
    test(
      'tracking updates after completion preserve one recorded review result',
      () {
        final fixture = _FlowFixture();
        final result = fixture.resultForPage(0);

        expect(
          fixture.flow.handleCoordinatorState(_completed(result)),
          ScannerValidationFlowAction.resultRecorded,
        );
        expect(
          fixture.flow.session.state,
          ScannerValidationSessionState.reviewing,
        );
        expect(fixture.flow.reviewResult, same(result));

        for (var index = 0; index < 3; index++) {
          expect(
            fixture.flow.handleCoordinatorState(_tracking()),
            ScannerValidationFlowAction.stateUpdated,
          );
          expect(fixture.flow.latestCameraState.result, isNull);
          expect(fixture.flow.reviewResult, same(result));
          expect(fixture.flow.session.completedPageCount, 1);
        }

        expect(
          fixture.flow.handleCoordinatorState(_completed(result)),
          ScannerValidationFlowAction.completionIgnored,
        );
        expect(fixture.flow.session.completedPageCount, 1);
        expect(fixture.flow.reviewResult, same(result));
      },
    );

    test('continue clears review result and next page scans normally', () {
      final fixture = _FlowFixture();
      final first = fixture.resultForPage(0);
      fixture.flow.handleCoordinatorState(_completed(first));

      final continued = fixture.flow.continueAfterReview();

      expect(continued.isSuccess, isTrue);
      expect(
        fixture.flow.session.state,
        ScannerValidationSessionState.scanning,
      );
      expect(fixture.flow.reviewResult, isNull);

      final second = fixture.resultForPage(1);
      expect(
        fixture.flow.handleCoordinatorState(_completed(second)),
        ScannerValidationFlowAction.resultRecorded,
      );
      expect(fixture.flow.reviewResult, same(second));
      expect(fixture.flow.session.completedPageCount, 2);
    });

    test('final page review advances to complete and clears result', () {
      final fixture = _FlowFixture();

      for (var index = 0; index < fixture.flow.session.pageCount; index++) {
        final result = fixture.resultForPage(index);
        expect(
          fixture.flow.handleCoordinatorState(_completed(result)),
          ScannerValidationFlowAction.resultRecorded,
        );
        expect(fixture.flow.reviewResult, same(result));
        expect(fixture.flow.continueAfterReview().isSuccess, isTrue);
      }

      expect(
        fixture.flow.session.state,
        ScannerValidationSessionState.complete,
      );
      expect(fixture.flow.reviewResult, isNull);
    });

    test('scan failure does not create or overwrite a review result', () {
      final fixture = _FlowFixture();

      expect(
        fixture.flow.handleCoordinatorState(
          CameraScanState(
            phase: CameraScanPhase.scanFailed,
            cameraState: const CameraEngineState.uninitialized(),
            error: EngineError(code: 'SCAN_FAILED', message: 'failed'),
          ),
        ),
        ScannerValidationFlowAction.stateUpdated,
      );
      expect(fixture.flow.reviewResult, isNull);
      expect(fixture.flow.session.completedPageCount, 0);

      final result = fixture.resultForPage(0);
      fixture.flow.handleCoordinatorState(_completed(result));
      fixture.flow.handleCoordinatorState(
        CameraScanState(
          phase: CameraScanPhase.scanFailed,
          cameraState: const CameraEngineState.uninitialized(),
          error: EngineError(code: 'LATE_FAILURE', message: 'late'),
        ),
      );
      expect(fixture.flow.reviewResult, same(result));
      expect(fixture.flow.session.completedPageCount, 1);
    });

    test('duplicate page rejection does not create a review result', () {
      final fixture = _FlowFixture();
      final result = fixture.resultForPage(0);
      fixture.flow.handleCoordinatorState(_completed(result));
      fixture.flow.continueAfterReview();

      expect(
        fixture.flow.handleCoordinatorState(_completed(result)),
        ScannerValidationFlowAction.resultRejected,
      );
      expect(fixture.flow.reviewResult, isNull);
      expect(fixture.flow.sessionError?.code, 'SCAN_PAGE_ALREADY_COMPLETED');
      expect(fixture.flow.session.completedPageCount, 1);
    });

    test('completed phase without result is a controlled failure', () {
      final fixture = _FlowFixture();

      expect(
        fixture.flow.handleCoordinatorState(
          const CameraScanState(
            phase: CameraScanPhase.scanCompleted,
            cameraState: CameraEngineState.uninitialized(),
          ),
        ),
        ScannerValidationFlowAction.resultRejected,
      );
      expect(fixture.flow.reviewResult, isNull);
      expect(fixture.flow.sessionError?.code, 'SCAN_COMPLETED_RESULT_MISSING');
    });
  });

  testWidgets(
    'review renders stored result after latest camera state loses result',
    (tester) async {
      final fixture = _FlowFixture();
      final result = fixture.resultForPage(0);
      fixture.flow.handleCoordinatorState(_completed(result));
      fixture.flow.handleCoordinatorState(_tracking());

      await tester.pumpWidget(
        MaterialApp(
          home: ScannerReviewStateView(
            session: fixture.flow.session,
            reviewResult: fixture.flow.reviewResult,
            onContinue: () {},
          ),
        ),
      );

      expect(fixture.flow.latestCameraState.result, isNull);
      expect(find.byType(ScannerPageResultScreen), findsOneWidget);
      expect(find.text('PageId: ${result.pageId.value}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing review result renders typed error instead of throwing', (
    tester,
  ) async {
    final fixture = _FlowFixture();
    final recorded = fixture.flow.session.recordResult(
      fixture.resultForPage(0),
    );
    expect(recorded.isSuccess, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: ScannerReviewStateView(
          session: recorded.value,
          reviewResult: null,
          onContinue: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('scanner-review-result-missing')), findsOne);
    expect(find.textContaining(scannerReviewResultMissingCode), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('review and worker response models retain no full image buffers', () {
    final resultSource = File(
      'lib/engines/scanner/domain/scan_result.dart',
    ).readAsStringSync();
    final cameraStateSource = File(
      'lib/application/camera_scanner/domain/camera_scan_state.dart',
    ).readAsStringSync();
    final workerSource = File(
      'lib/application/camera_scanner/infrastructure/'
      'isolate_offline_scanner_runner.dart',
    ).readAsStringSync();
    final responseSource = workerSource.substring(
      workerSource.indexOf('final class _WorkerScanResponse'),
      workerSource.indexOf('final class _WorkerDispose'),
    );

    expect(resultSource, isNot(contains('Uint8List')));
    expect(resultSource, isNot(contains('CanonicalPage')));
    expect(cameraStateSource, isNot(contains('encodedBytes')));
    expect(responseSource, isNot(contains('Uint8List')));
    expect(workerSource, contains('TransferableTypedData.fromList'));
    expect(workerSource, contains('alignmentBackend?.dispose()'));
  });
}

final class _FlowFixture {
  _FlowFixture() {
    final inputs = buildP11ScannerValidationSheetInputs();
    final session = ScannerValidationSession.start(
      artifact: PublishedScannerArtifact(
        template: inputs.template,
        layout: inputs.layout,
      ),
    );
    flow = ScannerValidationFlowController(
      session: session,
      initialCameraState: _tracking(),
    );
  }

  late final ScannerValidationFlowController flow;

  ScanResult resultForPage(int index) {
    final session = flow.session;
    final page = session.pages[index];
    final markerIds = page.markerRegions
        .map((region) => region.markerId)
        .toList(growable: false);
    const statistics = ImageStatistics(
      meanIntensity: 200,
      intensityStandardDeviation: 20,
      minimumIntensity: 0,
      maximumIntensity: 255,
      darkPixelRatio: 0.1,
      brightPixelRatio: 0.8,
    );
    return ScanResult(
      templateId: session.artifact.templateId,
      templateVersion: session.artifact.templateVersion,
      pageId: page.pageId,
      questions: const [],
      pageState: ScanPageState.accepted,
      reviewReasons: const [],
      reviewQuestionIds: const [],
      diagnostics: ScanDiagnostics(
        totalProcessingDuration: Duration.zero,
        stageDurations: const ScanStageDurations(
          alignment: Duration.zero,
          preprocessing: Duration.zero,
          measurement: Duration.zero,
          classification: Duration.zero,
        ),
        alignment: PageAlignmentDiagnostics(
          expectedMarkerIds: markerIds,
          detectedMarkerIds: markerIds,
          sourceMarkerSideLengths: const [20, 20, 20, 20],
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
}

CameraScanState _completed(ScanResult result) => CameraScanState(
  phase: CameraScanPhase.scanCompleted,
  cameraState: const CameraEngineState.uninitialized(),
  result: result,
);

CameraScanState _tracking() => const CameraScanState(
  phase: CameraScanPhase.tracking,
  cameraState: CameraEngineState.uninitialized(),
);
