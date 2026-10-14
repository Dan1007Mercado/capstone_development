import '../../aruco/domain/aruco_alignment_config.dart';
import '../../preprocessing/domain/preprocessing_config.dart';
import '../../recognition/domain/bubble_measurement_config.dart';
import '../../recognition/domain/mark_classification_config.dart';

enum RequiredQuestionPolicy { needsReview, ignore }

final class ScannerConfig {
  factory ScannerConfig({
    ArucoAlignmentConfig? alignment,
    PreprocessingConfig preprocessing = const PreprocessingConfig(),
    BubbleMeasurementConfig measurement = const BubbleMeasurementConfig(),
    MarkClassificationConfig classification = const MarkClassificationConfig(),
    RequiredQuestionPolicy requiredQuestionPolicy =
        RequiredQuestionPolicy.needsReview,
  }) => ScannerConfig._(
    alignment: alignment ?? ArucoAlignmentConfig(),
    preprocessing: preprocessing,
    measurement: measurement,
    classification: classification,
    requiredQuestionPolicy: requiredQuestionPolicy,
  );

  const ScannerConfig._({
    required this.alignment,
    required this.preprocessing,
    required this.measurement,
    required this.classification,
    required this.requiredQuestionPolicy,
  });

  final ArucoAlignmentConfig alignment;
  final PreprocessingConfig preprocessing;
  final BubbleMeasurementConfig measurement;
  final MarkClassificationConfig classification;
  final RequiredQuestionPolicy requiredQuestionPolicy;
}
