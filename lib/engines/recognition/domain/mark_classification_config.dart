final class MarkClassificationConfig {
  const MarkClassificationConfig({
    this.minimumFillRatio = 0.12,
    this.strongFillRatio = 0.45,
    this.minimumNormalizedDarkness = 0.08,
    this.strongNormalizedDarkness = 0.30,
    this.minimumDarknessContrast = 12,
    this.strongDarknessContrast = 60,
    this.fillWeight = 0.40,
    this.normalizedDarknessWeight = 0.35,
    this.darknessContrastWeight = 0.25,
    this.minimumCombinedScore = 0.35,
    this.strongCombinedScore = 0.65,
    this.minimumTopSecondGap = 0.12,
    this.maximumBaselineForegroundRatio = 0.35,
    this.severeBaselineForegroundRatio = 0.65,
    this.requireReliableBaseline = true,
    this.minimumValidSampleRatio = 0.90,
    this.severeMinimumValidSampleRatio = 0.75,
  });

  final double minimumFillRatio;
  final double strongFillRatio;
  final double minimumNormalizedDarkness;
  final double strongNormalizedDarkness;
  final double minimumDarknessContrast;
  final double strongDarknessContrast;
  final double fillWeight;
  final double normalizedDarknessWeight;
  final double darknessContrastWeight;
  final double minimumCombinedScore;
  final double strongCombinedScore;
  final double minimumTopSecondGap;
  final double maximumBaselineForegroundRatio;
  final double severeBaselineForegroundRatio;
  final bool requireReliableBaseline;
  final double minimumValidSampleRatio;
  final double severeMinimumValidSampleRatio;

  String? validationMessage() {
    if (!_orderedThresholds(minimumFillRatio, strongFillRatio, maximum: 1)) {
      return 'Fill thresholds must be finite, non-negative, ordered, and at most 1.';
    }
    if (!_orderedThresholds(
      minimumNormalizedDarkness,
      strongNormalizedDarkness,
      maximum: 1,
    )) {
      return 'Normalized-darkness thresholds must be finite and ordered within 0..1.';
    }
    if (!_orderedThresholds(minimumDarknessContrast, strongDarknessContrast)) {
      return 'Darkness-contrast thresholds must be finite, non-negative, and ordered.';
    }
    if (!_unit(minimumCombinedScore) ||
        !_unit(strongCombinedScore) ||
        minimumCombinedScore >= strongCombinedScore ||
        !_unit(minimumTopSecondGap)) {
      return 'Combined-score thresholds and separation must be ordered within 0..1.';
    }
    if (!_unit(maximumBaselineForegroundRatio) ||
        !_unit(severeBaselineForegroundRatio) ||
        maximumBaselineForegroundRatio >= severeBaselineForegroundRatio) {
      return 'Baseline contamination thresholds must be ordered within 0..1.';
    }
    if (!_unit(minimumValidSampleRatio) ||
        !_unit(severeMinimumValidSampleRatio) ||
        severeMinimumValidSampleRatio >= minimumValidSampleRatio) {
      return 'Sample-quality thresholds must be ordered within 0..1.';
    }
    if (![
          fillWeight,
          normalizedDarknessWeight,
          darknessContrastWeight,
        ].every((weight) => weight.isFinite && weight >= 0) ||
        (fillWeight + normalizedDarknessWeight + darknessContrastWeight - 1)
                .abs() >
            1e-9) {
      return 'Evidence weights must be non-negative, finite, and sum to 1.';
    }
    return null;
  }

  static bool _orderedThresholds(
    double minimum,
    double strong, {
    double? maximum,
  }) =>
      minimum.isFinite &&
      strong.isFinite &&
      minimum >= 0 &&
      minimum < strong &&
      (maximum == null || strong <= maximum);

  static bool _unit(double value) => value.isFinite && value >= 0 && value <= 1;
}
