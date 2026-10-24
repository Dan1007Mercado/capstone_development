import 'dart:typed_data';

import 'package:capstone_development/application/published_templates/in_memory_published_template_artifact_repository.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact_service.dart';
import 'package:capstone_development/application/real_scanner/published_scanner_resolver.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_alignment_config.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/layout/application/layout_engine.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/layout/domain/layout_regions.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/preprocessing/domain/pixel_images.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessed_page.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessing_config.dart';
import 'package:capstone_development/engines/recognition/application/mark_classification_engine.dart';
import 'package:capstone_development/engines/recognition/domain/bubble_measurement.dart';
import 'package:capstone_development/engines/recognition/domain/bubble_measurement_config.dart';
import 'package:capstone_development/engines/recognition/domain/canonical_bubble_roi.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification_config.dart';
import 'package:capstone_development/engines/scanner/application/offline_scanner_engine.dart';
import 'package:capstone_development/engines/scanner/domain/scan_result.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_stages.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/domain/template_option.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:capstone_development/engines/template/domain/template_section.dart';
import 'package:capstone_development/engines/template/domain/template_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('physical Q7 mark is classified and stored only as Q7', () {
    final fixture = _fixture();
    final result = _scan(fixture, QuestionId('q7'));

    _expectOnlyMarked(result, questionId: QuestionId('q7'), questionNumber: 7);
    expect(
      result.questions
          .singleWhere((item) => item.questionId == QuestionId('q8'))
          .state,
      MarkState.blank,
    );
  });

  test('physical Q8 mark is classified and stored only as Q8', () {
    final fixture = _fixture();
    final result = _scan(fixture, QuestionId('q8'));

    _expectOnlyMarked(result, questionId: QuestionId('q8'), questionNumber: 8);
    expect(
      result.questions
          .singleWhere((item) => item.questionId == QuestionId('q7'))
          .state,
      MarkState.blank,
    );
  });

  test('scanner rejects a classification whose number drifts from its ID', () {
    final fixture = _fixture();
    final valid = _scan(fixture, QuestionId('q7'));
    final changed = [
      for (final question in valid.questions)
        QuestionClassification(
          questionId: question.questionId,
          questionNumber: question.questionId == QuestionId('q7')
              ? 8
              : question.questionNumber,
          questionType: question.questionType,
          state: question.state,
          selectedOptionIds: question.selectedOptionIds,
          numericSelection: question.numericSelection,
          bubbleDecisions: question.bubbleDecisions,
          diagnostics: question.diagnostics,
        ),
    ];
    final pipeline = _SyntheticPipeline(
      selectedQuestionId: QuestionId('q7'),
      classificationOverride: changed,
    );

    final result = _engine(pipeline).scan(
      encodedImage: Uint8List.fromList([1]),
      template: fixture.template,
      pageLayout: fixture.page,
      config: ScannerConfig(),
    );

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'SCAN_RESULT_INVALID');
  });

  test('stored published PageLayout retains Q7 mapping when scanned', () async {
    final repository = InMemoryPublishedTemplateArtifactRepository();
    final service = PublishedTemplateArtifactService(
      repository: repository,
      pdfRenderer: (_, _) async =>
          EngineResult.success(Uint8List.fromList([37, 80, 68, 70, 45])),
    );
    final published = await service.publish(
      draft: _template(),
      layoutConfig: LayoutConfig.a4AnswerSheet(),
    );
    expect(published.isSuccess, isTrue);
    final resolved =
        await PublishedScannerResolver(artifactRepository: repository).resolve(
          templateId: published.value.templateId,
          templateVersion: published.value.templateVersion,
        );
    expect(resolved.isSuccess, isTrue);
    final page = resolved.value.layout.pages.single;
    final result =
        _engine(_SyntheticPipeline(selectedQuestionId: QuestionId('q7'))).scan(
          encodedImage: Uint8List.fromList([1]),
          template: resolved.value.template,
          pageLayout: page,
          config: ScannerConfig(),
        );

    expect(page.questionRegions[6].questionId, QuestionId('q7'));
    expect(page.questionRegions[6].questionNumber, 7);
    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    _expectOnlyMarked(
      result.value,
      questionId: QuestionId('q7'),
      questionNumber: 7,
    );
  });
}

