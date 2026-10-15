import 'dart:typed_data';

import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/debug/p11_1_scanner_validation_sheet.dart';
import 'package:capstone_development/debug/p11_2_known_answer_fixture.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_alignment_config.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
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

void main() {
  test(
    'all three authoritative pages classify deterministic known answers',
    () {
      final inputs = buildP11ScannerValidationSheetInputs();
      final results = <String, QuestionClassification>{};

      for (final page in inputs.layout.pages) {
        final canonical = renderP11KnownAnswerPage(page);
        final scan =
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
              template: inputs.template,
              pageLayout: page,
              config: ScannerConfig(),
            );
        expect(scan.isSuccess, isTrue, reason: scan.errorOrNull?.toString());
        final preprocessing = scan.value.diagnostics.preprocessing;
        final preprocessingStages = preprocessing.stageDurations;
        final timedStages =
            preprocessingStages.denoise +
            preprocessingStages.illuminationNormalization +
            preprocessingStages.thresholding +
            preprocessingStages.statistics;
        expect(
          timedStages,
          lessThanOrEqualTo(preprocessing.processingDuration),
        );
        for (final question in scan.value.questions) {
          results[question.questionId.value] = question;
        }
      }

      expect(results.keys.toSet(), {
        'q1',
        'q2',
        'q3',
        'q4',
        'q5',
        'q6',
        'q7',
        'q8',
        'q9',
        'q10',
      });
      for (final id in ['q1', 'q2', 'q4', 'q6', 'q8', 'q9', 'q10']) {
        expect(results[id]!.state, MarkState.marked, reason: id);
      }
      expect(results['q3']!.state, MarkState.blank);
      expect(results['q5']!.state, MarkState.multiple);
      expect(results['q7']!.state, MarkState.blank);
      expect(results['q1']!.selectedOptionIds.single.value, 'q1-4');
      expect(results['q6']!.selectedOptionIds.map((id) => id.value).toSet(), {
        'q6-1',
        'q6-3',
        'q6-5',
      });
      expect(results['q10']!.numericSelection!.completeDigitString, '427');
      expect(
        results['q5']!.bubbleDecisions,
        isNotEmpty,
        reason: 'Multiple/ambiguous evidence must remain inspectable.',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
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
