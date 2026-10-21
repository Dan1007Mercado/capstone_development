import 'package:capstone_development/debug/p11_1_scanner_validation_sheet.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/layout/domain/layout_regions.dart';
import 'package:capstone_development/engines/recognition/application/mark_classification_engine.dart';
import 'package:capstone_development/engines/recognition/domain/bubble_measurement.dart';
import 'package:capstone_development/engines/recognition/domain/canonical_bubble_roi.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Q5 Q6 Q7 share authoritative PageLayout bubble geometry', () {
    final inputs = buildP11ScannerValidationSheetInputs();
    final page = inputs.layout.pages[1];
    final regions = {
      for (final region in page.questionRegions)
        region.questionId.value: region,
    };

    expect(regions.keys, containsAll(const ['q5', 'q6', 'q7']));
    expect(regions['q5']!.questionType, QuestionType.singleChoice);
    expect(regions['q6']!.questionType, QuestionType.multipleChoice);
    expect(regions['q7']!.questionType, QuestionType.multipleChoice);
    expect(regions['q5']!.bubbleRegions, hasLength(4));
    expect(regions['q6']!.bubbleRegions, hasLength(5));
    expect(regions['q7']!.bubbleRegions, hasLength(5));

    for (final id in const ['q5', 'q6', 'q7']) {
      final region = regions[id]!;
      final authoritative = page.bubbleRegions
          .where((bubble) => bubble.questionId == region.questionId)
          .toList(growable: false);
      expect(region.bubbleRegions, orderedEquals(authoritative));
      for (var index = 0; index < region.bubbleRegions.length; index++) {
        expect(region.bubbleRegions[index], same(authoritative[index]));
        expect(region.bubbleRegions[index].pageId, page.pageId);
        expect(region.bubbleRegions[index].isOptionTarget, isTrue);
      }
    }
  });

  test('physical-style Q6 Q7 marks classify independently', () {
    final inputs = buildP11ScannerValidationSheetInputs();
    final page = inputs.layout.pages[1];
    final measurements = <BubbleMeasurement>[];

    for (var index = 0; index < page.bubbleRegions.length; index++) {
      final bubble = page.bubbleRegions[index];
      final questionBubbleIndex = page.bubbleRegions
          .where((candidate) => candidate.questionId == bubble.questionId)
          .toList(growable: false)
          .indexOf(bubble);
      final evidence = switch ((bubble.questionId.value, questionBubbleIndex)) {
        ('q5', 1) => _PhysicalEvidence.darkPen,
        ('q6', 0) => _PhysicalEvidence.darkPen,
        ('q6', 2) => _PhysicalEvidence.xMark,
        ('q7', 1) => _PhysicalEvidence.partialFill,
        ('q7', 3) => _PhysicalEvidence.moderatePencil,
        _ => _PhysicalEvidence.printedOutline,
      };
      measurements.add(_measurement(bubble, evidence, index));
    }

    final result = const MarkClassificationEngine().classify(
      inputs.template,
      page,
      BubbleMeasurementSet(pageId: page.pageId, measurements: measurements),
    );
    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    final classifications = {
      for (final question in result.value.questions)
        question.questionId.value: question,
    };

    expect(classifications['q5']!.state, MarkState.marked);
    expect(classifications['q6']!.state, MarkState.marked);
    expect(classifications['q7']!.state, MarkState.marked);
    expect(classifications['q6']!.selectedOptionIds.map((id) => id.value), [
      'q6-1',
      'q6-3',
    ]);
    expect(classifications['q7']!.selectedOptionIds.map((id) => id.value), [
      'q7-2',
      'q7-4',
    ]);
    expect(
      classifications['q7']!.bubbleDecisions[3].category,
      BubbleEvidenceCategory.possibleMark,
    );
    expect(
      classifications['q7']!.bubbleDecisions[3].state,
      BubbleDecisionState.selected,
    );
    expect(
      classifications['q6']!.bubbleDecisions
          .where(
            (decision) =>
                decision.category == BubbleEvidenceCategory.clearBlank,
          )
          .length,
      3,
    );
    expect(classifications['q6']!.state, isNot(MarkState.multiple));
    expect(classifications['q7']!.state, isNot(MarkState.multiple));
  });
}

BubbleMeasurement _measurement(
  BubbleRegion bubble,
  _PhysicalEvidence evidence,
  int index,
) {
  const baseline = 240.0;
  return BubbleMeasurement(
    pageId: bubble.pageId,
    questionId: bubble.questionId,
    optionId: bubble.optionId,
    numericColumnIndex: bubble.numericColumnIndex,
    numericDigitValue: bubble.numericDigitValue,
    roi: CanonicalBubbleRoi(
      center: ImagePoint(index + 10, 10),
      printedRadius: 5,
      interiorRadius: 3.4,
      baselineInnerRadius: 6.25,
      baselineOuterRadius: 10,
    ),
    sampledInteriorPixelCount: 100,
    sampledBaselinePixelCount: 120,
    interiorMeanIntensity: baseline - evidence.contrast,
    interiorMedianIntensity: baseline - evidence.contrast,
    localBaselineIntensity: baseline,
    darknessContrast: evidence.contrast,
    normalizedDarkness: evidence.normalizedDarkness,
    foregroundPixelCount: (evidence.fillRatio * 100).round(),
    fillRatio: evidence.fillRatio,
    quality: _goodQuality,
  );
}

final class _PhysicalEvidence {
  const _PhysicalEvidence({
    required this.fillRatio,
    required this.normalizedDarkness,
    required this.contrast,
  });

  final double fillRatio;
  final double normalizedDarkness;
  final double contrast;

  static const darkPen = _PhysicalEvidence(
    fillRatio: 0.78,
    normalizedDarkness: 0.50,
    contrast: 100,
  );
  static const partialFill = _PhysicalEvidence(
    fillRatio: 0.30,
    normalizedDarkness: 0.24,
    contrast: 48,
  );
  static const xMark = _PhysicalEvidence(
    fillRatio: 0.18,
    normalizedDarkness: 0.38,
    contrast: 78,
  );
  static const moderatePencil = _PhysicalEvidence(
    fillRatio: 0.18,
    normalizedDarkness: 0.17,
    contrast: 25,
  );
  static const printedOutline = _PhysicalEvidence(
    fillRatio: 0.16,
    normalizedDarkness: 0.03,
    contrast: 6,
  );
}

const _goodQuality = BubbleMeasurementQuality(
  interiorValidSampleRatio: 1,
  baselineValidSampleRatio: 1,
  clipping: BubbleRoiClipping.none,
  baselineForegroundRatio: 0.02,
  localBaselineReliable: true,
  neighborMaskedPixelCount: 0,
);
