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
    final coverageScore = _component(
      measurement.fillRatio,
      config.strongMarkCoverage,
    );
    final normalizedDarknessComponent = _component(
      measurement.normalizedDarkness,
      config.strongNormalizedDarkness,
    );
    final darknessContrastComponent = _component(
      measurement.darknessContrast,
      config.strongDarknessContrast,
    );
    final darknessScore =
        normalizedDarknessComponent * config.normalizedDarknessShare +
        darknessContrastComponent * (1 - config.normalizedDarknessShare);
    final combinedMarkScore =
        coverageScore * config.coverageWeight +
        darknessScore * config.darknessWeight +
        measurement.distributionScore * config.distributionWeight;

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
      measurement.fillRatio >= config.minimumMarkCoverage,
      measurement.normalizedDarkness >= config.minimumNormalizedDarkness,
      measurement.darknessContrast >= config.minimumDarknessContrast,
    ].where((passes) => passes).length;
    final binaryStrong = measurement.fillRatio >= config.strongMarkCoverage;
    final normalizedDarknessStrong =
        measurement.normalizedDarkness >= config.strongNormalizedDarkness;
    final darknessContrastStrong =
        measurement.darknessContrast >= config.strongDarknessContrast;
    final unsupportedStrongSignal =
        minimumSignals < 2 &&
        (binaryStrong || normalizedDarknessStrong || darknessContrastStrong);
    final credibleMark =
        combinedMarkScore >= config.minimumCombinedMarkScore &&
        darknessScore >= config.minimumDarknessEvidence &&
        minimumSignals >= 2 &&
        (measurement.fillRatio >= config.minimumMarkCoverage ||
            measurement.distributionScore >=
                config.minimumDistributedMarkScore);
    final strongMark =
        credibleMark &&
        combinedMarkScore >= config.strongCombinedMarkScore &&
        measurement.fillRatio >= config.multipleMarkMinimumCoverage;
    final conservativeBlank =
        measurement.fillRatio <= config.blankMaximumCoverage &&
        darknessScore < config.minimumDarknessEvidence;

    final category = severeQuality
        ? BubbleEvidenceCategory.invalid
        : unreliableQuality
        ? BubbleEvidenceCategory.unreliable
        : unsupportedStrongSignal
        ? BubbleEvidenceCategory.conflicting
        : strongMark
        ? BubbleEvidenceCategory.strongMark
        : credibleMark
        ? BubbleEvidenceCategory.possibleMark
        : measurement.fillRatio <= config.blankMaximumCoverage &&
              darknessScore >= config.minimumDarknessEvidence
        ? BubbleEvidenceCategory.conflicting
        : conservativeBlank || minimumSignals < 2
        ? BubbleEvidenceCategory.clearBlank
        : combinedMarkScore >= config.minimumCombinedMarkScore
        ? BubbleEvidenceCategory.conflicting
        : BubbleEvidenceCategory.clearBlank;
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
      coverageScore: coverageScore,
      normalizedDarknessComponent: normalizedDarknessComponent,
      darknessContrastComponent: darknessContrastComponent,
      darknessScore: darknessScore,
      distributionScore: measurement.distributionScore,
      combinedMarkScore: combinedMarkScore,
      category: category,
      state: state,
      qualityUsable: !severeQuality && !unreliableQuality,
      interiorMeanIntensity: measurement.interiorMeanIntensity,
      interiorMedianIntensity: measurement.interiorMedianIntensity,
      localBaselineIntensity: measurement.localBaselineIntensity,
      foregroundPixelCount: measurement.foregroundPixelCount,
      quality: measurement.quality,
    );
  }

  double _component(double value, double strongThreshold) =>
      math.max(0.0, math.min(1.0, value / strongThreshold));
}
