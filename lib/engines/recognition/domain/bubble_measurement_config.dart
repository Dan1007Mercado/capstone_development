final class BubbleMeasurementConfig {
  const BubbleMeasurementConfig({
    this.interiorRadiusRatio = 0.68,
    this.baselineInnerRadiusRatio = 1.25,
    this.baselineOuterRadiusRatio = 2.0,
    this.minimumInteriorPixels = 8,
    this.minimumBaselinePixels = 12,
    this.minimumValidSampleRatio = 0.9,
    this.allowPartialClipping = true,
    this.excludeBaselineForeground = true,
    this.excludeNeighborBubbles = true,
    this.baselinePercentile = 0.7,
    this.maximumBaselineForegroundRatio = 0.35,
    this.distributionGridSize = 3,
    this.distributionCellMinimumFillRatio = 0.12,
    this.epsilon = 1e-6,
  });

  final double interiorRadiusRatio;
  final double baselineInnerRadiusRatio;
  final double baselineOuterRadiusRatio;
  final int minimumInteriorPixels;
  final int minimumBaselinePixels;
  final double minimumValidSampleRatio;
  final bool allowPartialClipping;
  final bool excludeBaselineForeground;
  final bool excludeNeighborBubbles;
  final double baselinePercentile;
  final double maximumBaselineForegroundRatio;

  /// Fixed grid used to measure whether foreground spans the bubble interior.
  final int distributionGridSize;

  /// Minimum foreground share for a grid cell to count as occupied.
  final double distributionCellMinimumFillRatio;
  final double epsilon;

  String? validationMessage() {
    if (!interiorRadiusRatio.isFinite ||
        interiorRadiusRatio <= 0 ||
        interiorRadiusRatio >= 1) {
      return 'Interior radius ratio must be finite and between 0 and 1.';
    }
    if (!baselineInnerRadiusRatio.isFinite ||
        !baselineOuterRadiusRatio.isFinite ||
        baselineInnerRadiusRatio <= 1 ||
        baselineOuterRadiusRatio <= baselineInnerRadiusRatio ||
        baselineOuterRadiusRatio > 20) {
      return 'Baseline radii must be finite, outside the printed circle, ordered, and at most 20.';
    }
    if (minimumInteriorPixels < 1 || minimumBaselinePixels < 1) {
      return 'Minimum sample counts must be positive.';
    }
    if (!_unitInterval(minimumValidSampleRatio) ||
        minimumValidSampleRatio == 0) {
      return 'Minimum valid sample ratio must be greater than 0 and at most 1.';
    }
    if (!_unitInterval(baselinePercentile)) {
      return 'Baseline percentile must be between 0 and 1.';
    }
    if (!_unitInterval(maximumBaselineForegroundRatio)) {
      return 'Maximum baseline foreground ratio must be between 0 and 1.';
    }
    if (distributionGridSize < 2 || distributionGridSize > 8) {
      return 'Distribution grid size must be from 2 to 8.';
    }
    if (!_unitInterval(distributionCellMinimumFillRatio) ||
        distributionCellMinimumFillRatio == 0) {
      return 'Distribution cell fill ratio must be greater than 0 and at most 1.';
    }
    if (!epsilon.isFinite || epsilon <= 0) {
      return 'Normalization epsilon must be finite and positive.';
    }
    return null;
  }

  static bool _unitInterval(double value) =>
      value.isFinite && value >= 0 && value <= 1;
}