({TemplateDefinition template, PageLayout page}) _fixture() {
  final template = _template();
  final layout = LayoutEngine()
      .build(template, LayoutConfig.a4AnswerSheet())
      .value;
  return (template: template, page: layout.pages.single);
}

TemplateDefinition _template() => TemplateDefinition(
  id: TemplateId('p14-3-scanner-mapping'),
  version: TemplateVersion(1),
  name: 'P14.3 scanner mapping',
  status: TemplateStatus.draft,
  sections: [
    TemplateSection(
      id: SectionId('responses'),
      title: 'RESPONSES',
      questions: [
        for (var number = 1; number <= 7; number++)
          _question(number, QuestionType.singleChoice),
        _question(8, QuestionType.multipleChoice),
      ],
    ),
  ],
);

TemplateQuestion _question(int number, QuestionType type) => TemplateQuestion(
  id: QuestionId('q$number'),
  type: type,
  prompt: 'Question $number',
  options: [
    TemplateOption(id: OptionId('q$number-a'), label: 'A'),
    TemplateOption(id: OptionId('q$number-b'), label: 'B'),
  ],
);

ScanResult _scan(
  ({TemplateDefinition template, PageLayout page}) fixture,
  QuestionId selectedQuestionId,
) => _engine(_SyntheticPipeline(selectedQuestionId: selectedQuestionId))
    .scan(
      encodedImage: Uint8List.fromList([1]),
      template: fixture.template,
      pageLayout: fixture.page,
      config: ScannerConfig(),
    )
    .value;

OfflineScannerEngine _engine(_SyntheticPipeline pipeline) =>
    OfflineScannerEngine(
      alignment: pipeline,
      preprocessing: pipeline,
      measurement: pipeline,
      classification: pipeline,
    );

void _expectOnlyMarked(
  ScanResult result, {
  required QuestionId questionId,
  required int questionNumber,
}) {
  final marked = result.questions
      .where((question) => question.state == MarkState.marked)
      .toList(growable: false);
  expect(marked, hasLength(1));
  expect(marked.single.questionId, questionId);
  expect(marked.single.questionNumber, questionNumber);
  expect(marked.single.selectedOptionIds, [OptionId('${questionId.value}-a')]);
  expect(result.questions.map((question) => question.questionNumber), [
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
  ]);
}

