import 'dart:typed_data';

import 'package:capstone_development/core/geometry/page_spec.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_alignment_config.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/preprocessing/application/preprocessing_engine.dart';
import 'package:capstone_development/engines/preprocessing/infrastructure/dart_image_preprocessing_backend.dart';
import 'package:capstone_development/engines/recognition/application/bubble_measurement_engine.dart';
import 'package:capstone_development/engines/recognition/application/mark_classification_engine.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification.dart';
import 'package:capstone_development/engines/scanner/application/offline_scanner_engine.dart';
import 'package:capstone_development/engines/scanner/domain/scan_result.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_stages.dart';
import 'package:capstone_development/engines/scanner/infrastructure/scanner_stage_adapters.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:image/image.dart' as image;
import 'package:flutter_test/flutter_test.dart';

import '../layout/layout_test_fixtures.dart';

void main() {
  late TemplateDefinition template;
  late PageLayout page;

  setUp(() {
    template = templateWithQuestions([
      choiceQuestion('question', optionCount: 3),
    ]);
    page = buildLayout(
      template,
      config: testConfig(
        canonicalPageSpec: CanonicalPageSpec(
          widthPixels: 840,
          heightPixels: 1188,
        ),
        bubbleDiameterMm: 6,
        optionCellWidthMm: 20,
      ),
    ).pages.single;
  });

  test('real P6-P8 pipeline recognizes one clearly filled option', () {
    final canonical = _render(page, filledIndexes: const {1});

    final result = _scan(template, page, canonical);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    final question = result.value.questions.single;
    expect(question.state, MarkState.marked, reason: _describe(question));
    expect(question.selectedOptionIds, [page.bubbleRegions[1].optionId]);
    expect(result.value.pageState, ScanPageState.accepted);
  });

  test('real P6-P8 pipeline keeps an empty synthetic form blank', () {
    final result = _scan(template, page, _render(page));

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(
      result.value.questions.single.state,
      MarkState.blank,
      reason: _describe(result.value.questions.single),
    );
    expect(result.value.pageState, ScanPageState.accepted);
  });

  test('real P6-P8 pipeline reports two exclusive marks as multiple', () {
    final canonical = _render(page, filledIndexes: const {0, 2});

    final result = _scan(template, page, canonical);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(result.value.questions.single.state, MarkState.multiple);
    expect(result.value.pageState, ScanPageState.needsReview);
    expect(result.value.reviewReasons, [ScanReviewReason.multipleSelection]);
  });

  test('real P6-P8 pipeline retains useful evidence for a faint mark', () {
    final canonical = _render(
      page,
      filledIndexes: const {0},
      filledIntensity: 185,
    );

    final result = _scan(template, page, canonical);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    final question = result.value.questions.single;
    expect(question.state, MarkState.marked, reason: _describe(question));
    expect(question.selectedOptionIds, [page.bubbleRegions.first.optionId]);
    expect(question.bubbleDecisions.first.darknessContrast, greaterThan(12));
  });
}

String _describe(QuestionClassification question) => [
  'reason=${question.diagnostics.reason.name}',
  for (final bubble in question.bubbleDecisions)
    '${bubble.optionId?.value}: category=${bubble.category.name}, '
        'fill=${bubble.fillRatio.toStringAsFixed(3)}, '
        'dark=${bubble.normalizedDarkness.toStringAsFixed(3)}, '
        'contrast=${bubble.darknessContrast.toStringAsFixed(1)}, '
        'score=${bubble.combinedScore.toStringAsFixed(3)}, '
        'usable=${bubble.qualityUsable}',
].join('\n');

EngineResult<ScanResult> _scan(
  TemplateDefinition template,
  PageLayout page,
  CanonicalPageImage canonical,
) =>
    OfflineScannerEngine(
      alignment: _CanonicalAlignmentStage(canonical),
      preprocessing: const PreprocessingStageAdapter(
        PreprocessingEngine(backend: DartImagePreprocessingBackend()),
      ),
      measurement: const BubbleMeasurementStageAdapter(
        BubbleMeasurementEngine(),
      ),
      classification: const MarkClassificationStageAdapter(
        MarkClassificationEngine(),
      ),
    ).scan(
      encodedImage: Uint8List.fromList([10, 20, 30]),
      template: template,
      pageLayout: page,
      config: ScannerConfig(),
    );

CanonicalPageImage _render(
  PageLayout page, {
  Set<int> filledIndexes = const {},
  int filledIntensity = 20,
}) {
  final width = page.canonicalPageSpec.widthPixels;
  final height = page.canonicalPageSpec.heightPixels;
  final canvas = image.Image(width: width, height: height, numChannels: 3);
  image.fill(canvas, color: image.ColorRgb8(245, 245, 245));
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
      color: image.ColorRgb8(20, 20, 20),
    );
    image.fillCircle(
      canvas,
      x: centerX,
      y: centerY,
      radius: radius - 1,
      color: image.ColorRgb8(245, 245, 245),
    );
    if (filledIndexes.contains(index)) {
      image.fillCircle(
        canvas,
        x: centerX,
        y: centerY,
        radius: (radius * 0.65).round(),
        color: image.ColorRgb8(
          filledIntensity,
          filledIntensity,
          filledIntensity,
        ),
      );
    }
  }
  return CanonicalPageImage(
    size: ImageSize(width: width, height: height),
    pngBytes: image.encodePng(canvas),
  );
}

final class _CanonicalAlignmentStage implements ScannerAlignmentStage {
  const _CanonicalAlignmentStage(this.canonical);

  final CanonicalPageImage canonical;

  @override
  EngineResult<PageAlignmentResult> align(
    Uint8List encodedImage,
    PageLayout page,
    ArucoAlignmentConfig config,
  ) => EngineResult.success(
    PageAlignmentResult(
      canonicalPage: canonical,
      homography: HomographyMatrix(const [1, 0, 0, 0, 1, 0, 0, 0, 1]),
      observations: const [],
      correspondences: const [],
      diagnostics: PageAlignmentDiagnostics(
        expectedMarkerIds: page.markerRegions.map((region) => region.markerId),
        detectedMarkerIds: page.markerRegions.map((region) => region.markerId),
        sourceMarkerSideLengths: const [10, 10, 10, 10],
        sourceRegistrationPoints: const [],
        destinationRegistrationPoints: const [],
        registrationQuality: const RegistrationQuality(
          quadrilateralAreaRatio: 0.8,
          minimumMarkerSidePixels: 10,
          maximumPerspectiveRatio: 1,
        ),
        reprojectionErrors: const [0, 0, 0, 0],
        meanReprojectionError: 0,
        maxReprojectionError: 0,
        processingDuration: Duration.zero,
      ),
    ),
  );
}
