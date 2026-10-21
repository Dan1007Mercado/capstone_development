/// Centralized tuning for deterministic bubble evidence and question decisions.
///
/// Coverage is intentionally the primary mark signal. Darkness confirms that
/// the covered pixels are ink, while distribution distinguishes broad marks
/// from concentrated dots or strokes.
final class MarkClassificationConfig {
  const MarkClassificationConfig({
    this.minimumMarkCoverage = 0.12,
    this.strongMarkCoverage = 0.45,
    this.blankMaximumCoverage = 0.08,
    this.minimumNormalizedDarkness = 0.08,
    this.strongNormalizedDarkness = 0.30,
    this.minimumDarknessContrast = 12,
    this.strongDarknessContrast = 60,
    this.minimumDarknessEvidence = 0.22,
    this.normalizedDarknessShare = 0.50,
    this.coverageWeight = 0.65,
    this.darknessWeight = 0.25,
    this.distributionWeight = 0.10,
    this.minimumDistributedMarkScore = 0.45,
    this.minimumCombinedMarkScore = 0.35,
    this.strongCombinedMarkScore = 0.65,
    this.minimumTopSecondScoreGap = 0.12,
    this.coverageDominanceRatio = 1.80,
    this.coverageDominanceGap = 0.15,
    this.multipleMarkMinimumCoverage = 0.30,
    this.multipleMarkMinimumConfidence = 0.65,
    this.maximumBaselineForegroundRatio = 0.35,
    this.severeBaselineForegroundRatio = 0.65,
    this.requireReliableBaseline = true,
    this.minimumValidSampleRatio = 0.90,
    this.severeMinimumValidSampleRatio = 0.75,
    this.epsilon = 1e-6,
  });

  /// Minimum raw foreground coverage counted as one independent mark signal.
  final double minimumMarkCoverage;

  /// Coverage at which coverage scoring saturates at 1.0.
  ///
  /// A physical bubble need not reach 100% foreground because thresholding,
  /// blur, and pen style can leave valid interior pixels unclassified.
  final double strongMarkCoverage;

  /// Upper coverage bound for a conservative blank when darkness is weak.
  final double blankMaximumCoverage;

  final double minimumNormalizedDarkness;
  final double strongNormalizedDarkness;
  final double minimumDarknessContrast;
  final double strongDarknessContrast;

  /// Minimum consolidated darkness score required for credible mark evidence.
  final double minimumDarknessEvidence;

  /// Share of normalized darkness within the consolidated darkness score. The
  /// remainder is contributed by absolute local contrast.
  final double normalizedDarknessShare;

  /// Coverage/darkness/distribution weights for the combined mark score.
  final double coverageWeight;
  final double darknessWeight;
  final double distributionWeight;

  /// Minimum spread required when raw coverage is below
  /// [minimumMarkCoverage]. This preserves broad faint strokes without
  /// promoting a concentrated dark dot.
  final double minimumDistributedMarkScore;

  final double minimumCombinedMarkScore;
  final double strongCombinedMarkScore;
  final double minimumTopSecondScoreGap;

  /// Relative and absolute coverage separation required for a safe coverage
  /// dominance decision. Both gates must pass.
  final double coverageDominanceRatio;
  final double coverageDominanceGap;

  /// Absolute gates ensuring two genuinely filled bubbles remain MULTIPLE.
  final double multipleMarkMinimumCoverage;
  final double multipleMarkMinimumConfidence;

  final double maximumBaselineForegroundRatio;
  final double severeBaselineForegroundRatio;
  final bool requireReliableBaseline;
  final double minimumValidSampleRatio;
  final double severeMinimumValidSampleRatio;
  final double epsilon;

  String? validationMessage() {
    if (!_orderedThresholds(
          minimumMarkCoverage,
          strongMarkCoverage,
          maximum: 1,
        ) ||
        !_unit(blankMaximumCoverage) ||
        blankMaximumCoverage >= minimumMarkCoverage) {
      return 'Coverage thresholds must be finite and ordered within 0..1.';
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
    if (!_unit(minimumDarknessEvidence) || !_unit(normalizedDarknessShare)) {
      return 'Darkness scoring parameters must be within 0..1.';
    }
    if (![
          coverageWeight,
          darknessWeight,
          distributionWeight,
        ].every((weight) => weight.isFinite && weight >= 0) ||
        (coverageWeight + darknessWeight + distributionWeight - 1).abs() >
            1e-9) {
      return 'Coverage, darkness, and distribution weights must be non-negative, finite, and sum to 1.';
    }
    if (!_unit(minimumDistributedMarkScore)) {
      return 'Minimum distributed-mark score must be within 0..1.';
    }
    if (!_unit(minimumCombinedMarkScore) ||
        !_unit(strongCombinedMarkScore) ||
        minimumCombinedMarkScore >= strongCombinedMarkScore ||
        !_unit(minimumTopSecondScoreGap)) {
      return 'Combined-score thresholds and separation must be ordered within 0..1.';
    }
    if (!coverageDominanceRatio.isFinite ||
        coverageDominanceRatio <= 1 ||
        !_unit(coverageDominanceGap)) {
      return 'Coverage dominance requires a ratio above 1 and a gap within 0..1.';
    }
    if (!_unit(multipleMarkMinimumCoverage) ||
        !_unit(multipleMarkMinimumConfidence) ||
        multipleMarkMinimumCoverage < minimumMarkCoverage) {
      return 'Multiple-mark gates must be valid coverage and confidence values.';
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
    if (!epsilon.isFinite || epsilon <= 0) {
      return 'Classification epsilon must be finite and positive.';
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
