import 'dart:typed_data';

import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessing_config.dart';
import 'package:capstone_development/engines/preprocessing/application/preprocessing_engine.dart';
import 'package:capstone_development/engines/preprocessing/infrastructure/dart_image_preprocessing_backend.dart';
import 'package:capstone_development/engines/preprocessing/infrastructure/opencv_preprocessing_backend.dart';
import 'package:capstone_development/engines/recognition/application/bubble_measurement_engine.dart';
import 'package:capstone_development/engines/recognition/application/mark_classification_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import '../layout/layout_test_fixtures.dart';

void main() {
  const dartBackend = DartImagePreprocessingBackend();
  const nativeBackend = OpenCvPreprocessingBackend();
  const config = PreprocessingConfig(minimumIntensityStdDev: 0);

  test('native transfer preserves a strided-owner byte view and dimensions', () {
    final backing = Uint8List.fromList(List.generate(90, (i) => i * 17 % 256));
    final pixels = Uint8List.sublistView(backing, 3, 80);
    final page = CanonicalPageImage.ownedGrayscale(
      size: ImageSize(width: 7, height: 11),
      grayscaleBytes: pixels,
    );
    const untouched = PreprocessingConfig(
      enableDenoise: false,
      enableIlluminationNormalization: false,
      minimumIntensityStdDev: 0,
    );
    final native = nativeBackend.process(page, untouched);
    if (_nativeUnavailable(native.errorOrNull)) {
      markTestSkipped('Native OpenCV is unavailable on this host.');
      return;
    }
    expect(native.isSuccess, isTrue, reason: native.errorOrNull?.toString());
    expect(native.value.normalizedGrayscale.size, page.size);
    expect(native.value.normalizedGrayscale.pixels, pixels);
    expect(native.value.binary.pixels, everyElement(anyOf(0, 1)));
    // A later allocation/process must not invalidate the returned detached data.
    expect(nativeBackend.process(page, config).isSuccess, isTrue);
    expect(native.value.normalizedGrayscale.pixels, pixels);
  });

  for (final fixture in <String, Uint8List>{
    'uniform bright': Uint8List.fromList(List.filled(49, 255)),
    'uniform dark': Uint8List.fromList(List.filled(49, 0)),
    'gradient and edge marks': Uint8List.fromList([
      0,
      40,
      80,
      120,
      160,
      200,
      240,
      20,
      50,
      90,
      130,
      170,
      210,
      250,
      30,
      60,
      0,
      0,
      180,
      220,
      255,
      40,
      70,
      0,
      0,
      190,
      230,
      255,
      50,
      80,
      120,
      150,
      200,
      240,
      255,
      60,
      90,
      130,
      160,
      210,
      245,
      255,
      0,
      100,
      140,
      170,
      220,
      250,
      0,
    ]),
    'dark bubble mark': _darkBubble(),
    'deterministic noise': _noise(),
    'multiple local contrast regions': _localContrastRegions(),
  }.entries) {
    test('native P6 matches Dart P6 for ${fixture.key}', () {
      final page = CanonicalPageImage.ownedGrayscale(
        size: ImageSize(width: 7, height: 7),
        grayscaleBytes: Uint8List.fromList(fixture.value),
      );
      final dart = dartBackend.process(page, config);
      final native = nativeBackend.process(page, config);
      if (_nativeUnavailable(native.errorOrNull)) {
        markTestSkipped('Native OpenCV is unavailable on this host.');
        return;
      }
      expect(
        native.isSuccess,
        isTrue,
        reason: '${native.errorOrNull}: ${native.errorOrNull?.details}',
      );
      expect(native.value.grayscale.pixels, dart.value.grayscale.pixels);
      expect(
        _maximumDifference(
          native.value.normalizedGrayscale.pixels,
          dart.value.normalizedGrayscale.pixels,
        ),
        lessThanOrEqualTo(1),
      );
      expect(native.value.binary.pixels, dart.value.binary.pixels);
      expect(native.value.binaryForegroundCount, isNotNull);
      expect(native.value.sourceStatistics, isNotNull);
      expect(native.value.normalizedStatistics, isNotNull);
    });
  }

  test(
    'native parity preserves downstream measurements and classification',
    () {
      final template = templateWithQuestions([
        choiceQuestion('question', optionCount: 3),
      ]);
      final page = buildLayout(template).pages.single;
      final canonical = _markedCanonicalPage(page);
      const dartEngine = PreprocessingEngine(
        backend: DartImagePreprocessingBackend(),
      );
      const nativeEngine = PreprocessingEngine(
        backend: OpenCvPreprocessingBackend(),
      );
      final dart = dartEngine.process(canonical);
      final native = nativeEngine.process(canonical);
      if (_nativeUnavailable(native.errorOrNull)) {
        markTestSkipped('Native OpenCV is unavailable on this host.');
        return;
      }
      expect(
        native.isSuccess,
        isTrue,
        reason: '${native.errorOrNull}: ${native.errorOrNull?.details}',
      );
      const measurementEngine = BubbleMeasurementEngine();
      final dartMeasurements = measurementEngine
          .measure(page, dart.value)
          .value;
      final nativeMeasurements = measurementEngine
          .measure(page, native.value)
          .value;
      expect(nativeMeasurements.measurements, hasLength(3));
      for (
        var index = 0;
        index < dartMeasurements.measurements.length;
        index++
      ) {
        expect(
          nativeMeasurements.measurements[index].fillRatio,
          closeTo(dartMeasurements.measurements[index].fillRatio, 0.01),
        );
        expect(
          nativeMeasurements.measurements[index].darknessContrast,
          closeTo(dartMeasurements.measurements[index].darknessContrast, 1),
        );
      }
      const classificationEngine = MarkClassificationEngine();
      final dartClassification = classificationEngine
          .classify(template, page, dartMeasurements)
          .value;
      final nativeClassification = classificationEngine
          .classify(template, page, nativeMeasurements)
          .value;
      expect(
        nativeClassification.questions.single.state,
        dartClassification.questions.single.state,
      );
      expect(
        nativeClassification.questions.single.selectedOptionIds,
        dartClassification.questions.single.selectedOptionIds,
      );
    },
  );
}

