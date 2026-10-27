import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../aruco/domain/page_alignment_result.dart';
import '../domain/pixel_images.dart';
import '../domain/preprocessed_page.dart';
import '../domain/preprocessing_backend.dart';
import '../domain/preprocessing_config.dart';

/// Native P6 implementation used by the final-scanner worker.
///
/// The clipped local-mean window matches the Dart reference implementation.
/// Returned buffers own copies detached from native Mats; every Mat is disposed
/// before this method returns.
final class OpenCvPreprocessingBackend implements PreprocessingBackend {
  const OpenCvPreprocessingBackend();

  @override
  EngineResult<BackendPreprocessingOutput> process(
    CanonicalPageImage page,
    PreprocessingConfig config,
  ) {
    cv.Mat? source;
    cv.Mat? working;
    cv.Mat? normalized;
    cv.Mat? thresholdMean;
    cv.Mat? thresholdSource32;
    cv.Mat? thresholdBoundary32;
    cv.Mat? binaryMask;
    cv.Mat? binaryOne;
    cv.VecU8? inputBytes;
    try {
      if (page.grayscaleBytes.isNotEmpty) {
        // Mat.fromList casts the typed bytes to a generic list in opencv_dart
        // 1.2.5, preventing the bulk copy. The typed vector reaches the same
        // copying native constructor without that per-byte Dart traversal.
        inputBytes = cv.VecU8.fromList(page.grayscaleBytes);
        source = cv.Mat.fromVec(
          inputBytes,
          rows: page.size.height,
          cols: page.size.width,
          type: cv.MatType.CV_8UC1,
        );
        inputBytes.dispose();
        inputBytes = null;
      } else {
        source = cv.imdecode(page.pngBytes, cv.IMREAD_GRAYSCALE);
      }
      if (source.isEmpty || source.width <= 0 || source.height <= 0) {
        return _failure(
          'PREPROCESS_IMAGE_INVALID',
          'Canonical bytes are not a decodable grayscale image.',
        );
      }
      if (source.width != page.size.width ||
          source.height != page.size.height) {
        return _failure(
          'PREPROCESS_IMAGE_SIZE_MISMATCH',
          'Decoded image dimensions do not match the canonical size.',
          {
            'declaredWidth': page.size.width,
            'declaredHeight': page.size.height,
            'decodedWidth': source.width,
            'decodedHeight': source.height,
          },
        );
      }

      final sourceBytes = page.grayscaleBytes.isNotEmpty
          ? page.grayscaleBytes
          : Uint8List.fromList(source.data);
      final denoiseStopwatch = Stopwatch()..start();
      working = config.enableDenoise
          ? _clippedLocalMean(source, config.denoiseKernelSize)
          : source.clone();
      denoiseStopwatch.stop();

      final normalizationStopwatch = Stopwatch()..start();
      if (config.enableIlluminationNormalization) {
        final background = _clippedLocalMean(
          working,
          config.backgroundKernelSize,
        );
        try {
          normalized = cv.addWeighted(working, 1, background, -1, 220);
        } finally {
          background.dispose();
        }
      } else {
        normalized = working.clone();
      }
      normalizationStopwatch.stop();
      final normalizedBytes = Uint8List.fromList(normalized.data);

      final thresholdStopwatch = Stopwatch()..start();
      thresholdMean = _clippedLocalMean(
        normalized,
        config.adaptiveThresholdBlockSize,
      );
      thresholdSource32 = normalized.convertTo(cv.MatType.CV_32FC1);
      thresholdBoundary32 = thresholdMean.convertTo(
        cv.MatType.CV_32FC1,
        beta: -config.adaptiveThresholdC,
      );
      binaryMask = cv.compare(
        thresholdSource32,
        thresholdBoundary32,
        cv.CMP_LE,
      );
      final foregroundCount = cv.countNonZero(binaryMask);
      binaryOne = binaryMask.convertTo(cv.MatType.CV_8UC1, alpha: 1 / 255);
      final binaryBytes = Uint8List.fromList(binaryOne.data);
      thresholdStopwatch.stop();

      final statisticsStopwatch = Stopwatch()..start();
      final sourceStatistics = _statistics(source, config);
      final normalizedStatistics = _statistics(normalized, config);
      statisticsStopwatch.stop();
      return EngineResult.success(
        BackendPreprocessingOutput(
          grayscale: GrayImage.owned(size: page.size, pixels: sourceBytes),
          normalizedGrayscale: GrayImage.owned(
            size: page.size,
            pixels: normalizedBytes,
          ),
          binary: BinaryImage.owned(size: page.size, pixels: binaryBytes),
          sourceStatistics: sourceStatistics,
          normalizedStatistics: normalizedStatistics,
          binaryForegroundCount: foregroundCount,
          stageDurations: PreprocessingStageDurations(
            denoise: denoiseStopwatch.elapsed,
            illuminationNormalization: normalizationStopwatch.elapsed,
            thresholding: thresholdStopwatch.elapsed,
            statistics: statisticsStopwatch.elapsed,
          ),
        ),
      );
    } on Object catch (error) {
      return _failure(
        'PREPROCESS_FAILED',
        'Native OpenCV preprocessing failed.',
        {'cause': error.toString()},
      );
    } finally {
      binaryOne?.dispose();
      binaryMask?.dispose();
      thresholdBoundary32?.dispose();
      thresholdSource32?.dispose();
      thresholdMean?.dispose();
      normalized?.dispose();
      working?.dispose();
      source?.dispose();
      inputBytes?.dispose();
    }
  }

