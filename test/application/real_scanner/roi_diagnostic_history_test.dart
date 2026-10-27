import 'dart:typed_data';

import 'package:capstone_development/application/real_scanner/roi_diagnostic_history.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessed_page.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessing_config.dart';
import 'package:capstone_development/engines/recognition/domain/bubble_measurement.dart';
import 'package:capstone_development/engines/recognition/domain/bubble_measurement_config.dart';
import 'package:capstone_development/engines/recognition/domain/canonical_bubble_roi.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification_config.dart';
import 'package:capstone_development/engines/scanner/domain/scan_result.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_diagnostic_snapshot.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('history retains only the latest five numeric evidence scans', () {
    var history = RoiDiagnosticHistory();
    for (var index = 1; index <= 7; index++) {
      history = history.record(
        _snapshot(
          index: index,
          fill: index / 10,
          normalized: index / 20,
          contrast: index * 5,
          score: index / 10,
          category: BubbleEvidenceCategory.possibleMark,
          questionState: MarkState.marked,
        ),
      );
    }

    expect(history.scans, hasLength(5));
    expect(history.scans.map((scan) => scan.scanSequenceIndex), [
      3,
      4,
      5,
      6,
      7,
    ]);
    expect(history.retainedCanonicalImageByteCount, 0);
    expect(history.scans.first.bubbles.single.fillRatio, 0.3);
    expect(history.scans.last.bubbles.single.fillRatio, 0.7);
  });

  test('summary calculates ranges and category/question-state changes', () {
    var history = RoiDiagnosticHistory();
    history = history.record(
      _snapshot(
        index: 1,
        fill: 0.1,
        normalized: 0.2,
        contrast: 10,
        score: 0.3,
        category: BubbleEvidenceCategory.clearBlank,
        questionState: MarkState.blank,
      ),
    );
    history = history.record(
      _snapshot(
        index: 2,
        fill: 0.4,
        normalized: 0.5,
        contrast: 40,
        score: 0.6,
        category: BubbleEvidenceCategory.possibleMark,
        questionState: MarkState.ambiguous,
      ),
    );
    history = history.record(
      _snapshot(
        index: 3,
        fill: 0.8,
        normalized: 0.7,
        contrast: 80,
        score: 0.9,
        category: BubbleEvidenceCategory.strongMark,
        questionState: MarkState.marked,
      ),
    );

    final summary = history.summarize(_identity)!;
    expect(summary.scanCount, 3);
    expect(summary.minimumFillRatio, 0.1);
    expect(summary.maximumFillRatio, 0.8);
    expect(summary.minimumNormalizedDarkness, 0.2);
    expect(summary.maximumNormalizedDarkness, 0.7);
    expect(summary.minimumDarknessContrast, 10);
    expect(summary.maximumDarknessContrast, 80);
    expect(summary.minimumCombinedScore, 0.3);
    expect(summary.maximumCombinedScore, 0.9);
    expect(summary.minimumCoverageScore, 0.1);
    expect(summary.maximumCoverageScore, 0.8);
    expect(summary.minimumDistributionScore, 0.67);
    expect(summary.maximumDistributionScore, 0.67);
    expect(summary.categoryChanges, 2);
    expect(summary.stateChanges, 2);
  });

  test('diagnostic JSON exposes identity, geometry, evidence, and timings', () {
    final json = _snapshot(
      index: 4,
      fill: 0.4,
      normalized: 0.5,
      contrast: 40,
      score: 0.6,
      category: BubbleEvidenceCategory.possibleMark,
      questionState: MarkState.marked,
    ).toJson();

    expect(json['templateId'], 'p11-1-scanner-validation');
    expect(json['templateVersion'], 1);
    expect(json['pageId'], 'p11-1-scanner-validation-v1-p1');
    expect(json['scanSequenceIndex'], 4);
    final bubbles = json['bubbles']! as List<Object?>;
    final bubble = bubbles.single! as Map<String, Object?>;
    expect(bubble['questionId'], 'q4');
    expect(bubble['questionNumber'], 1);
    expect(bubble['optionId'], 'q4-2');
    expect(bubble['fillRatio'], 0.4);
    expect(bubble['coverageScore'], 0.4);
    expect(bubble['darknessScore'], 0.5);
    expect(bubble['distributionScore'], 0.67);
    expect(bubble['combinedMarkScore'], 0.6);
    expect(bubble['combinedScore'], 0.6);
    expect(bubble['evidenceCategory'], 'possibleMark');
    expect(bubble['sampledInteriorPixelCount'], 100);
    expect(bubble['sampledBaselinePixelCount'], 120);
    expect(bubble['clipping'], 'none');
    final classificationConfig =
        json['classificationConfig']! as Map<String, Object?>;
    expect(classificationConfig['minimumCombinedMarkScore'], 0.35);
    final measurementConfig =
        json['measurementConfig']! as Map<String, Object?>;
    expect(measurementConfig['interiorRadiusRatio'], 0.68);
    final preprocessingConfig =
        json['preprocessingConfig']! as Map<String, Object?>;
    expect(preprocessingConfig['adaptiveThresholdBlockSize'], 15);
    final alignment = json['alignment']! as Map<String, Object?>;
    expect(alignment['homographySelectionPolicy'], 'fourPointBaseline');
    expect(alignment['reprojectionScaleFactor'], 1);
    final questions = json['questions']! as List<Object?>;
    final question = questions.single! as Map<String, Object?>;
    expect(question['questionNumber'], 1);
    expect(question['topCandidate'], 'q4-2');
    expect(question['reason'], 'isolatedMark');
  });
}

