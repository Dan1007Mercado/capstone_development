import 'dart:math' as math;

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../aruco/domain/page_alignment_result.dart';
import '../domain/pixel_images.dart';
import '../domain/preprocessed_page.dart';
import '../domain/preprocessing_backend.dart';
import '../domain/preprocessing_config.dart';

final class PreprocessingEngine {
  const PreprocessingEngine({required this.backend});

  final PreprocessingBackend backend;

  EngineResult<PreprocessedPage> process(
    CanonicalPageImage page, [
    PreprocessingConfig config = const PreprocessingConfig(),
  ]) {
    final stopwatch = Stopwatch()..start();
    if (page.pngBytes.isEmpty && page.grayscaleBytes.isEmpty) {
      return _failure(
        'PREPROCESS_IMAGE_INVALID',
        'Canonical image bytes are empty.',
      );
    }
    final configError = config.validationMessage();
    if (configError != null) {
      return _failure('PREPROCESS_CONFIG_INVALID', configError);
    }

    final backendResult = backend.process(page, config);
    if (backendResult.isFailure) {
      return EngineResult.failure(backendResult.error);
    }
    final output = backendResult.value;
    if (output.grayscale.size != page.size ||
        output.normalizedGrayscale.size != page.size ||
        output.binary.size != page.size ||
        output.grayscale.pixels.length != page.size.area ||
        output.normalizedGrayscale.pixels.length != page.size.area ||
        output.binary.pixels.length != page.size.area) {
      return _failure(
        'PREPROCESS_FAILED',
        'The preprocessing backend violated the canonical image contract.',
      );
    }

    final statisticsStopwatch = Stopwatch()..start();
    final sourceStatistics =
        output.sourceStatistics ?? _statistics(output.grayscale, config);
    final normalizedStatistics =
        output.normalizedStatistics ??
        _statistics(output.normalizedGrayscale, config);
    final foregroundCount =
        output.binaryForegroundCount ??
        output.binary.pixels.fold<int>(0, (sum, pixel) => sum + pixel);
    statisticsStopwatch.stop();
    final foregroundRatio = foregroundCount / page.size.area;
    if (!_statisticsAreFinite(sourceStatistics) ||
        !_statisticsAreFinite(normalizedStatistics) ||
        !foregroundRatio.isFinite) {
      return _failure(
        'PREPROCESS_FAILED',
        'Preprocessing produced invalid image statistics.',
      );
    }
    if (sourceStatistics.intensityStandardDeviation <
        config.minimumIntensityStdDev) {
      return _failure(
        'PREPROCESS_LOW_CONTRAST',
        'Canonical image is too uniform for reliable preprocessing.',
        {
          'intensityStandardDeviation':
              sourceStatistics.intensityStandardDeviation,
          'minimumRequired': config.minimumIntensityStdDev,
        },
      );
    }

    stopwatch.stop();
    return EngineResult.success(
      PreprocessedPage(
        size: page.size,
        grayscale: output.grayscale,
        normalizedGrayscale: output.normalizedGrayscale,
        binary: output.binary,
        diagnostics: PreprocessingDiagnostics(
          sourceStatistics: sourceStatistics,
          normalizedStatistics: normalizedStatistics,
          binaryForegroundRatio: foregroundRatio,
          processingDuration: stopwatch.elapsed,
          stageDurations: PreprocessingStageDurations(
            denoise: output.stageDurations.denoise,
            illuminationNormalization:
                output.stageDurations.illuminationNormalization,
            thresholding: output.stageDurations.thresholding,
            statistics:
                output.stageDurations.statistics + statisticsStopwatch.elapsed,
          ),
        ),
        config: config,
      ),
    );
  }

  ImageStatistics _statistics(GrayImage image, PreprocessingConfig config) {
    var sum = 0.0;
    var sumSquares = 0.0;
    var minimum = 255;
    var maximum = 0;
    var dark = 0;
    var bright = 0;
    for (final pixel in image.pixels) {
      sum += pixel;
      sumSquares += pixel * pixel;
      if (pixel < minimum) minimum = pixel;
      if (pixel > maximum) maximum = pixel;
      if (pixel <= config.darkPixelThreshold) dark++;
      if (pixel >= config.brightPixelThreshold) bright++;
    }
    final count = image.pixels.length;
    final mean = sum / count;
    final variance = math.max(0.0, sumSquares / count - mean * mean);
    return ImageStatistics(
      meanIntensity: mean,
      intensityStandardDeviation: math.sqrt(variance),
      minimumIntensity: minimum,
      maximumIntensity: maximum,
      darkPixelRatio: dark / count,
      brightPixelRatio: bright / count,
    );
  }

  bool _statisticsAreFinite(ImageStatistics statistics) =>
      statistics.meanIntensity.isFinite &&
      statistics.intensityStandardDeviation.isFinite &&
      statistics.darkPixelRatio.isFinite &&
      statistics.brightPixelRatio.isFinite;

  EngineResult<PreprocessedPage> _failure(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );
}
