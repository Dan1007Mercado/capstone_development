import 'dart:math' as math;
import 'dart:typed_data';

import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/preprocessing/application/preprocessing_engine.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessing_config.dart';
import 'package:capstone_development/engines/preprocessing/infrastructure/dart_image_preprocessing_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  const engine = PreprocessingEngine(backend: DartImagePreprocessingBackend());

  test('corrupt PNG bytes return a structured image failure', () {
    final result = engine.process(
      CanonicalPageImage(
        size: ImageSize(width: 4, height: 4),
        pngBytes: [1, 2, 3, 4],
      ),
    );

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'PREPROCESS_IMAGE_INVALID');
  });

  test('declared canonical size mismatch fails without resizing', () {
    final result = engine.process(
      CanonicalPageImage(
        size: ImageSize(width: 31, height: 32),
        pngBytes: _png(_solid(32, 32, 255)),
      ),
    );

    expect(result.error.code, 'PREPROCESS_IMAGE_SIZE_MISMATCH');
  });

  for (final value in [0, 255]) {
    test('uniform $value page fails the low-contrast quality gate', () {
      final result = engine.process(_page(_solid(48, 48, value)));

      expect(result.isFailure, isTrue);
      expect(result.error.code, 'PREPROCESS_LOW_CONTRAST');
    });
  }

  test('simple black-on-white form produces exact scanner-ready buffers', () {
    final fixture = _solid(64, 64, 255);
    image.fillRect(
      fixture,
      x1: 22,
      y1: 22,
      x2: 41,
      y2: 41,
      color: image.ColorRgb8(0, 0, 0),
    );
    final result = engine.process(_page(fixture));

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    final page = result.value;
    expect(page.size, ImageSize(width: 64, height: 64));
    expect(page.grayscale.pixels, hasLength(64 * 64));
    expect(page.normalizedGrayscale.pixels, hasLength(64 * 64));
    expect(page.binary.pixels, hasLength(64 * 64));
    expect(page.grayscale.pixels, everyElement(inInclusiveRange(0, 255)));
    expect(page.binary.pixels.toSet().difference({0, 1}), isEmpty);
    expect(
      _regionSum(page.binary.pixels, 64, 20, 20, 43, 43),
      greaterThan(50),
      reason: 'The dark shape region contains foreground ink.',
    );
    expect(page.binary.at(5, 5), isFalse, reason: 'White paper is background.');
  });

  test('same bytes and config produce identical semantic buffers', () {
    final fixture = _gradient(72, 56, start: 130, end: 250);
    image.fillCircle(
      fixture,
      x: 35,
      y: 27,
      radius: 6,
      color: image.ColorRgb8(35, 35, 35),
    );
    final canonical = _page(fixture);

    final first = engine.process(canonical).value;
    final second = engine.process(canonical).value;
    expect(first.grayscale.pixels, second.grayscale.pixels);
    expect(first.normalizedGrayscale.pixels, second.normalizedGrayscale.pixels);
    expect(first.binary.pixels, second.binary.pixels);
    expect(
      first.diagnostics.sourceStatistics.meanIntensity,
      second.diagnostics.sourceStatistics.meanIntensity,
    );
  });

  test('known grayscale fixture reports correct statistics', () {
    final fixture = image.Image(width: 2, height: 2, numChannels: 3);
    final values = [0, 64, 128, 255];
    for (var index = 0; index < values.length; index++) {
      final value = values[index];
      fixture.setPixelRgb(index % 2, index ~/ 2, value, value, value);
    }
    final result = engine.process(
      _page(fixture),
      const PreprocessingConfig(
        enableIlluminationNormalization: false,
        enableDenoise: false,
        minimumIntensityStdDev: 0,
        darkPixelThreshold: 64,
        brightPixelThreshold: 200,
      ),
    );

    final statistics = result.value.diagnostics.sourceStatistics;
    expect(statistics.meanIntensity, closeTo(111.75, 0.001));
    expect(statistics.intensityStandardDeviation, closeTo(94.277, 0.01));
    expect(statistics.minimumIntensity, 0);
    expect(statistics.maximumIntensity, 255);
    expect(statistics.darkPixelRatio, 0.5);
    expect(statistics.brightPixelRatio, 0.25);
  });

  test('normalization measurably reduces an illumination gradient', () {
    final result = engine.process(
      _page(_gradient(96, 64, start: 80, end: 250)),
    );

    expect(result.isSuccess, isTrue);
    expect(
      result.value.diagnostics.normalizedStatistics.intensityStandardDeviation,
      lessThan(
        result.value.diagnostics.sourceStatistics.intensityStandardDeviation *
            0.5,
      ),
    );
  });

  test('faint mark remains darker than its local background', () {
    final fixture = _solid(80, 80, 240);
    image.fillCircle(
      fixture,
      x: 40,
      y: 40,
      radius: 7,
      color: image.ColorRgb8(185, 185, 185),
    );
    final output = engine.process(_page(fixture)).value.normalizedGrayscale;

    final markMean = _regionMean(output.pixels, 80, 36, 36, 44, 44);
    final paperMean = _regionMean(output.pixels, 80, 10, 10, 18, 18);
    expect(paperMean - markMean, greaterThan(20));
  });

  test('mild deterministic noise does not destroy a dark mark', () {
    final fixture = _solid(80, 80, 245);
    image.fillCircle(
      fixture,
      x: 40,
      y: 40,
      radius: 8,
      color: image.ColorRgb8(30, 30, 30),
    );
    final random = math.Random(17);
    for (var index = 0; index < 180; index++) {
      final x = random.nextInt(80);
      final y = random.nextInt(80);
      final value = random.nextBool() ? 210 : 255;
      fixture.setPixelRgb(x, y, value, value, value);
    }
    final result = engine.process(_page(fixture));

    expect(result.isSuccess, isTrue);
    final inkCount = _regionSum(result.value.binary.pixels, 80, 34, 34, 46, 46);
    expect(inkCount, greaterThan(100));
  });

  test('processing does not mutate canonical PNG bytes', () {
    final fixture = _gradient(48, 48, start: 100, end: 250);
    image.fillRect(
      fixture,
      x1: 20,
      y1: 20,
      x2: 27,
      y2: 27,
      color: image.ColorRgb8(0, 0, 0),
    );
    final canonical = _page(fixture);
    final before = Uint8List.fromList(canonical.pngBytes);

    final result = engine.process(canonical);

    expect(result.isSuccess, isTrue);
    expect(canonical.pngBytes, before);
  });
}

