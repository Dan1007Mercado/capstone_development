import 'dart:typed_data';

import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/preprocessing/application/preprocessing_engine.dart';
import 'package:capstone_development/engines/preprocessing/domain/pixel_images.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessing_backend.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessing_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty bytes fail before opening the backend', () {
    final backend = _RecordingBackend();
    final result = PreprocessingEngine(backend: backend).process(
      CanonicalPageImage(
        size: ImageSize(width: 2, height: 2),
        pngBytes: const [],
      ),
    );

    expect(result.error.code, 'PREPROCESS_IMAGE_INVALID');
    expect(backend.called, isFalse);
  });

  test('invalid and even kernel sizes return config failures', () {
    final backend = _RecordingBackend();
    final engine = PreprocessingEngine(backend: backend);
    final page = _nonEmptyPage();

    for (final config in [
      const PreprocessingConfig(backgroundKernelSize: 1),
      const PreprocessingConfig(denoiseKernelSize: 4),
      const PreprocessingConfig(adaptiveThresholdBlockSize: 10),
    ]) {
      final result = engine.process(page, config);
      expect(result.error.code, 'PREPROCESS_CONFIG_INVALID');
    }
    expect(backend.called, isFalse);
  });

  test('backend failure is preserved', () {
    final result = PreprocessingEngine(
      backend: _RecordingBackend(fail: true),
    ).process(_nonEmptyPage());

    expect(result.error.code, 'PREPROCESS_BACKEND_UNAVAILABLE');
  });

  test('backend dimensions must preserve the canonical contract', () {
    final backend = _RecordingBackend(
      outputSize: ImageSize(width: 3, height: 3),
    );
    final result = PreprocessingEngine(
      backend: backend,
    ).process(_nonEmptyPage());

    expect(result.error.code, 'PREPROCESS_FAILED');
  });
}

CanonicalPageImage _nonEmptyPage() =>
    CanonicalPageImage(size: ImageSize(width: 2, height: 2), pngBytes: [1]);

final class _RecordingBackend implements PreprocessingBackend {
  _RecordingBackend({this.fail = false, this.outputSize});

  final bool fail;
  final ImageSize? outputSize;
  bool called = false;

  @override
  EngineResult<BackendPreprocessingOutput> process(
    CanonicalPageImage page,
    PreprocessingConfig config,
  ) {
    called = true;
    if (fail) {
      return EngineResult.failure(
        EngineError(
          code: 'PREPROCESS_BACKEND_UNAVAILABLE',
          message: 'Unavailable for test.',
        ),
      );
    }
    final size = outputSize ?? page.size;
    return EngineResult.success(
      BackendPreprocessingOutput(
        grayscale: GrayImage(size: size, pixels: Uint8List(size.area)),
        normalizedGrayscale: GrayImage(
          size: size,
          pixels: Uint8List(size.area),
        ),
        binary: BinaryImage(size: size, pixels: Uint8List(size.area)),
      ),
    );
  }
}