  cv.Mat _clippedLocalMean(cv.Mat source, int kernelSize) {
    final source32 = source.convertTo(cv.MatType.CV_32FC1);
    final ones = cv.Mat.ones(source.rows, source.cols, cv.MatType.CV_32FC1);
    cv.Mat? sums;
    cv.Mat? counts;
    cv.Mat? means;
    try {
      sums = cv.boxFilter(
        source32,
        cv.MatType.CV_32F,
        (kernelSize, kernelSize),
        normalize: false,
        borderType: cv.BORDER_CONSTANT,
      );
      counts = cv.boxFilter(
        ones,
        cv.MatType.CV_32F,
        (kernelSize, kernelSize),
        normalize: false,
        borderType: cv.BORDER_CONSTANT,
      );
      means = cv.divide(sums, counts);
      return means.convertTo(cv.MatType.CV_8UC1);
    } finally {
      means?.dispose();
      counts?.dispose();
      sums?.dispose();
      ones.dispose();
      source32.dispose();
    }
  }

  ImageStatistics _statistics(cv.Mat pixels, PreprocessingConfig config) {
    cv.Scalar? mean;
    cv.Scalar? standardDeviation;
    cv.Mat? darkMask;
    cv.Mat? brightMask;
    try {
      final statistics = cv.meanStdDev(pixels);
      mean = statistics.$1;
      standardDeviation = statistics.$2;
      final extremes = cv.minMaxIdx(pixels);
      darkMask = cv
          .threshold(
            pixels,
            config.darkPixelThreshold.toDouble(),
            255,
            cv.THRESH_BINARY_INV,
          )
          .$2;
      brightMask = cv
          .threshold(
            pixels,
            (config.brightPixelThreshold - 1).toDouble(),
            255,
            cv.THRESH_BINARY,
          )
          .$2;
      final pixelCount = pixels.rows * pixels.cols;
      return ImageStatistics(
        meanIntensity: mean.val1,
        intensityStandardDeviation: standardDeviation.val1,
        minimumIntensity: extremes.$1.round(),
        maximumIntensity: extremes.$2.round(),
        darkPixelRatio: cv.countNonZero(darkMask) / pixelCount,
        brightPixelRatio: cv.countNonZero(brightMask) / pixelCount,
      );
    } finally {
      brightMask?.dispose();
      darkMask?.dispose();
      standardDeviation?.dispose();
      mean?.dispose();
    }
  }

  EngineResult<BackendPreprocessingOutput> _failure(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );
}
