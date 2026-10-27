import 'dart:io';
import 'dart:typed_data';

import 'package:capstone_development/application/camera_scanner/domain/camera_scan_state.dart';
import 'package:capstone_development/application/real_scanner/published_scanner_resolver.dart';
import 'package:capstone_development/application/real_scanner/multi_page_validation_recorder.dart';
import 'package:capstone_development/application/real_scanner/scanner_validation_flow.dart';
import 'package:capstone_development/application/real_scanner/scanner_validation_session.dart';
import 'package:capstone_development/application/real_scanner/scanner_user_feedback.dart';
import 'package:capstone_development/application/published_templates/in_memory_published_template_artifact_repository.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact_service.dart';
import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/debug/p11_1_scanner_validation_sheet.dart';
import 'package:capstone_development/debug/real_scanner_validation_screen.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/camera/domain/camera_models.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessed_page.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification.dart';
import 'package:capstone_development/engines/scanner/domain/scan_result.dart';
import 'package:capstone_development/engines/scanner/domain/packet_scan_identity.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
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

    test('rejected blank page is not completed and same page can retry', () {
      final fixture = _FlowFixture();
      final rejected = fixture.resultForPage(0, questions: [_blankQuestion()]);

      expect(
        fixture.flow.handleCoordinatorState(_completed(rejected)),
        ScannerValidationFlowAction.resultRejected,
      );
      expect(fixture.flow.session.completedPageCount, 0);
      expect(fixture.flow.reviewResult, isNull);
      expect(fixture.flow.acceptanceRejection, isNotNull);

      final corrected = fixture.resultForPage(0);
      expect(
        fixture.flow.handleCoordinatorState(_completed(corrected)),
        ScannerValidationFlowAction.resultRecorded,
      );
      expect(fixture.flow.session.completedPageCount, 1);
      expect(fixture.flow.reviewResult, same(corrected));
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

  testWidgets('successful review keeps scanner diagnostics accessible', (
    tester,
  ) async {
    final fixture = _FlowFixture();
    final result = fixture.resultForPage(0);
    fixture.flow.handleCoordinatorState(_completed(result));
    var opens = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ScannerReviewStateView(
          session: fixture.flow.session,
          reviewResult: fixture.flow.reviewResult,
          onContinue: () {},
          onShowDiagnostics: () => opens++,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('review-scanner-diagnostics')));
    expect(opens, 1);
  });

  testWidgets('rejected capture card exposes debug details before retry', (
    tester,
  ) async {
    var retries = 0;
    var diagnostics = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScannerFailureCard(
            feedback: const ScannerUserFeedback(
              kind: ScannerFailureKind.recoverable,
              title: 'Alignment failed validation',
              description: 'Keep markers sharp.',
              actionLabel: 'Scan Again',
            ),
            onAction: () => retries++,
            onShowDiagnostics: () => diagnostics++,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('rejection-scanner-diagnostics')));
    expect(diagnostics, 1);
    expect(retries, 0);
  });

  testWidgets('recorded confirmation waits for packet persistence', (
    tester,
  ) async {
    final fixture = _FlowFixture();
    final page = fixture.flow.session.pages.first;
    final result = fixture.resultForPage(
      0,
      packetIdentity: PacketPageIdentity(
        packetId: PacketId('PK000001'),
        templateId: fixture.flow.session.artifact.templateId,
        templateVersion: fixture.flow.session.artifact.templateVersion,
        pageId: page.pageId,
        pageIndex: 0,
        totalPages: fixture.flow.session.pages.length,
        identityMarkerIds: page.markerRegions
            .map((region) => region.markerId)
            .toList(),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ScannerPageResultScreen(
          session: fixture.flow.session,
          result: result,
          onContinue: () {},
        ),
      ),
    );

    expect(find.byKey(const Key('scan-recording-pending')), findsOneWidget);
    expect(find.byKey(const Key('scan-recording-confirmed')), findsNothing);
  });

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

  testWidgets('final multi-page review exposes the Page 2 duplicate check', (
    tester,
  ) async {
    final fixture = _FlowFixture(multiPage: true);
    for (final index in const [1, 0]) {
      fixture.flow.handleCoordinatorState(
        _completed(fixture.resultForPage(index)),
      );
      fixture.flow.continueAfterReview();
    }
    final finalResult = fixture.resultForPage(2);
    fixture.flow.handleCoordinatorState(_completed(finalResult));

    await tester.pumpWidget(
      MaterialApp(
        home: ScannerReviewStateView(
          session: fixture.flow.session,
          reviewResult: fixture.flow.reviewResult,
          onContinue: () {},
        ),
      ),
    );

    expect(find.text('Check duplicate Page 2'), findsOneWidget);
    expect(find.byKey(const Key('p13-9-validation-summary')), findsOneWidget);
    expect(find.textContaining('3/3 unique pages'), findsOneWidget);
  });

  testWidgets('known multi-page selection shows the required scan order', (
    tester,
  ) async {
    final repository = InMemoryPublishedTemplateArtifactRepository();
    final inputs = buildP11ScannerValidationSheetInputs();
    final published = await PublishedTemplateArtifactService(
      repository: repository,
      pdfRenderer: (_, _) async =>
          EngineResult.success(Uint8List.fromList([37, 80, 68, 70, 45])),
    ).publish(draft: inputs.template, layoutConfig: LayoutConfig.a4Default());
    expect(published.isSuccess, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: RealScannerSelectionScreen(
          resolver: PublishedScannerResolver(artifactRepository: repository),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Page 2 -> Page 1 -> Page 3 -> Page 2'),
      findsOne,
    );
    expect(find.textContaining('rejected as a duplicate'), findsOne);
    final diagnostics = tester.widget<OutlinedButton>(
      find.byKey(const Key('open-roi-diagnostics')),
    );
    expect(
      find.byKey(const Key('open-bundled-failed-scan-replay')),
      findsOneWidget,
    );
    expect(diagnostics.onPressed, isNotNull);
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
  _FlowFixture({bool multiPage = false}) {
    final inputs = buildP11ScannerValidationSheetInputs();
    final artifact = PublishedScannerArtifact(
      template: inputs.template,
      layout: inputs.layout,
    );
    final session = ScannerValidationSession.start(
      artifact: artifact,
      multiPageValidationPlan: multiPage
          ? buildP13_9MultiPageValidationPlan(artifact)
          : null,
    );
    flow = ScannerValidationFlowController(
      session: session,
      initialCameraState: _tracking(),
    );
  }

  late final ScannerValidationFlowController flow;

  ScanResult resultForPage(
    int index, {
    List<QuestionClassification> questions = const [],
    PacketPageIdentity? packetIdentity,
  }) {
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
      questions: questions,
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
        summary: ScanSummary(
          totalQuestions: questions.length,
          marked: questions.where((q) => q.state == MarkState.marked).length,
          blank: questions.where((q) => q.state == MarkState.blank).length,
          multiple: questions
              .where((q) => q.state == MarkState.multiple)
              .length,
          ambiguous: questions
              .where((q) => q.state == MarkState.ambiguous)
              .length,
          invalid: questions.where((q) => q.state == MarkState.invalid).length,
          requiredBlank: 0,
          measuredBubbles: 0,
        ),
      ),
      packetIdentity: packetIdentity,
    );
  }
}

QuestionClassification _blankQuestion() => QuestionClassification(
  questionId: QuestionId('blank-question'),
  questionNumber: 1,
  questionType: QuestionType.singleChoice,
  state: MarkState.blank,
  selectedOptionIds: const [],
  numericSelection: null,
  bubbleDecisions: const [],
  diagnostics: const QuestionClassificationDiagnostics(
    topScore: 0,
    secondScore: 0,
    scoreGap: 0,
    reason: ClassificationReason.clearBlank,
  ),
);

CameraScanState _completed(ScanResult result) => CameraScanState(
  phase: CameraScanPhase.scanCompleted,
  cameraState: const CameraEngineState.uninitialized(),
  result: result,
);

CameraScanState _tracking() => const CameraScanState(
  phase: CameraScanPhase.tracking,
  cameraState: CameraEngineState.uninitialized(),
);
