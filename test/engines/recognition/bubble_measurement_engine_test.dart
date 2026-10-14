import 'dart:typed_data';

import 'package:capstone_development/core/geometry/page_spec.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/preprocessing/domain/pixel_images.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessed_page.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessing_config.dart';
import 'package:capstone_development/engines/recognition/application/bubble_measurement_engine.dart';
import 'package:capstone_development/engines/recognition/application/canonical_bubble_mapper.dart';
import 'package:capstone_development/engines/recognition/domain/bubble_measurement.dart';
import 'package:capstone_development/engines/recognition/domain/bubble_measurement_config.dart';
import 'package:capstone_development/engines/recognition/domain/canonical_bubble_roi.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout/layout_test_fixtures.dart';

void main() {
  const mapper = CanonicalBubbleMapper();
  const engine = BubbleMeasurementEngine();

  test('canonical bubble mapping derives from physical geometry', () {
    final layout = _choiceLayout();
    final bubble = layout.bubbleRegions.first;
    final roi = mapper.map(bubble, layout, const BubbleMeasurementConfig());
    final scaleX =
        layout.canonicalPageSpec.widthPixels /
        layout.pageSpec.size.width.millimeters;
    final scaleY =
        layout.canonicalPageSpec.heightPixels /
        layout.pageSpec.size.height.millimeters;

    expect(
      roi.printedRadius,
      closeTo(
        bubble.physicalDiameter.millimeters /
            2 *
            (scaleX < scaleY ? scaleX : scaleY),
        1e-10,
      ),
    );
    expect(roi.interiorRadius, closeTo(roi.printedRadius * 0.68, 1e-10));
  });

  test('physical center maps to expected canonical pixel coordinates', () {
    final layout = _choiceLayout();
    final bubble = layout.bubbleRegions.first;
    final roi = mapper.map(bubble, layout, const BubbleMeasurementConfig());

    expect(
      roi.center.x,
      closeTo(
        bubble.physicalCenter.x.millimeters /
            layout.pageSpec.size.width.millimeters *
            layout.canonicalPageSpec.widthPixels,
        1e-10,
      ),
    );
    expect(
      roi.center.y,
      closeTo(
        bubble.physicalCenter.y.millimeters /
            layout.pageSpec.size.height.millimeters *
            layout.canonicalPageSpec.heightPixels,
        1e-10,
      ),
    );
  });

  test('circular membership uses deterministic pixel centers', () {
    final roi = CanonicalBubbleRoi(
      center: ImagePoint(10, 10),
      printedRadius: 3,
      interiorRadius: 1,
      baselineInnerRadius: 4,
      baselineOuterRadius: 5,
    );

    expect(roi.containsInteriorPixel(9, 9), isTrue);
    expect(roi.containsInteriorPixel(10, 10), isTrue);
    expect(roi.containsInteriorPixel(8, 9), isFalse);
    expect(roi.containsBaselinePixel(14, 9), isTrue);
  });

  test('printed outline is excluded from the inset interior ROI', () {
    final layout = _choiceLayout();
    final fixture = _fixture(layout);
    final roi = mapper.map(
      layout.bubbleRegions.first,
      layout,
      const BubbleMeasurementConfig(),
    );
    _paintRing(fixture, roi, innerRatio: 0.86, value: 0, foreground: 1);

    final measurement = _measure(engine, layout, fixture).measurements.first;
    expect(measurement.fillRatio, 0);
    expect(measurement.darknessContrast.abs(), lessThan(1));
  });

  test('blank bubble has low fill ratio', () {
    final layout = _choiceLayout();
    final measurement = _measure(
      engine,
      layout,
      _fixture(layout),
    ).measurements.first;

    expect(measurement.fillRatio, 0);
    expect(measurement.foregroundPixelCount, 0);
  });

  test('fully filled bubble has high fill ratio', () {
    final layout = _choiceLayout();
    final fixture = _fixture(layout);
    final roi = mapper.map(
      layout.bubbleRegions.first,
      layout,
      const BubbleMeasurementConfig(),
    );
    _paintInterior(fixture, roi, value: 50, foreground: 1);

    final measurement = _measure(engine, layout, fixture).measurements.first;
    expect(measurement.fillRatio, 1);
    expect(measurement.darknessContrast, greaterThan(150));
  });

  test('partially filled bubble returns intermediate evidence only', () {
    final layout = _choiceLayout();
    final fixture = _fixture(layout);
    final roi = mapper.map(
      layout.bubbleRegions.first,
      layout,
      const BubbleMeasurementConfig(),
    );
    _paintInterior(
      fixture,
      roi,
      value: 60,
      foreground: 1,
      include: (x, _) => x + 0.5 < roi.center.x,
    );

    final measurement = _measure(engine, layout, fixture).measurements.first;
    expect(measurement.fillRatio, inExclusiveRange(0.3, 0.7));
    expect(measurement.darknessContrast, inExclusiveRange(50, 150));
  });

  test('faint mark retains grayscale evidence when binary remains weak', () {
    final layout = _choiceLayout();
    final fixture = _fixture(layout);
    final roi = mapper.map(
      layout.bubbleRegions.first,
      layout,
      const BubbleMeasurementConfig(),
    );
    _paintInterior(fixture, roi, value: 190, foreground: 0);

    final measurement = _measure(engine, layout, fixture).measurements.first;
    expect(measurement.darknessContrast, greaterThan(40));
    expect(measurement.fillRatio, 0);
  });

  test('local gradient does not radically change darkness contrast', () {
    final layout = _choiceLayout();
    final uniform = _fixture(layout);
    final gradient = _fixture(layout, horizontalGradient: true);
    final roi = mapper.map(
      layout.bubbleRegions.first,
      layout,
      const BubbleMeasurementConfig(),
    );
    _paintInterior(uniform, roi, value: 180, foreground: 1);
    _darkenInterior(gradient, roi, amount: 60, foreground: 1);

    final uniformContrast = _measure(
      engine,
      layout,
      uniform,
    ).measurements.first.darknessContrast;
    final gradientContrast = _measure(
      engine,
      layout,
      gradient,
    ).measurements.first.darknessContrast;
    expect((uniformContrast - gradientContrast).abs(), lessThan(15));
  });

  test('baseline uses nearby paper context', () {
    final layout = _choiceLayout();
    final fixture = _fixture(layout, paperValue: 226);
    final measurement = _measure(engine, layout, fixture).measurements.first;

    expect(measurement.localBaselineIntensity, 226);
    expect(measurement.sampledBaselinePixelCount, greaterThan(12));
  });

  test('dark nearby label does not catastrophically skew robust baseline', () {
    final layout = _choiceLayout();
    final fixture = _fixture(layout);
    final roi = mapper.map(
      layout.bubbleRegions.first,
      layout,
      const BubbleMeasurementConfig(),
    );
    _paintBaselineSlice(fixture, roi, value: 0, foreground: 1);

    final measurement = _measure(engine, layout, fixture).measurements.first;
    expect(measurement.localBaselineIntensity, closeTo(240, 1));
    expect(measurement.quality.baselineForegroundRatio, greaterThan(0));
  });

  test('numeric-grid identity is preserved without fake option IDs', () {
    final layout = buildLayout(fullTemplate(), config: _config()).pages.first;
    final result = _measure(engine, layout, _fixture(layout));
    final numeric = result.measurements.firstWhere(
      (measurement) => measurement.numericColumnIndex != null,
    );

    expect(numeric.optionId, isNull);
    expect(numeric.numericColumnIndex, isNotNull);
    expect(numeric.numericDigitValue, inInclusiveRange(0, 9));
  });

  test('choice option identity is preserved exactly', () {
    final layout = _choiceLayout();
    final result = _measure(engine, layout, _fixture(layout));

    expect(
      result.measurements.first.optionId,
      layout.bubbleRegions.first.optionId,
    );
    expect(
      result.measurements.first.questionId,
      layout.bubbleRegions.first.questionId,
    );
  });

  test('measurement ordering matches PageLayout bubble ordering', () {
    final layout = _choiceLayout();
    final result = _measure(engine, layout, _fixture(layout));

    expect(
      result.measurements.map((measurement) => measurement.optionId).toList(),
      layout.bubbleRegions.map((bubble) => bubble.optionId).toList(),
    );
  });

  test('page-size mismatch returns a structured failure', () {
    final layout = _choiceLayout();
    final wrongLayout = _choiceLayout(
      canonicalPageSpec: CanonicalPageSpec(widthPixels: 210, heightPixels: 297),
    );
    final result = engine.measure(layout, _fixture(wrongLayout).page);

    expect(result.error.code, 'BUBBLE_MEASUREMENT_SIZE_MISMATCH');
  });

  test('invalid measurement config fails before sampling', () {
    final layout = _choiceLayout();
    final result = engine.measure(
      layout,
      _fixture(layout).page,
      const BubbleMeasurementConfig(interiorRadiusRatio: 1),
    );

    expect(result.error.code, 'BUBBLE_MEASUREMENT_INVALID_CONFIG');
  });

  test('too-small usable interior returns insufficient-pixels failure', () {
    final layout = _choiceLayout();
    final result = engine.measure(
      layout,
      _fixture(layout).page,
      const BubbleMeasurementConfig(minimumInteriorPixels: 10000),
    );

    expect(result.error.code, 'BUBBLE_MEASUREMENT_INSUFFICIENT_PIXELS');
    expect(result.error.details['questionId'], isNotNull);
  });

  test('insufficient baseline pixels return baseline failure', () {
    final layout = _choiceLayout();
    final result = engine.measure(
      layout,
      _fixture(layout).page,
      const BubbleMeasurementConfig(minimumBaselinePixels: 10000),
    );

    expect(result.error.code, 'BUBBLE_MEASUREMENT_BASELINE_INVALID');
  });

  test('measurement does not mutate preprocessing buffers', () {
    final layout = _choiceLayout();
    final fixture = _fixture(layout);
    final grayBefore = Uint8List.fromList(
      fixture.page.normalizedGrayscale.pixels,
    );
    final binaryBefore = Uint8List.fromList(fixture.page.binary.pixels);

    final result = engine.measure(layout, fixture.page);

    expect(result.isSuccess, isTrue);
    expect(fixture.page.normalizedGrayscale.pixels, grayBefore);
    expect(fixture.page.binary.pixels, binaryBefore);
  });

  test('identical inputs produce identical semantic measurements', () {
    final layout = _choiceLayout();
    final fixture = _fixture(layout);
    final first = _measure(engine, layout, fixture).measurements;
    final second = _measure(engine, layout, fixture).measurements;

    expect(first.length, second.length);
    for (var index = 0; index < first.length; index++) {
      expect(first[index].canonicalCenter, second[index].canonicalCenter);
      expect(first[index].fillRatio, second[index].fillRatio);
      expect(first[index].darknessContrast, second[index].darknessContrast);
      expect(
        first[index].sampledBaselinePixelCount,
        second[index].sampledBaselinePixelCount,
      );
    }
  });

  test('known adjacent bubble geometry is masked from baseline', () {
    final layout = _choiceLayout();
    final firstRoi = mapper.map(
      layout.bubbleRegions[0],
      layout,
      const BubbleMeasurementConfig(),
    );
    final secondRoi = mapper.map(
      layout.bubbleRegions[1],
      layout,
      const BubbleMeasurementConfig(),
    );
    final distance = firstRoi.center.distanceTo(secondRoi.center);
    final outerRatio = distance / firstRoi.printedRadius + 1;
    final config = BubbleMeasurementConfig(
      baselineOuterRadiusRatio: outerRatio,
      baselineInnerRadiusRatio: 1.1,
    );
    final fixture = _fixture(layout);
    _paintInterior(fixture, secondRoi, value: 0, foreground: 1);

    final result = engine.measure(layout, fixture.page, config);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(
      result.value.measurements.first.quality.neighborMaskedPixelCount,
      greaterThan(0),
    );
    expect(result.value.measurements.first.localBaselineIntensity, 240);
  });
}