bool _nativeUnavailable(Object? error) {
  final details = error is EngineError ? error.details : const {};
  final text = '$error $details'.toLowerCase();
  return text.contains('dynamic library') ||
      text.contains('failed to load') ||
      text.contains('symbol');
}

Uint8List _darkBubble() => Uint8List.fromList([
  for (var y = 0; y < 7; y++)
    for (var x = 0; x < 7; x++)
      (x - 3) * (x - 3) + (y - 3) * (y - 3) <= 4 ? 20 : 240,
]);

Uint8List _noise() => Uint8List.fromList(
  List.generate(49, (index) => 180 + ((index * 37 + 11) % 70)),
);

Uint8List _localContrastRegions() => Uint8List.fromList([
  for (var y = 0; y < 7; y++)
    for (var x = 0; x < 7; x++)
      if (x < 3 && y < 3) 40 else if (x > 3 && y > 3) 245 else 150,
]);

CanonicalPageImage _markedCanonicalPage(PageLayout page) {
  final width = page.canonicalPageSpec.widthPixels;
  final height = page.canonicalPageSpec.heightPixels;
  final canvas = image.Image(width: width, height: height, numChannels: 1);
  final paper = image.ColorUint8.fromList(const [245]);
  final ink = image.ColorUint8.fromList(const [20]);
  image.fill(canvas, color: paper);
  for (var index = 0; index < page.bubbleRegions.length; index++) {
    final bubble = page.bubbleRegions[index];
    final centerX = (bubble.normalizedCenter.x.value * width).round();
    final centerY = (bubble.normalizedCenter.y.value * height).round();
    final radius = (bubble.normalizedBounds.width.value * width / 2).round();
    image.fillCircle(
      canvas,
      x: centerX,
      y: centerY,
      radius: radius,
      color: ink,
    );
    image.fillCircle(
      canvas,
      x: centerX,
      y: centerY,
      radius: radius - 1,
      color: paper,
    );
    if (index == 1) {
      image.fillCircle(
        canvas,
        x: centerX,
        y: centerY,
        radius: (radius * 0.65).round(),
        color: ink,
      );
    }
  }
  return CanonicalPageImage.ownedGrayscale(
    size: ImageSize(width: width, height: height),
    grayscaleBytes: Uint8List.fromList(canvas.getBytes()),
  );
}

int _maximumDifference(Uint8List first, Uint8List second) {
  var maximum = 0;
  for (var index = 0; index < first.length; index++) {
    final difference = (first[index] - second[index]).abs();
    if (difference > maximum) maximum = difference;
  }
  return maximum;
}
