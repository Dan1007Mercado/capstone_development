import 'package:capstone_development/application/real_scanner/physical_validation_recorder.dart';
import 'package:capstone_development/application/real_scanner/android_omr_acceptance.dart';
import 'package:capstone_development/application/real_scanner/published_scanner_resolver.dart';
import 'package:capstone_development/application/real_scanner/scanner_validation_session.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/debug/p13_6_dense_validation_sheet.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessed_page.dart';
import 'package:capstone_development/engines/recognition/domain/bubble_measurement.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification.dart';
import 'package:capstone_development/engines/scanner/domain/scan_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'dense known-answer plan records complete bubble evidence and metrics',
    () {
      final inputs = buildP13_6DenseValidationInputs();
      final plan = buildP13_8DenseKnownAnswerPlan(inputs.template)!;
      final result = _result(plan, inputs.layout.pages.single);

      final report = PhysicalValidationReport.record(
        plan: plan,
        results: [result],
      );

      expect(report.summary.totalQuestions, 40);
      expect(report.summary.correct, 40);
      expect(report.summary.wrong, 0);
      expect(report.summary.blankAccuracy, 1);
      expect(report.summary.markedAccuracy, 1);
      expect(report.summary.falsePositiveMarks, 0);
      expect(report.summary.falseBlank, 0);
      expect(report.summary.wrongConfidentCount, 0);
      expect(report.summary.accuracyPercentage, 100);
      expect(
        report.summary.averageProcessingDuration,
        const Duration(milliseconds: 25),
      );

      final q1 = report.questions.first;
      expect(q1.expected.answerLabel, 'dense-q01-2');
      expect(q1.detectedAnswer, 'dense-q01-2');
      expect(q1.bubbles, hasLength(4));
      final json = q1.bubbles.first.toJson();
      expect(json, containsPair('templateId', inputs.template.id.value));
      expect(json, containsPair('expectedState', 'marked'));
      expect(json, containsPair('fillRatio', 0.02));
      expect(json, containsPair('evidenceCategory', 'clearBlank'));
      expect(json, contains('baselineForegroundRatio'));
      expect(json, contains('localBaselineReliable'));
      expect(json, contains('interiorValidSampleRatio'));
      expect(json, contains('baselineValidSampleRatio'));
      expect(json, contains('stageTimingsMs'));
      expect(q1.bubbles[1].toJson(), containsPair('fillRatio', 0.8));
      expect(
        q1.bubbles[1].toJson(),
        containsPair('evidenceCategory', 'strongMark'),
      );
    },
  );

  test(
    'summary separates ambiguity, false marks, false blanks, and confident errors',
    () {
      final inputs = buildP13_6DenseValidationInputs();
      final plan = buildP13_8DenseKnownAnswerPlan(inputs.template)!;
      final overrides = <String, MarkState>{
        'dense-q01': MarkState.blank,
        'dense-q02': MarkState.marked,
        'dense-q03': MarkState.ambiguous,
      };

      final report = PhysicalValidationReport.record(
        plan: plan,
        results: [
          _result(plan, inputs.layout.pages.single, overrides: overrides),
        ],
      );

      expect(report.summary.correct, 37);
      expect(report.summary.wrong, 3);
      expect(report.summary.ambiguous, 1);
      expect(report.summary.falsePositiveMarks, 1);
      expect(report.summary.falseBlank, 1);
      expect(report.summary.wrongConfidentCount, 2);
      expect(report.summary.accuracyPercentage, 92.5);
      expect(report.summary.ambiguousPercentage, 2.5);
    },
  );

  test('scanner validation session retains and exposes the local report', () {
    final inputs = buildP13_6DenseValidationInputs();
    final plan = buildP13_8DenseKnownAnswerPlan(inputs.template)!;
    final session = ScannerValidationSession.start(
      artifact: PublishedScannerArtifact(
        template: inputs.template,
        layout: inputs.layout,
      ),
      validationPlan: plan,
    );

    final recorded = session.recordResult(
      _result(plan, inputs.layout.pages.single),
    );

    expect(recorded.isSuccess, isTrue);
    expect(recorded.value.validationReport?.summary.correct, 40);
    final continued = recorded.value.continueAfterReview();
    expect(continued.isSuccess, isTrue);
    expect(continued.value.validationPlan, same(plan));
    expect(continued.value.validationReport?.summary.correct, 40);
  });

  test('known-answer plans round trip for local import', () {
    final inputs = buildP13_6DenseValidationInputs();
    final plan = buildP13_8DenseKnownAnswerPlan(inputs.template)!;

    final restored = PhysicalValidationPlan.fromJson(plan.toJson());

    expect(restored.templateId, plan.templateId);
    expect(restored.templateVersion, plan.templateVersion);
    expect(restored.answersByQuestion.length, plan.answersByQuestion.length);
    expect(restored.answersByQuestion[QuestionId('dense-q01')]!.optionIds, [
      OptionId('dense-q01-2'),
    ]);
  });

  test(
    'Android acceptance summary requires the complete 25-attempt matrix',
    () {
      final inputs = buildP13_6DenseValidationInputs();
      final plan = buildP13_8DenseKnownAnswerPlan(inputs.template)!;
      final result = _result(plan, inputs.layout.pages.single);
      final attempts = [
        for (final scenario in AndroidOmrScenario.values)
          for (var attempt = 1; attempt <= 5; attempt++)
            AndroidOmrAcceptanceAttempt(
              scenario: scenario,
              attemptNumber: attempt,
              deviceModel: 'Infinix X6711',
              startedAtUtc: DateTime.utc(2026, 10, 27),
              cameraCaptureDuration: const Duration(milliseconds: 35),
              duration: Duration(milliseconds: 100 + attempt),
              expectedPlan: plan,
              result: result,
            ),
      ];

      final report = AndroidOmrAcceptanceReport.build(attempts);

      expect(report.summary['matrixComplete'], isTrue);
      expect(report.summary['acceptedAttempts'], 25);
      expect(report.summary['acceptedQuestionAccuracy'], 1);
      expect(report.summary['latencyP95Ms'], 105);
      expect(report.summary['rejectedAttempts'], 0);
    },
  );
}

