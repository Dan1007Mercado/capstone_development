import 'dart:typed_data';

import '../../../core/result/engine_result.dart';
import '../../aruco/domain/aruco_alignment_config.dart';
import '../../aruco/domain/page_alignment_result.dart';
import '../../layout/domain/page_layout.dart';
import '../../preprocessing/domain/preprocessed_page.dart';
import '../../preprocessing/domain/preprocessing_config.dart';
import '../../recognition/domain/bubble_measurement.dart';
import '../../recognition/domain/bubble_measurement_config.dart';
import '../../recognition/domain/mark_classification.dart';
import '../../recognition/domain/mark_classification_config.dart';
import '../../template/domain/template_definition.dart';

abstract interface class ScannerAlignmentStage {
  EngineResult<PageAlignmentResult> align(
    Uint8List encodedImage,
    PageLayout page,
    ArucoAlignmentConfig config,
  );
}

abstract interface class ScannerPreprocessingStage {
  EngineResult<PreprocessedPage> process(
    CanonicalPageImage page,
    PreprocessingConfig config,
  );
}

abstract interface class ScannerMeasurementStage {
  EngineResult<BubbleMeasurementSet> measure(
    PageLayout layout,
    PreprocessedPage page,
    BubbleMeasurementConfig config,
  );
}

abstract interface class ScannerClassificationStage {
  EngineResult<PageClassificationResult> classify(
    TemplateDefinition template,
    PageLayout page,
    BubbleMeasurementSet measurements,
    MarkClassificationConfig config,
  );
}
