import '../../../core/result/engine_result.dart';
import '../../aruco/domain/page_alignment_result.dart';
import 'pixel_images.dart';
import 'preprocessed_page.dart';
import 'preprocessing_config.dart';

abstract interface class PreprocessingBackend {
  EngineResult<BackendPreprocessingOutput> process(
    CanonicalPageImage page,
    PreprocessingConfig config,
  );
}

final class BackendPreprocessingOutput {
  const BackendPreprocessingOutput({
    required this.grayscale,
    required this.normalizedGrayscale,
    required this.binary,
    this.sourceStatistics,
    this.normalizedStatistics,
    this.binaryForegroundCount,
    this.stageDurations = const PreprocessingStageDurations(),
  });

  final GrayImage grayscale;
  final GrayImage normalizedGrayscale;
  final BinaryImage binary;
  final ImageStatistics? sourceStatistics;
  final ImageStatistics? normalizedStatistics;
  final int? binaryForegroundCount;
  final PreprocessingStageDurations stageDurations;
}
