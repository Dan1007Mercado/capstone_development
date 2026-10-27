import 'dart:typed_data';

import 'package:capstone_development/core/geometry/page_spec.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/layout/application/layout_engine.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/preprocessing/domain/pixel_images.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessed_page.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessing_config.dart';
import 'package:capstone_development/engines/recognition/application/bubble_measurement_engine.dart';
import 'package:capstone_development/engines/recognition/application/canonical_bubble_mapper.dart';
import 'package:capstone_development/engines/recognition/application/mark_classification_engine.dart';
import 'package:capstone_development/engines/recognition/domain/bubble_measurement.dart';
import 'package:capstone_development/engines/recognition/domain/bubble_measurement_config.dart';
import 'package:capstone_development/engines/recognition/domain/canonical_bubble_roi.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/domain/template_option.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:capstone_development/engines/template/domain/template_section.dart';
import 'package:capstone_development/engines/template/domain/template_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const measurementEngine = BubbleMeasurementEngine();
  const classifier = MarkClassificationEngine();
  const mapper = CanonicalBubbleMapper();
  late TemplateDefinition template;
  late PageLayout page;

  setUp(() {
    template = _template();
    final generated = LayoutEngine()
        .build(template, LayoutConfig.a4AnswerSheet().withFixedColumnCount(3))
        .value
        .pages
        .single;
    page = _withSmallCanonicalPage(generated);
  });

  test('printed center glyph alone remains BLANK', () {
    final fixture = _fixture(page);
    for (final bubble in page.bubbleRegions) {
      final roi = mapper.map(bubble, page, const BubbleMeasurementConfig());
      _paintCenterGlyph(fixture, roi);
    }

    final measurements = _measure(measurementEngine, page, fixture);
    expect(
      measurements.measurements.every((item) => item.fillRatio == 0),
      isTrue,
    );
    expect(
      measurements.measurements.every(
        (item) => item.roi.centerExclusionRadius > 0,
      ),
      isTrue,
    );
    expect(
      _classify(classifier, template, page, measurements).state,
      MarkState.blank,
    );
  });

  test('filled labeled bubble remains MARKED', () {
    final fixture = _fixture(page);
    _paintAllMeasuredPixels(fixture, _roi(page, 1));

    final measurements = _measure(measurementEngine, page, fixture);
    final result = _classify(classifier, template, page, measurements);
    expect(measurements.measurements[1].fillRatio, 1);
    expect(result.state, MarkState.marked);
    expect(result.selectedOptionIds.single, page.bubbleRegions[1].optionId);
  });

  test('two filled labeled bubbles remain MULTIPLE', () {
    final fixture = _fixture(page);
    _paintAllMeasuredPixels(fixture, _roi(page, 0));
    _paintAllMeasuredPixels(fixture, _roi(page, 2));

    final result = _classify(
      classifier,
      template,
      page,
      _measure(measurementEngine, page, fixture),
    );
    expect(result.state, MarkState.multiple);
  });

  for (final style in [
    'half',
    'crescent',
    'distributed dots',
    'X',
    'light fill',
  ]) {
    test('controlled labeled $style retains a selected answer', () {
      final fixture = _fixture(page);
      final roi = _roi(page, 1);
      _paint(fixture, roi, (x, y) {
        if (!roi.containsPrintedPixel(x, y)) return false;
        final dx = (x + 0.5 - roi.center.x) / roi.printedRadius;
        final dy = (y + 0.5 - roi.center.y) / roi.printedRadius;
        return switch (style) {
          'half' => dx < 0,
          'crescent' => dx < -0.2,
          'distributed dots' =>
            (dx.abs() - 0.55).abs() < 0.2 && dy.abs() < 0.2 ||
                (dy.abs() - 0.55).abs() < 0.2 && dx.abs() < 0.2,
          'X' => (dx - dy).abs() < 0.22 || (dx + dy).abs() < 0.22,
          _ => true,
        };
      });
      // These fixtures start at measurement-ready buffers. They establish
      // classification requirements, not preprocessing or physical accuracy.
      if (style == 'light fill') {
        for (var i = 0; i < fixture.normalized.length; i++) {
          if (fixture.binary[i] == 1) fixture.normalized[i] = 150;
        }
        fixture.page = _page(
          fixture.page.size,
          fixture.normalized,
          fixture.binary,
        );
      }
      final result = _classify(
        classifier,
        template,
        page,
        _measure(measurementEngine, page, fixture),
      );
      expect(result.state, MarkState.marked);
      expect(result.selectedOptionIds.single, page.bubbleRegions[1].optionId);
    });
  }

  test(
    'a centered dot hidden by label exclusion supplies no mark evidence',
    () {
      final fixture = _fixture(page);
      final roi = _roi(page, 1);
      _paint(fixture, roi, (x, y) {
        final dx = x + 0.5 - roi.center.x;
        final dy = y + 0.5 - roi.center.y;
        return dx * dx + dy * dy <
            roi.centerExclusionRadius * roi.centerExclusionRadius;
      });
      expect(fixture.binary.any((v) => v == 1), isTrue);
      final measured = _measure(measurementEngine, page, fixture);
      expect(measured.measurements[1].foregroundPixelCount, 0);
      expect(
        _classify(classifier, template, page, measured).state,
        MarkState.blank,
      );
    },
  );

  test('similar partial marks in labeled bubbles remain AMBIGUOUS', () {
    final fixture = _fixture(page);
    _paintPartialMeasuredPixels(fixture, _roi(page, 0));
    _paintPartialMeasuredPixels(fixture, _roi(page, 1));

    final measurements = _measure(measurementEngine, page, fixture);
    final result = _classify(classifier, template, page, measurements);
    expect(
      measurements.measurements[0].fillRatio,
      inExclusiveRange(0.12, 0.45),
    );
    expect(
      measurements.measurements[1].fillRatio,
      inExclusiveRange(0.12, 0.45),
    );
    expect(result.state, MarkState.ambiguous);
  });
}