CanonicalPageImage _page(image.Image source) => CanonicalPageImage(
  size: ImageSize(width: source.width, height: source.height),
  pngBytes: _png(source),
);

Uint8List _png(image.Image source) =>
    Uint8List.fromList(image.encodePng(source));

image.Image _solid(int width, int height, int value) {
  final output = image.Image(width: width, height: height, numChannels: 3);
  image.fill(output, color: image.ColorRgb8(value, value, value));
  return output;
}

image.Image _gradient(
  int width,
  int height, {
  required int start,
  required int end,
}) {
  final output = image.Image(width: width, height: height, numChannels: 3);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final value = (start + (end - start) * x / (width - 1)).round();
      output.setPixelRgb(x, y, value, value, value);
    }
  }
  return output;
}

double _regionMean(
  Uint8List pixels,
  int width,
  int left,
  int top,
  int right,
  int bottom,
) {
  var sum = 0;
  var count = 0;
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      sum += pixels[y * width + x];
      count++;
    }
  }
  return sum / count;
}

int _regionSum(
  Uint8List pixels,
  int width,
  int left,
  int top,
  int right,
  int bottom,
) {
  var sum = 0;
  for (var y = top; y <= bottom; y++) {
    for (var x = left; x <= right; x++) {
      sum += pixels[y * width + x];
    }
  }
  return sum;
}
