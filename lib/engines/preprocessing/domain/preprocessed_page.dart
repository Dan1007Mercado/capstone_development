import '../../aruco/domain/image_geometry.dart';
import 'pixel_images.dart';
import 'preprocessing_config.dart';

final class ImageStatistics {
  const ImageStatistics({
    required this.meanIntensity,
    required this.intensityStandardDeviation,
    required this.minimumIntensity,
    required this.maximumIntensity,
    required this.darkPixelRatio,
    required this.brightPixelRatio,
  });

  final double meanIntensity;
  final double intensityStandardDeviation;
  final int minimumIntensity;
  final int maximumIntensity;
  final double darkPixelRatio;
  final double brightPixelRatio;
}

final class PreprocessingDiagnostics {
  const PreprocessingDiagnostics({
    required this.sourceStatistics,
    required this.normalizedStatistics,
    required this.binaryForegroundRatio,
    required this.processingDuration,
    this.stageDurations = const PreprocessingStageDurations(),
  });

  final ImageStatistics sourceStatistics;
  final ImageStatistics normalizedStatistics;
  final double binaryForegroundRatio;
  final Duration processingDuration;
  final PreprocessingStageDurations stageDurations;
}

final class PreprocessingStageDurations {
  const PreprocessingStageDurations({
    this.denoise = Duration.zero,
    this.illuminationNormalization = Duration.zero,
    this.thresholding = Duration.zero,
    this.statistics = Duration.zero,
  });

  final Duration denoise;
  final Duration illuminationNormalization;
  final Duration thresholding;
  final Duration statistics;
}

final class PreprocessedPage {
  const PreprocessedPage({
    required this.size,
    required this.grayscale,
    required this.normalizedGrayscale,
    required this.binary,
    required this.diagnostics,
    required this.config,
  });

  final ImageSize size;
  final GrayImage grayscale;
  final GrayImage normalizedGrayscale;
  final BinaryImage binary;
  final PreprocessingDiagnostics diagnostics;
  final PreprocessingConfig config;
}
