import 'dart:math' as math;

import '../domain/bubble_measurement.dart';
import '../domain/mark_classification.dart';
import '../domain/mark_classification_config.dart';

final class BubbleEvidenceEvaluator {
  const BubbleEvidenceEvaluator();

  BubbleMarkDecision evaluate(
    BubbleMeasurement measurement,
    MarkClassificationConfig config,
  ) {
    final fillComponent = _component(
      measurement.fillRatio,
      config.strongFillRatio,
    );
    final normalizedDarknessComponent = _component(
      measurement.normalizedDarkness,
      config.strongNormalizedDarkness,
    );
    final darknessContrastComponent = _component(
      measurement.darknessContrast,
      config.strongDarknessContrast,
    );
    final combinedScore =
        fillComponent * config.fillWeight +
        normalizedDarknessComponent * config.normalizedDarknessWeight +
        darknessContrastComponent * config.darknessContrastWeight;

    final quality = measurement.quality;
    final severeQuality =
        quality.interiorValidSampleRatio <
            config.severeMinimumValidSampleRatio ||
        quality.baselineValidSampleRatio <
            config.severeMinimumValidSampleRatio ||
        quality.baselineForegroundRatio > config.severeBaselineForegroundRatio;
    final unreliableQuality =
        quality.interiorValidSampleRatio < config.minimumValidSampleRatio ||
        quality.baselineValidSampleRatio < config.minimumValidSampleRatio ||
        quality.baselineForegroundRatio >
            config.maximumBaselineForegroundRatio ||
        (config.requireReliableBaseline && !quality.localBaselineReliable);

    final minimumSignals = [
      measurement.fillRatio >= config.minimumFillRatio,
      measurement.normalizedDarkness >= config.minimumNormalizedDarkness,
      measurement.darknessContrast >= config.minimumDarknessContrast,
    ].where((passes) => passes).length;
    final binaryStrong = measurement.fillRatio >= config.strongFillRatio;
    final grayscaleSignals = [
      measurement.normalizedDarkness >= config.minimumNormalizedDarkness,
      measurement.darknessContrast >= config.minimumDarknessContrast,
    ].where((passes) => passes).length;

    final category = severeQuality
        ? BubbleEvidenceCategory.invalid
        : unreliableQuality
        ? BubbleEvidenceCategory.unreliable
        : binaryStrong && grayscaleSignals == 0
        ? BubbleEvidenceCategory.conflicting
        : combinedScore >= config.strongCombinedScore && minimumSignals >= 2
        ? BubbleEvidenceCategory.strongMark
        : combinedScore >= config.minimumCombinedScore && minimumSignals >= 2
        ? BubbleEvidenceCategory.possibleMark
        : combinedScore < config.minimumCombinedScore && minimumSignals == 0
        ? BubbleEvidenceCategory.clearBlank
        : BubbleEvidenceCategory.conflicting;
    final state = switch (category) {
      BubbleEvidenceCategory.strongMark => BubbleDecisionState.selected,
      BubbleEvidenceCategory.clearBlank => BubbleDecisionState.notSelected,
      BubbleEvidenceCategory.invalid => BubbleDecisionState.invalid,
      _ => BubbleDecisionState.uncertain,
    };
    return BubbleMarkDecision(
      pageId: measurement.pageId,
      questionId: measurement.questionId,
      optionId: measurement.optionId,
      numericColumnIndex: measurement.numericColumnIndex,
      numericDigitValue: measurement.numericDigitValue,
      fillRatio: measurement.fillRatio,
      normalizedDarkness: measurement.normalizedDarkness,
      darknessContrast: measurement.darknessContrast,
      fillComponent: fillComponent,
      normalizedDarknessComponent: normalizedDarknessComponent,
      darknessContrastComponent: darknessContrastComponent,
      combinedScore: combinedScore,
      category: category,
      state: state,
      qualityUsable: !severeQuality && !unreliableQuality,
    );
  }

  double _component(double value, double strongThreshold) =>
      math.max(0.0, math.min(1.0, value / strongThreshold));
}