ScanResult _result(
  PhysicalValidationPlan plan,
  PageLayout page, {
  Map<String, MarkState> overrides = const {},
}) {
  final classifications = <QuestionClassification>[];
  for (final region in page.questionRegions) {
    final expected = plan.answersByQuestion[region.questionId]!;
    final state = overrides[region.questionId.value] ?? expected.state;
    final List<OptionId> selected = state == MarkState.marked
        ? (expected.optionIds.isNotEmpty
              ? expected.optionIds
              : [region.bubbleRegions.first.optionId!])
        : const [];
    final decisions = [
      for (final bubble in region.bubbleRegions)
        _decision(
          bubble.pageId,
          bubble.questionId,
          bubble.optionId,
          selected.contains(bubble.optionId),
        ),
    ];
    classifications.add(
      QuestionClassification(
        questionId: region.questionId,
        questionNumber: region.questionNumber,
        questionType: region.questionType,
        state: state,
        selectedOptionIds: state == MarkState.marked ? selected : const [],
        numericSelection: null,
        bubbleDecisions: decisions,
        diagnostics: QuestionClassificationDiagnostics(
          topScore: state == MarkState.marked ? 0.9 : 0.1,
          secondScore: 0.1,
          scoreGap: state == MarkState.marked ? 0.8 : 0,
          reason: state == MarkState.marked
              ? ClassificationReason.isolatedMark
              : state == MarkState.blank
              ? ClassificationReason.clearBlank
              : ClassificationReason.uncertainEvidence,
        ),
      ),
    );
  }
  const statistics = ImageStatistics(
    meanIntensity: 220,
    intensityStandardDeviation: 15,
    minimumIntensity: 0,
    maximumIntensity: 255,
    darkPixelRatio: 0.05,
    brightPixelRatio: 0.9,
  );
  return ScanResult(
    templateId: plan.templateId,
    templateVersion: plan.templateVersion,
    pageId: page.pageId,
    questions: classifications,
    pageState: ScanPageState.accepted,
    reviewReasons: const [],
    reviewQuestionIds: const [],
    diagnostics: ScanDiagnostics(
      totalProcessingDuration: const Duration(milliseconds: 25),
      stageDurations: const ScanStageDurations(
        alignment: Duration(milliseconds: 8),
        preprocessing: Duration(milliseconds: 5),
        measurement: Duration(milliseconds: 7),
        classification: Duration(milliseconds: 3),
        validation: Duration(milliseconds: 1),
      ),
      alignment: PageAlignmentDiagnostics(
        expectedMarkerIds: const [10, 11, 12, 13],
        detectedMarkerIds: const [10, 11, 12, 13],
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
        totalQuestions: classifications.length,
        marked: classifications
            .where((q) => q.state == MarkState.marked)
            .length,
        blank: classifications.where((q) => q.state == MarkState.blank).length,
        multiple: 0,
        ambiguous: classifications
            .where((q) => q.state == MarkState.ambiguous)
            .length,
        invalid: 0,
        requiredBlank: 0,
        measuredBubbles: page.bubbleRegions.length,
      ),
    ),
  );
}

BubbleMarkDecision _decision(
  PageId pageId,
  QuestionId questionId,
  OptionId? optionId,
  bool selected,
) => BubbleMarkDecision(
  pageId: pageId,
  questionId: questionId,
  optionId: optionId,
  numericColumnIndex: null,
  numericDigitValue: null,
  fillRatio: selected ? 0.8 : 0.02,
  normalizedDarkness: selected ? 0.5 : 0.02,
  darknessContrast: selected ? 90 : 3,
  coverageScore: selected ? 1 : 0.04,
  normalizedDarknessComponent: selected ? 1 : 0.04,
  darknessContrastComponent: selected ? 1 : 0.03,
  darknessScore: selected ? 1 : 0.035,
  distributionScore: selected ? 1 : 0,
  combinedMarkScore: selected ? 0.9 : 0.1,
  category: selected
      ? BubbleEvidenceCategory.strongMark
      : BubbleEvidenceCategory.clearBlank,
  state: selected
      ? BubbleDecisionState.selected
      : BubbleDecisionState.notSelected,
  qualityUsable: true,
  interiorMeanIntensity: selected ? 100 : 235,
  interiorMedianIntensity: selected ? 95 : 238,
  localBaselineIntensity: 240,
  foregroundPixelCount: selected ? 80 : 2,
  quality: const BubbleMeasurementQuality(
    interiorValidSampleRatio: 1,
    baselineValidSampleRatio: 1,
    clipping: BubbleRoiClipping.none,
    baselineForegroundRatio: 0.02,
    localBaselineReliable: true,
    neighborMaskedPixelCount: 0,
  ),
);