PageLayout _choiceLayout({CanonicalPageSpec? canonicalPageSpec}) => buildLayout(
  templateWithQuestions([choiceQuestion('q', optionCount: 3)]),
  config: _config(canonicalPageSpec: canonicalPageSpec),
).pages.single;

LayoutConfig _config({CanonicalPageSpec? canonicalPageSpec}) => testConfig(
  canonicalPageSpec:
      canonicalPageSpec ??
      CanonicalPageSpec(widthPixels: 420, heightPixels: 594),
  bubbleDiameterMm: 6,
  optionCellWidthMm: 20,
);

BubbleMeasurementSet _measure(
  BubbleMeasurementEngine engine,
  PageLayout layout,
  _SyntheticFixture fixture,
) {
  final result = engine.measure(layout, fixture.page);
  expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
  return result.value;
}

final class _SyntheticFixture {
  _SyntheticFixture({
    required this.page,
    required this.normalized,
    required this.binary,
  });

  PreprocessedPage page;
  final Uint8List normalized;
  final Uint8List binary;
}

_SyntheticFixture _fixture(
  PageLayout layout, {
  int paperValue = 240,
  bool horizontalGradient = false,
}) {
  final size = ImageSize(
    width: layout.canonicalPageSpec.widthPixels,
    height: layout.canonicalPageSpec.heightPixels,
  );
  final normalized = Uint8List(size.area);
  final binary = Uint8List(size.area);
  for (var y = 0; y < size.height; y++) {
    for (var x = 0; x < size.width; x++) {
      normalized[y * size.width + x] = horizontalGradient
          ? (180 + 60 * x / (size.width - 1)).round()
          : paperValue;
    }
  }
  final grayscale = GrayImage(size: size, pixels: normalized);
  final page = PreprocessedPage(
    size: size,
    grayscale: grayscale,
    normalizedGrayscale: GrayImage(size: size, pixels: normalized),
    binary: BinaryImage(size: size, pixels: binary),
    diagnostics: const PreprocessingDiagnostics(
      sourceStatistics: _statistics,
      normalizedStatistics: _statistics,
      binaryForegroundRatio: 0,
      processingDuration: Duration.zero,
    ),
    config: const PreprocessingConfig(),
  );
  return _SyntheticFixture(page: page, normalized: normalized, binary: binary);
}