TemplateDefinition _template() => TemplateDefinition(
  id: TemplateId('p14-2-recognition'),
  version: TemplateVersion(1),
  name: 'Labeled Bubble Recognition',
  status: TemplateStatus.draft,
  sections: [
    TemplateSection(
      id: SectionId('answers'),
      title: 'ANSWERS',
      questions: [
        TemplateQuestion(
          id: QuestionId('q1'),
          type: QuestionType.singleChoice,
          prompt: 'Prompt is on the questionnaire.',
          options: [
            for (var index = 0; index < 3; index++)
              TemplateOption(id: OptionId('o$index'), label: 'Option $index'),
          ],
        ),
      ],
    ),
  ],
);

PageLayout _withSmallCanonicalPage(PageLayout source) => PageLayout(
  templateId: source.templateId,
  templateVersion: source.templateVersion,
  pageId: source.pageId,
  pageIndex: source.pageIndex,
  totalPageCount: source.totalPageCount,
  pageSpec: source.pageSpec,
  canonicalPageSpec: CanonicalPageSpec(widthPixels: 420, heightPixels: 594),
  physicalPageBounds: source.physicalPageBounds,
  normalizedPageBounds: source.normalizedPageBounds,
  printableBounds: source.printableBounds,
  normalizedPrintableBounds: source.normalizedPrintableBounds,
  safeBounds: source.safeBounds,
  normalizedSafeBounds: source.normalizedSafeBounds,
  markerRegions: source.markerRegions,
  templateIdentityRegion: source.templateIdentityRegion,
  headerRegion: source.headerRegion,
  contentColumnRegions: source.contentColumnRegions,
  sectionRegions: source.sectionRegions,
  questionRegions: source.questionRegions,
  bubbleRegions: source.bubbleRegions,
);

CanonicalBubbleRoi _roi(PageLayout page, int index) =>
    const CanonicalBubbleMapper().map(
      page.bubbleRegions[index],
      page,
      const BubbleMeasurementConfig(),
    );

BubbleMeasurementSet _measure(
  BubbleMeasurementEngine engine,
  PageLayout page,
  _Fixture fixture,
) {
  final result = engine.measure(page, fixture.page);
  expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
  return result.value;
}

QuestionClassification _classify(
  MarkClassificationEngine engine,
  TemplateDefinition template,
  PageLayout page,
  BubbleMeasurementSet measurements,
) {
  final result = engine.classify(template, page, measurements);
  expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
  return result.value.questions.single;
}

final class _Fixture {
  _Fixture({
    required this.page,
    required this.normalized,
    required this.binary,
  });

  PreprocessedPage page;
  final Uint8List normalized;
  final Uint8List binary;
}

_Fixture _fixture(PageLayout layout) {
  final size = ImageSize(
    width: layout.canonicalPageSpec.widthPixels,
    height: layout.canonicalPageSpec.heightPixels,
  );
  final normalized = Uint8List(size.area)..fillRange(0, size.area, 240);
  final binary = Uint8List(size.area);
  final fixture = _Fixture(
    page: _page(size, normalized, binary),
    normalized: normalized,
    binary: binary,
  );
  return fixture;
}

PreprocessedPage _page(
  ImageSize size,
  Uint8List normalized,
  Uint8List binary,
) => PreprocessedPage(
  size: size,
  grayscale: GrayImage(size: size, pixels: normalized),
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

const _statistics = ImageStatistics(
  meanIntensity: 240,
  intensityStandardDeviation: 10,
  minimumIntensity: 0,
  maximumIntensity: 255,
  darkPixelRatio: 0,
  brightPixelRatio: 0,
);

void _paintCenterGlyph(_Fixture fixture, CanonicalBubbleRoi roi) {
  _paint(fixture, roi, (x, y) {
    final dx = x + 0.5 - roi.center.x;
    final dy = y + 0.5 - roi.center.y;
    return dx * dx + dy * dy <
        roi.centerExclusionRadius * roi.centerExclusionRadius;
  });
}

void _paintAllMeasuredPixels(_Fixture fixture, CanonicalBubbleRoi roi) =>
    _paint(fixture, roi, roi.containsInteriorPixel);

void _paintPartialMeasuredPixels(_Fixture fixture, CanonicalBubbleRoi roi) =>
    _paint(
      fixture,
      roi,
      (x, y) =>
          roi.containsInteriorPixel(x, y) &&
          y + 0.5 < roi.center.y - roi.interiorRadius * 0.55,
    );

void _paint(
  _Fixture fixture,
  CanonicalBubbleRoi roi,
  bool Function(int x, int y) include,
) {
  final radius = roi.printedRadius.ceil() + 1;
  for (
    var y = (roi.center.y - radius).floor();
    y <= (roi.center.y + radius).ceil();
    y++
  ) {
    for (
      var x = (roi.center.x - radius).floor();
      x <= (roi.center.x + radius).ceil();
      x++
    ) {
      if (x < 0 ||
          y < 0 ||
          x >= fixture.page.size.width ||
          y >= fixture.page.size.height ||
          !include(x, y)) {
        continue;
      }
      final index = y * fixture.page.size.width + x;
      fixture.normalized[index] = 30;
      fixture.binary[index] = 1;
    }
  }
  fixture.page = _page(fixture.page.size, fixture.normalized, fixture.binary);
}
