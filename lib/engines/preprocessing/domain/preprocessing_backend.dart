import '../../../core/result/engine_result.dart';
import '../../aruco/domain/page_alignment_result.dart';
import 'pixel_images.dart';
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
  });

  final GrayImage grayscale;
  final GrayImage normalizedGrayscale;
  final BinaryImage binary;
}