const _statistics = ImageStatistics(
  meanIntensity: 240,
  intensityStandardDeviation: 10,
  minimumIntensity: 0,
  maximumIntensity: 255,
  darkPixelRatio: 0,
  brightPixelRatio: 0,
);

void _paintInterior(
  _SyntheticFixture fixture,
  CanonicalBubbleRoi roi, {
  required int value,
  required int foreground,
  bool Function(int x, int y)? include,
}) {
  _forRoiPixels(fixture, roi, (x, y) {
    if (roi.containsInteriorPixel(x, y) && (include == null || include(x, y))) {
      final index = y * fixture.page.size.width + x;
      fixture.normalized[index] = value;
      fixture.binary[index] = foreground;
    }
  });
  _rebuildPageBuffers(fixture);
}

void _darkenInterior(
  _SyntheticFixture fixture,
  CanonicalBubbleRoi roi, {
  required int amount,
  required int foreground,
}) {
  _forRoiPixels(fixture, roi, (x, y) {
    if (roi.containsInteriorPixel(x, y)) {
      final index = y * fixture.page.size.width + x;
      fixture.normalized[index] = (fixture.normalized[index] - amount)
          .clamp(0, 255)
          .toInt();
      fixture.binary[index] = foreground;
    }
  });
  _rebuildPageBuffers(fixture);
}