final _identity = DiagnosticBubbleIdentity(
  questionId: QuestionId('q4'),
  optionId: OptionId('q4-2'),
  numericColumnIndex: null,
  numericDigitValue: null,
);

ScannerDiagnosticSnapshot _snapshot({
  required int index,
  required double fill,
  required double normalized,
  required double contrast,
  required double score,
  required BubbleEvidenceCategory category,
  required MarkState questionState,
}) {
  final measurement = BubbleMeasurement(
    pageId: _pageId,
    questionId: _identity.questionId,
    optionId: _identity.optionId,
    numericColumnIndex: null,
    numericDigitValue: null,
    roi: CanonicalBubbleRoi(
      center: ImagePoint(20, 30),
      printedRadius: 5,
      interiorRadius: 3.4,
      baselineInnerRadius: 6.25,
      baselineOuterRadius: 10,
    ),
    sampledInteriorPixelCount: 100,
    sampledBaselinePixelCount: 120,
    interiorMeanIntensity: 180,
    interiorMedianIntensity: 175,
    localBaselineIntensity: 220,
    darknessContrast: contrast,
    normalizedDarkness: normalized,
    foregroundPixelCount: (fill * 100).round(),
    fillRatio: fill,
    distributionScore: 0.67,
    quality: const BubbleMeasurementQuality(
      interiorValidSampleRatio: 1,
      baselineValidSampleRatio: 1,
      clipping: BubbleRoiClipping.none,
      baselineForegroundRatio: 0.02,
      localBaselineReliable: true,
      neighborMaskedPixelCount: 2,
    ),
  );
  final decision = BubbleMarkDecision(
    pageId: _pageId,
    questionId: _identity.questionId,
    optionId: _identity.optionId,
    numericColumnIndex: null,
    numericDigitValue: null,
    fillRatio: fill,
    normalizedDarkness: normalized,
    darknessContrast: contrast,
    coverageScore: fill,
    normalizedDarknessComponent: normalized,
    darknessContrastComponent: contrast / 100,
    darknessScore: normalized,
    distributionScore: 0.67,
    combinedMarkScore: score,
    category: category,
    state: switch (category) {
      BubbleEvidenceCategory.strongMark => BubbleDecisionState.selected,
      BubbleEvidenceCategory.clearBlank => BubbleDecisionState.notSelected,
      BubbleEvidenceCategory.invalid => BubbleDecisionState.invalid,
      _ => BubbleDecisionState.uncertain,
    },
    qualityUsable: true,
    interiorMeanIntensity: 180,
    interiorMedianIntensity: 175,
    localBaselineIntensity: 220,
    foregroundPixelCount: (fill * 100).round(),
    quality: measurement.quality,
  );
  final classification = PageClassificationResult(
    pageId: _pageId,
    questions: [
      QuestionClassification(
        questionId: _identity.questionId,
        questionNumber: 1,
        questionType: QuestionType.singleChoice,
        state: questionState,
        selectedOptionIds: questionState == MarkState.marked
            ? [_identity.optionId!]
            : const [],
        numericSelection: null,
        bubbleDecisions: [decision],
        diagnostics: const QuestionClassificationDiagnostics(
          topScore: 0.6,
          secondScore: 0,
          scoreGap: 0.6,
          reason: ClassificationReason.isolatedMark,
        ),
      ),
    ],
  );
  final result = ScanResult(
    templateId: _templateId,
    templateVersion: _version,
    pageId: _pageId,
    questions: classification.questions,
    pageState: ScanPageState.accepted,
    reviewReasons: const [],
    reviewQuestionIds: const [],
    diagnostics: ScanDiagnostics(
      totalProcessingDuration: const Duration(milliseconds: 12),
      stageDurations: const ScanStageDurations(
        alignment: Duration(milliseconds: 4),
        preprocessing: Duration(milliseconds: 3),
        measurement: Duration(milliseconds: 2),
        classification: Duration(milliseconds: 2),
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
        sourceStatistics: _statistics,
        normalizedStatistics: _statistics,
        binaryForegroundRatio: 0.1,
        processingDuration: Duration.zero,
      ),
      summary: const ScanSummary(
        totalQuestions: 1,
        marked: 1,
        blank: 0,
        multiple: 0,
        ambiguous: 0,
        invalid: 0,
        requiredBlank: 0,
        measuredBubbles: 1,
      ),
    ),
  );
  return ScannerDiagnosticSnapshot(
    templateId: _templateId,
    templateVersion: _version,
    pageId: _pageId,
    canonicalSize: ImageSize(width: 2, height: 2),
    canonicalImageFormat: ScannerDiagnosticImageFormat.grayscale8,
    canonicalImageBytes: Uint8List.fromList([0, 64, 128, 255]),
    homography: HomographyMatrix(const [1, 0, 0, 0, 1, 0, 0, 0, 1]),
    measurements: BubbleMeasurementSet(
      pageId: _pageId,
      measurements: [measurement],
    ),
    classification: classification,
    result: result,
    preprocessingConfig: const PreprocessingConfig(),
    measurementConfig: const BubbleMeasurementConfig(),
    classificationConfig: const MarkClassificationConfig(),
    scanSequenceIndex: index,
  );
}

final _templateId = TemplateId('p11-1-scanner-validation');
final _version = TemplateVersion(1);
final _pageId = PageId('p11-1-scanner-validation-v1-p1');

const _statistics = ImageStatistics(
  meanIntensity: 200,
  intensityStandardDeviation: 20,
  minimumIntensity: 0,
  maximumIntensity: 255,
  darkPixelRatio: 0.1,
  brightPixelRatio: 0.8,
);
