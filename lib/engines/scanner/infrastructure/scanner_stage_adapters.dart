import 'dart:typed_data';

import '../../../core/result/engine_result.dart';
import '../../aruco/application/aruco_alignment_engine.dart';
import '../../aruco/application/marker_correspondence_service.dart';
import '../../aruco/domain/aruco_alignment_config.dart';
import '../../aruco/domain/aruco_vision_backend.dart';
import '../../aruco/domain/page_alignment_result.dart';
import '../../layout/domain/page_layout.dart';
import '../../preprocessing/application/preprocessing_engine.dart';
import '../../preprocessing/domain/preprocessed_page.dart';
import '../../preprocessing/domain/preprocessing_config.dart';
import '../../recognition/application/bubble_measurement_engine.dart';
import '../../recognition/application/mark_classification_engine.dart';
import '../../recognition/domain/bubble_measurement.dart';
import '../../recognition/domain/bubble_measurement_config.dart';
import '../../recognition/domain/mark_classification.dart';
import '../../recognition/domain/mark_classification_config.dart';
import '../../template/domain/template_definition.dart';
import '../domain/scanner_stages.dart';

final class ArucoAlignmentStageAdapter implements ScannerAlignmentStage {
  const ArucoAlignmentStageAdapter({
    required this.backend,
    this.correspondenceService = const MarkerCorrespondenceService(),
  });

  final ArucoVisionBackend backend;
  final MarkerCorrespondenceService correspondenceService;

  @override
  EngineResult<PageAlignmentResult> align(
    Uint8List encodedImage,
    PageLayout page,
    ArucoAlignmentConfig config,
  ) => ArucoAlignmentEngine(
    backend: backend,
    correspondenceService: correspondenceService,
    config: config,
  ).align(encodedImage, page);
}

final class PreprocessingStageAdapter implements ScannerPreprocessingStage {
  const PreprocessingStageAdapter(this.engine);

  final PreprocessingEngine engine;

  @override
  EngineResult<PreprocessedPage> process(
    CanonicalPageImage page,
    PreprocessingConfig config,
  ) => engine.process(page, config);
}

final class BubbleMeasurementStageAdapter implements ScannerMeasurementStage {
  const BubbleMeasurementStageAdapter(this.engine);

  final BubbleMeasurementEngine engine;

  @override
  EngineResult<BubbleMeasurementSet> measure(
    PageLayout layout,
    PreprocessedPage page,
    BubbleMeasurementConfig config,
  ) => engine.measure(layout, page, config);
}

final class MarkClassificationStageAdapter
    implements ScannerClassificationStage {
  const MarkClassificationStageAdapter(this.engine);

  final MarkClassificationEngine engine;

  @override
  EngineResult<PageClassificationResult> classify(
    TemplateDefinition template,
    PageLayout page,
    BubbleMeasurementSet measurements,
    MarkClassificationConfig config,
  ) => engine.classify(template, page, measurements, config);
}
