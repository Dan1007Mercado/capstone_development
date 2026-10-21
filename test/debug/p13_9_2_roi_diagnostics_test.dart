import 'dart:typed_data';

import 'package:capstone_development/debug/p11_1_scanner_validation_sheet.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/preprocessing/domain/pixel_images.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessed_page.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessing_config.dart';
import 'package:capstone_development/engines/recognition/application/bubble_measurement_engine.dart';
import 'package:capstone_development/engines/recognition/application/canonical_bubble_mapper.dart';
import 'package:capstone_development/engines/recognition/domain/bubble_measurement_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Q4 diagnostics retain authoritative identities and mapper ROIs', () {
    final inputs = buildP11ScannerValidationSheetInputs();
    final page = inputs.layout.pages.first;
    const config = BubbleMeasurementConfig();
    const mapper = CanonicalBubbleMapper();
    final size = ImageSize(
      width: page.canonicalPageSpec.widthPixels,
      height: page.canonicalPageSpec.heightPixels,
    );
    final white = Uint8List(size.area)..fillRange(0, size.area, 255);
    final result = const BubbleMeasurementEngine().measure(
      page,
      PreprocessedPage(
        size: size,
        grayscale: GrayImage.owned(size: size, pixels: white),
        normalizedGrayscale: GrayImage.owned(size: size, pixels: white),
        binary: BinaryImage.owned(size: size, pixels: Uint8List(size.area)),
        diagnostics: const PreprocessingDiagnostics(
          sourceStatistics: _whiteStatistics,
          normalizedStatistics: _whiteStatistics,
          binaryForegroundRatio: 0,
          processingDuration: Duration.zero,
        ),
        config: const PreprocessingConfig(),
      ),
      config,
    );

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    final q4Bubbles = page.bubbleRegions
        .where((bubble) => bubble.questionId.value == 'q4')
        .toList(growable: false);
    final q4Measurements = result.value.measurements
        .where((measurement) => measurement.questionId.value == 'q4')
        .toList(growable: false);
    expect(q4Bubbles.map((bubble) => bubble.optionId!.value), [
      'q4-1',
      'q4-2',
      'q4-3',
      'q4-4',
    ]);
    expect(q4Measurements.map((measurement) => measurement.optionId!.value), [
      'q4-1',
      'q4-2',
      'q4-3',
      'q4-4',
    ]);

    for (var index = 0; index < q4Bubbles.length; index++) {
      final expected = mapper.map(q4Bubbles[index], page, config);
      final diagnostic = q4Measurements[index].roi;
      expect(diagnostic.center, expected.center);
      expect(diagnostic.printedRadius, expected.printedRadius);
      expect(diagnostic.interiorRadius, expected.interiorRadius);
      expect(diagnostic.baselineInnerRadius, expected.baselineInnerRadius);
      expect(diagnostic.baselineOuterRadius, expected.baselineOuterRadius);
    }
  });
}

const _whiteStatistics = ImageStatistics(
  meanIntensity: 255,
  intensityStandardDeviation: 0,
  minimumIntensity: 255,
  maximumIntensity: 255,
  darkPixelRatio: 0,
  brightPixelRatio: 1,
);
