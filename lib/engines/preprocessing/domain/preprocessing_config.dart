final class PreprocessingConfig {
  const PreprocessingConfig({
    this.enableIlluminationNormalization = true,
    this.backgroundKernelSize = 31,
    this.enableDenoise = true,
    this.denoiseKernelSize = 3,
    this.adaptiveThresholdBlockSize = 15,
    this.adaptiveThresholdC = 7,
    this.minimumIntensityStdDev = 2.0,
    this.darkPixelThreshold = 32,
    this.brightPixelThreshold = 245,
  });

  final bool enableIlluminationNormalization;
  final int backgroundKernelSize;
  final bool enableDenoise;
  final int denoiseKernelSize;
  final int adaptiveThresholdBlockSize;
  final double adaptiveThresholdC;
  final double minimumIntensityStdDev;
  final int darkPixelThreshold;
  final int brightPixelThreshold;

  String? validationMessage() {
    if (!_validOddKernel(backgroundKernelSize)) {
      return 'Background kernel size must be an odd integer from 3 to 1001.';
    }
    if (!_validOddKernel(denoiseKernelSize)) {
      return 'Denoise kernel size must be an odd integer from 3 to 1001.';
    }
    if (!_validOddKernel(adaptiveThresholdBlockSize)) {
      return 'Adaptive threshold block size must be an odd integer from 3 to 1001.';
    }
    if (!adaptiveThresholdC.isFinite || adaptiveThresholdC.abs() > 255) {
      return 'Adaptive threshold C must be finite and between -255 and 255.';
    }
    if (!minimumIntensityStdDev.isFinite ||
        minimumIntensityStdDev < 0 ||
        minimumIntensityStdDev > 127.5) {
      return 'Minimum intensity standard deviation must be from 0 to 127.5.';
    }
    if (darkPixelThreshold < 0 ||
        darkPixelThreshold > 255 ||
        brightPixelThreshold < 0 ||
        brightPixelThreshold > 255 ||
        darkPixelThreshold >= brightPixelThreshold) {
      return 'Dark and bright thresholds must be ordered values from 0 to 255.';
    }
    return null;
  }

  static bool _validOddKernel(int value) =>
      value >= 3 && value <= 1001 && value.isOdd;
}
