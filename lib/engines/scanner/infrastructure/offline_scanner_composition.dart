import '../../aruco/domain/aruco_vision_backend.dart';
import '../../preprocessing/application/preprocessing_engine.dart';
import '../../preprocessing/domain/preprocessing_backend.dart';
import '../../recognition/application/bubble_measurement_engine.dart';
import '../../recognition/application/mark_classification_engine.dart';
import '../application/offline_scanner_engine.dart';
import '../domain/scanner_stages.dart';
import 'scanner_stage_adapters.dart';

abstract final class OfflineScannerComposition {
  static OfflineScannerEngine create({
    required ArucoVisionBackend alignmentBackend,
    required PreprocessingBackend preprocessingBackend,
    ScannerIdentityStage? identity,
  }) => OfflineScannerEngine(
    alignment: ArucoAlignmentStageAdapter(backend: alignmentBackend),
    preprocessing: PreprocessingStageAdapter(
      PreprocessingEngine(backend: preprocessingBackend),
    ),
    measurement: const BubbleMeasurementStageAdapter(BubbleMeasurementEngine()),
    classification: const MarkClassificationStageAdapter(
      MarkClassificationEngine(),
    ),
    identity: identity,
  );
}