void _paintRing(
  _SyntheticFixture fixture,
  CanonicalBubbleRoi roi, {
  required double innerRatio,
  required int value,
  required int foreground,
}) {
  _forRoiPixels(fixture, roi, (x, y) {
    final dx = x + 0.5 - roi.center.x;
    final dy = y + 0.5 - roi.center.y;
    final distanceSquared = dx * dx + dy * dy;
    if (distanceSquared >=
            roi.printedRadius * innerRatio * roi.printedRadius * innerRatio &&
        distanceSquared <= roi.printedRadius * roi.printedRadius) {
      final index = y * fixture.page.size.width + x;
      fixture.normalized[index] = value;
      fixture.binary[index] = foreground;
    }
  });
  _rebuildPageBuffers(fixture);
}

void _paintBaselineSlice(
  _SyntheticFixture fixture,
  CanonicalBubbleRoi roi, {
  required int value,
  required int foreground,
}) {
  _forRoiPixels(fixture, roi, (x, y) {
    if (roi.containsBaselinePixel(x, y) && x + 0.5 > roi.center.x) {
      final index = y * fixture.page.size.width + x;
      fixture.normalized[index] = value;
      fixture.binary[index] = foreground;
    }
  });
  _rebuildPageBuffers(fixture);
}

void _forRoiPixels(
  _SyntheticFixture fixture,
  CanonicalBubbleRoi roi,
  void Function(int x, int y) action,
) {
  final radius = roi.baselineOuterRadius;
  for (
    var y = (roi.center.y - radius - 1).floor();
    y <= (roi.center.y + radius + 1).ceil();
    y++
  ) {
    for (
      var x = (roi.center.x - radius - 1).floor();
      x <= (roi.center.x + radius + 1).ceil();
      x++
    ) {
      if (x >= 0 &&
          x < fixture.page.size.width &&
          y >= 0 &&
          y < fixture.page.size.height) {
        action(x, y);
      }
    }
  }
}

void _rebuildPageBuffers(_SyntheticFixture fixture) {
  final size = fixture.page.size;
  final replacement = PreprocessedPage(
    size: size,
    grayscale: GrayImage(size: size, pixels: fixture.normalized),
    normalizedGrayscale: GrayImage(size: size, pixels: fixture.normalized),
    binary: BinaryImage(size: size, pixels: fixture.binary),
    diagnostics: fixture.page.diagnostics,
    config: fixture.page.config,
  );
  // The fixture itself remains mutable only while constructing test evidence.
  fixture.page = replacement;
}
