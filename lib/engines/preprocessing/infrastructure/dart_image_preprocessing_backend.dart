import 'dart:typed_data';

import 'package:image/image.dart' as image_codec;

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../aruco/domain/image_geometry.dart';
import '../../aruco/domain/page_alignment_result.dart';
import '../domain/pixel_images.dart';
import '../domain/preprocessing_backend.dart';
import '../domain/preprocessing_config.dart';

final class DartImagePreprocessingBackend implements PreprocessingBackend {
  const DartImagePreprocessingBackend();

  @override
  EngineResult<BackendPreprocessingOutput> process(
    CanonicalPageImage page,
    PreprocessingConfig config,
  ) {
    if (page.grayscaleBytes.isNotEmpty) {
      return _processGrayscale(page, config);
    }
    image_codec.Image? decoded;
    try {
      decoded = image_codec.decodePng(page.pngBytes);
    } on Object {
      return _failure(
        'PREPROCESS_IMAGE_INVALID',
        'Canonical bytes are not a decodable PNG image.',
      );
    }
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return _failure(
        'PREPROCESS_IMAGE_INVALID',
        'Canonical bytes are not a decodable PNG image.',
      );
    }
    try {
      if (decoded.width != page.size.width ||
          decoded.height != page.size.height) {
        return _failure(
          'PREPROCESS_IMAGE_SIZE_MISMATCH',
          'Decoded PNG dimensions do not match the declared canonical size.',
          {
            'declaredWidth': page.size.width,
            'declaredHeight': page.size.height,
            'decodedWidth': decoded.width,
            'decodedHeight': decoded.height,
          },
        );
      }

      final grayscalePixels = Uint8List(page.size.area);
      for (var y = 0; y < page.size.height; y++) {
        for (var x = 0; x < page.size.width; x++) {
          grayscalePixels[y * page.size.width + x] = decoded
              .getPixel(x, y)
              .luminance
              .round()
              .clamp(0, 255)
              .toInt();
        }
      }
      final workingPixels = config.enableDenoise
          ? _localMean(grayscalePixels, page.size, config.denoiseKernelSize)
          : Uint8List.fromList(grayscalePixels);
      final normalizedPixels = config.enableIlluminationNormalization
          ? _normalizeIllumination(
              workingPixels,
              page.size,
              config.backgroundKernelSize,
            )
          : Uint8List.fromList(workingPixels);
      final binaryPixels = _adaptiveThreshold(
        normalizedPixels,
        page.size,
        config.adaptiveThresholdBlockSize,
        config.adaptiveThresholdC,
      );
      return EngineResult.success(
        BackendPreprocessingOutput(
          grayscale: GrayImage(size: page.size, pixels: grayscalePixels),
          normalizedGrayscale: GrayImage(
            size: page.size,
            pixels: normalizedPixels,
          ),
          binary: BinaryImage(size: page.size, pixels: binaryPixels),
        ),
      );
    } on Object catch (error) {
      return _failure(
        'PREPROCESS_FAILED',
        'Canonical PNG preprocessing failed.',
        {'cause': error.toString()},
      );
    }
  }

  EngineResult<BackendPreprocessingOutput> _processGrayscale(
    CanonicalPageImage page,
    PreprocessingConfig config,
  ) {
    try {
      final grayscalePixels = page.grayscaleBytes;
      final workingPixels = config.enableDenoise
          ? _localMean(grayscalePixels, page.size, config.denoiseKernelSize)
          : Uint8List.fromList(grayscalePixels);
      final normalizedPixels = config.enableIlluminationNormalization
          ? _normalizeIllumination(
              workingPixels,
              page.size,
              config.backgroundKernelSize,
            )
          : Uint8List.fromList(workingPixels);
      final binaryPixels = _adaptiveThreshold(
        normalizedPixels,
        page.size,
        config.adaptiveThresholdBlockSize,
        config.adaptiveThresholdC,
      );
      return EngineResult.success(
        BackendPreprocessingOutput(
          grayscale: GrayImage(size: page.size, pixels: grayscalePixels),
          normalizedGrayscale: GrayImage(
            size: page.size,
            pixels: normalizedPixels,
          ),
          binary: BinaryImage(size: page.size, pixels: binaryPixels),
        ),
      );
    } on Object catch (error) {
      return _failure(
        'PREPROCESS_FAILED',
        'Canonical grayscale preprocessing failed.',
        {'cause': error.toString()},
      );
    }
  }

  Uint8List _normalizeIllumination(
    Uint8List source,
    ImageSize size,
    int kernelSize,
  ) {
    final background = _localMean(source, size, kernelSize);
    final output = Uint8List(size.area);
    for (var index = 0; index < source.length; index++) {
      output[index] = (source[index] - background[index] + 220)
          .clamp(0, 255)
          .toInt();
    }
    return output;
  }

  Uint8List _adaptiveThreshold(
    Uint8List source,
    ImageSize size,
    int blockSize,
    double constant,
  ) {
    final localMean = _localMean(source, size, blockSize);
    final output = Uint8List(size.area);
    for (var index = 0; index < source.length; index++) {
      output[index] = source[index] <= localMean[index] - constant ? 1 : 0;
    }
    return output;
  }

  Uint8List _localMean(Uint8List source, ImageSize size, int kernelSize) {
    final integralWidth = size.width + 1;
    final integral = Int64List(integralWidth * (size.height + 1));
    for (var y = 0; y < size.height; y++) {
      var rowSum = 0;
      for (var x = 0; x < size.width; x++) {
        rowSum += source[y * size.width + x];
        integral[(y + 1) * integralWidth + x + 1] =
            integral[y * integralWidth + x + 1] + rowSum;
      }
    }

    final radius = kernelSize ~/ 2;
    final output = Uint8List(size.area);
    for (var y = 0; y < size.height; y++) {
      final top = (y - radius).clamp(0, size.height - 1).toInt();
      final bottom = (y + radius).clamp(0, size.height - 1).toInt();
      for (var x = 0; x < size.width; x++) {
        final left = (x - radius).clamp(0, size.width - 1).toInt();
        final right = (x + radius).clamp(0, size.width - 1).toInt();
        final sum =
            integral[(bottom + 1) * integralWidth + right + 1] -
            integral[top * integralWidth + right + 1] -
            integral[(bottom + 1) * integralWidth + left] +
            integral[top * integralWidth + left];
        final count = (right - left + 1) * (bottom - top + 1);
        output[y * size.width + x] = (sum / count).round();
      }
    }
    return output;
  }

  EngineResult<BackendPreprocessingOutput> _failure(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );
}
