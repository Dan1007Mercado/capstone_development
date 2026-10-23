import 'dart:typed_data';

import 'package:capstone_development/application/template_builder/template_builder_controller.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_alignment_config.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/preprocessing/application/preprocessing_engine.dart';
import 'package:capstone_development/engines/preprocessing/infrastructure/dart_image_preprocessing_backend.dart';
import 'package:capstone_development/engines/recognition/application/bubble_measurement_engine.dart';
import 'package:capstone_development/engines/recognition/application/mark_classification_engine.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification.dart';
import 'package:capstone_development/engines/scanner/application/offline_scanner_engine.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_stages.dart';
import 'package:capstone_development/engines/scanner/infrastructure/scanner_stage_adapters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test(
    'builder definition and exact PageLayout remain scanner compatible',
    () {
      final controller = TemplateBuilderController(name: 'Scanner Template');
      final section = controller.addSection(title: 'Answers');
      controller.addQuestion(section, prompt: 'Select one');
      final preview = controller.previewLayout().value;
      final page = preview.layout.pages.single;
      final canonical = _renderMarkedPage(page, filledBubbleIndex: 1);

      final result =
          OfflineScannerEngine(
            alignment: _CanonicalAlignment(canonical),
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
            encodedImage: Uint8List.fromList(const [1, 2, 3]),
            template: preview.definition,
            pageLayout: page,
            config: ScannerConfig(),
          );

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      expect(result.value.questions.single.state, MarkState.marked);
      expect(
        result.value.questions.single.selectedOptionIds.single,
        page.bubbleRegions[1].optionId,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'answer-sheet PageLayout and labeled bubbles traverse offline scanner',
    () {
      final controller = TemplateBuilderController(
        name: 'Answer Scanner Template',
      );
      final section = controller.addSection(title: 'Answers');
      controller.addQuestion(section, prompt: 'Prompt is separate');
      final definition = controller.snapshot.definition;
      final preview = controller
          .previewDefinition(
            definition,
            layoutConfig: LayoutConfig.a4AnswerSheet(),
          )
          .value;
      final page = preview.layout.pages.single;
      final canonical = _renderMarkedPage(
        page,
        filledBubbleIndex: 1,
        drawPrintedGlyphs: true,
      );

      final result =
          OfflineScannerEngine(
            alignment: _CanonicalAlignment(canonical),
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
            encodedImage: Uint8List.fromList(const [1, 2, 3]),
            template: definition,
            pageLayout: page,
            config: ScannerConfig(),
          );

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      expect(result.value.questions.single.state, MarkState.marked);
      expect(
        result.value.questions.single.selectedOptionIds.single,
        page.bubbleRegions[1].optionId,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

CanonicalPageImage _renderMarkedPage(
  PageLayout page, {
  required int filledBubbleIndex,
  bool drawPrintedGlyphs = false,
}) {
  final width = page.canonicalPageSpec.widthPixels;
  final height = page.canonicalPageSpec.heightPixels;
  final canvas = image.Image(width: width, height: height, numChannels: 1);
  final paper = image.ColorUint8.fromList(const [245]);
  final ink = image.ColorUint8.fromList(const [20]);
  image.fill(canvas, color: paper);
  for (var index = 0; index < page.bubbleRegions.length; index++) {
    final bubble = page.bubbleRegions[index];
    final x = (bubble.normalizedCenter.x.value * width).round();
    final y = (bubble.normalizedCenter.y.value * height).round();
    final radius = (bubble.normalizedBounds.width.value * width / 2).round();
    image.fillCircle(canvas, x: x, y: y, radius: radius, color: ink);
    image.fillCircle(canvas, x: x, y: y, radius: radius - 1, color: paper);
    if (drawPrintedGlyphs && bubble.printedLabel != null) {
      image.fillCircle(
        canvas,
        x: x,
        y: y,
        radius: (radius * bubble.measurementCenterExclusionRatio * 0.9).round(),
        color: ink,
      );
    }
    if (index == filledBubbleIndex) {
      image.fillCircle(
        canvas,
        x: x,
        y: y,
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

final class _CanonicalAlignment implements ScannerAlignmentStage {
  const _CanonicalAlignment(this.canonical);

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
        expectedMarkerIds: page.markerRegions.map((marker) => marker.markerId),
        detectedMarkerIds: page.markerRegions.map((marker) => marker.markerId),
        sourceMarkerSideLengths: const [100, 100, 100, 100],
        sourceRegistrationPoints: const [],
        destinationRegistrationPoints: const [],
        registrationQuality: const RegistrationQuality(
          quadrilateralAreaRatio: 0.8,
          minimumMarkerSidePixels: 100,
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