final class _SyntheticPipeline
    implements
        ScannerAlignmentStage,
        ScannerPreprocessingStage,
        ScannerMeasurementStage,
        ScannerClassificationStage {
  _SyntheticPipeline({
    required this.selectedQuestionId,
    this.classificationOverride,
  });

  final QuestionId selectedQuestionId;
  final List<QuestionClassification>? classificationOverride;

  @override
  EngineResult<PageAlignmentResult> align(
    Uint8List encodedImage,
    PageLayout page,
    ArucoAlignmentConfig config,
  ) {
    final size = ImageSize(
      width: page.canonicalPageSpec.widthPixels,
      height: page.canonicalPageSpec.heightPixels,
    );
    return EngineResult.success(
      PageAlignmentResult(
        canonicalPage: CanonicalPageImage(size: size, pngBytes: const [1]),
        homography: HomographyMatrix(const [1, 0, 0, 0, 1, 0, 0, 0, 1]),
        observations: const [],
        correspondences: const [],
        diagnostics: PageAlignmentDiagnostics(
          expectedMarkerIds: const [],
          detectedMarkerIds: const [],
          sourceMarkerSideLengths: const [],
          sourceRegistrationPoints: const [],
          destinationRegistrationPoints: const [],
          registrationQuality: const RegistrationQuality(
            quadrilateralAreaRatio: 1,
            minimumMarkerSidePixels: 10,
            maximumPerspectiveRatio: 1,
          ),
          reprojectionErrors: const [],
          meanReprojectionError: 0,
          maxReprojectionError: 0,
          processingDuration: Duration.zero,
        ),
      ),
    );
  }

  @override
  EngineResult<PreprocessedPage> process(
    CanonicalPageImage page,
    PreprocessingConfig config,
  ) {
    final pixels = Uint8List(page.size.area);
    final image = GrayImage(size: page.size, pixels: pixels);
    return EngineResult.success(
      PreprocessedPage(
        size: page.size,
        grayscale: image,
        normalizedGrayscale: image,
        binary: BinaryImage(size: page.size, pixels: pixels),
        diagnostics: const PreprocessingDiagnostics(
          sourceStatistics: _statistics,
          normalizedStatistics: _statistics,
          binaryForegroundRatio: 0,
          processingDuration: Duration.zero,
        ),
        config: config,
      ),
    );
  }

  @override
  EngineResult<BubbleMeasurementSet> measure(
    PageLayout layout,
    PreprocessedPage page,
    BubbleMeasurementConfig config,
  ) => EngineResult.success(
    BubbleMeasurementSet(
      pageId: layout.pageId,
      measurements: [
        for (var index = 0; index < layout.bubbleRegions.length; index++)
          _measurement(
            layout.bubbleRegions[index],
            index,
            layout.bubbleRegions[index].questionId == selectedQuestionId &&
                layout.bubbleRegions[index].optionId?.value.endsWith('-a') ==
                    true,
          ),
      ],
    ),
  );

  @override
  EngineResult<PageClassificationResult> classify(
    TemplateDefinition template,
    PageLayout page,
    BubbleMeasurementSet measurements,
    MarkClassificationConfig config,
  ) {
    final override = classificationOverride;
    if (override != null) {
      return EngineResult.success(
        PageClassificationResult(pageId: page.pageId, questions: override),
      );
    }
    return const MarkClassificationEngine().classify(
      template,
      page,
      measurements,
      config,
    );
  }
}

BubbleMeasurement _measurement(BubbleRegion bubble, int index, bool marked) {
  final fill = marked ? 0.8 : 0.02;
  final darkness = marked ? 0.45 : 0.02;
  final contrast = marked ? 90.0 : 3.0;
  return BubbleMeasurement(
    pageId: bubble.pageId,
    questionId: bubble.questionId,
    optionId: bubble.optionId,
    numericColumnIndex: bubble.numericColumnIndex,
    numericDigitValue: bubble.numericDigitValue,
    roi: CanonicalBubbleRoi(
      center: ImagePoint(index + 10, 10),
      printedRadius: 5,
      interiorRadius: 3.4,
      baselineInnerRadius: 6.25,
      baselineOuterRadius: 10,
    ),
    sampledInteriorPixelCount: 100,
    sampledBaselinePixelCount: 120,
    interiorMeanIntensity: 240 - contrast,
    interiorMedianIntensity: 240 - contrast,
    localBaselineIntensity: 240,
    darknessContrast: contrast,
    normalizedDarkness: darkness,
    foregroundPixelCount: (fill * 100).round(),
    fillRatio: fill,
    distributionScore: marked ? 1 : 0,
    quality: const BubbleMeasurementQuality(
      interiorValidSampleRatio: 1,
      baselineValidSampleRatio: 1,
      clipping: BubbleRoiClipping.none,
      baselineForegroundRatio: 0,
      localBaselineReliable: true,
      neighborMaskedPixelCount: 0,
    ),
  );
}

const _statistics = ImageStatistics(
  meanIntensity: 200,
  intensityStandardDeviation: 20,
  minimumIntensity: 0,
  maximumIntensity: 255,
  darkPixelRatio: 0,
  brightPixelRatio: 0,
);
