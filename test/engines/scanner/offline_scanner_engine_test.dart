import 'dart:typed_data';

import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/core/geometry/page_spec.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_alignment_config.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/preprocessing/domain/pixel_images.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessed_page.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessing_config.dart';
import 'package:capstone_development/engines/recognition/domain/bubble_measurement.dart';
import 'package:capstone_development/engines/recognition/domain/bubble_measurement_config.dart';
import 'package:capstone_development/engines/recognition/domain/canonical_bubble_roi.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification_config.dart';
import 'package:capstone_development/engines/scanner/application/offline_scanner_engine.dart';
import 'package:capstone_development/engines/scanner/domain/scan_result.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_diagnostic_snapshot.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_stages.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/domain/template_option.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout/layout_test_fixtures.dart';

void main() {
  late TemplateDefinition template;
  late PageLayout page;
  late List<QuestionId> questionIds;

  setUp(() {
    template = templateWithQuestions([
      _question('first'),
      _question('required', required: true),
      _question('last'),
    ]);
    page = buildLayout(
      template,
      config: testConfig(
        canonicalPageSpec: CanonicalPageSpec(
          widthPixels: 210,
          heightPixels: 297,
        ),
      ),
    ).pages.single;
    questionIds = page.questionRegions
        .map((region) => region.questionId)
        .toList(growable: false);
  });

  test('executes all stages in order and preserves identity and order', () {
    final pipeline = _FakePipeline(
      page,
      _classifications(questionIds, const [
        MarkState.marked,
        MarkState.marked,
        MarkState.blank,
      ]),
    );

    final result = _engine(pipeline).scan(
      encodedImage: Uint8List.fromList([1, 2, 3]),
      template: template,
      pageLayout: page,
      config: ScannerConfig(),
    );

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(pipeline.calls, [
      ScanStage.alignment,
      ScanStage.preprocessing,
      ScanStage.measurement,
      ScanStage.classification,
    ]);
    expect(result.value.templateId, template.id);
    expect(result.value.templateVersion, template.version);
    expect(result.value.pageId, page.pageId);
    expect(
      result.value.questions.map((question) => question.questionId),
      questionIds,
    );
    expect(result.value.pageState, ScanPageState.accepted);
  });

  test(
    'diagnostic hook observes exact pipeline values without changing result',
    () {
      final normalPipeline = _FakePipeline(
        page,
        _classifications(questionIds, const [
          MarkState.marked,
          MarkState.marked,
          MarkState.blank,
        ]),
      );
      final diagnosticPipeline = _FakePipeline(
        page,
        _classifications(questionIds, const [
          MarkState.marked,
          MarkState.marked,
          MarkState.blank,
        ]),
      );
      final config = ScannerConfig(
        preprocessing: const PreprocessingConfig(denoiseKernelSize: 5),
        measurement: const BubbleMeasurementConfig(interiorRadiusRatio: 0.67),
        classification: const MarkClassificationConfig(
          minimumCombinedMarkScore: 0.36,
        ),
      );
      final normal = _engine(normalPipeline).scan(
        encodedImage: Uint8List.fromList([1, 2, 3]),
        template: template,
        pageLayout: page,
        config: config,
      );
      ScannerDiagnosticSnapshot? snapshot;
      final diagnostic = _engine(diagnosticPipeline).scan(
        encodedImage: Uint8List.fromList([1, 2, 3]),
        template: template,
        pageLayout: page,
        config: config,
        diagnosticSink: (value) => snapshot = value,
      );

      expect(normal.isSuccess, isTrue);
      expect(diagnostic.isSuccess, isTrue);
      expect(
        _semanticProjection(diagnostic.value),
        _semanticProjection(normal.value),
      );
      expect(snapshot, isNotNull);
      expect(snapshot!.result, same(diagnostic.value));
      expect(snapshot!.measurements, same(diagnosticPipeline.measurementSet));
      expect(
        diagnosticPipeline.classificationMeasurements,
        same(snapshot!.measurements),
      );
      expect(
        snapshot!.classification,
        same(diagnosticPipeline.classificationResult),
      );
      expect(snapshot!.preprocessingConfig, same(config.preprocessing));
      expect(snapshot!.measurementConfig, same(config.measurement));
      expect(snapshot!.classificationConfig, same(config.classification));
      expect(snapshot!.canonicalImageFormat, ScannerDiagnosticImageFormat.png);
      expect(snapshot!.canonicalImageBytes, [1]);
    },
  );

  for (final failureStage in [
    ScanStage.alignment,
    ScanStage.preprocessing,
    ScanStage.measurement,
    ScanStage.classification,
  ]) {
    test('$failureStage failure preserves cause and stops later stages', () {
      final pipeline = _FakePipeline(
        page,
        _classifications(questionIds, const [
          MarkState.marked,
          MarkState.marked,
          MarkState.marked,
        ]),
        failAt: failureStage,
      );

      final result = _engine(pipeline).scan(
        encodedImage: Uint8List.fromList([1]),
        template: template,
        pageLayout: page,
        config: ScannerConfig(),
      );

      expect(result.isFailure, isTrue);
      expect(result.error.details['failedStage'], failureStage.name);
      expect(result.error.details['causeCode'], 'CHILD_FAILED');
      expect(result.error.details['causeMessage'], 'stage failed');
      expect(result.error.details['causeDetails'], {'value': 7});
      expect(
        pipeline.calls,
        ScanStage.values.take(failureStage.index + 1).toList(),
      );
    });
  }

  test('alignment failure diagnostics survive the scanner stage wrapper', () {
    const failurePayload = {
      'alignmentFailureDiagnostics': {
        'selectionReason': 'NO_TRUSTWORTHY_HOMOGRAPHY',
        'fourPoint': {'validationStatus': 'rejected'},
        'multiPoint': {'validationStatus': 'rejected'},
      },
    };
    final pipeline = _FakePipeline(
      page,
      _classifications(questionIds, const [
        MarkState.marked,
        MarkState.marked,
        MarkState.marked,
      ]),
      failAt: ScanStage.alignment,
      failureDetails: failurePayload,
    );

    final result = _engine(pipeline).scan(
      encodedImage: Uint8List.fromList([1]),
      template: template,
      pageLayout: page,
      config: ScannerConfig(),
    );

    expect(result.isFailure, isTrue);
    expect(result.error.details['causeDetails'], failurePayload);
  });

  test('template/layout mismatch fails before image processing', () {
    final pipeline = _FakePipeline(
      page,
      _classifications(questionIds, const [
        MarkState.blank,
        MarkState.blank,
        MarkState.blank,
      ]),
    );
    final otherTemplate = templateWithQuestions([
      _question('first'),
    ], templateId: 'other');

    final result = _engine(pipeline).scan(
      encodedImage: Uint8List.fromList([1]),
      template: otherTemplate,
      pageLayout: page,
      config: ScannerConfig(),
    );

    expect(result.error.code, 'SCAN_TEMPLATE_LAYOUT_MISMATCH');
    expect(pipeline.calls, isEmpty);
  });

  test('unknown layout question fails before image processing', () {
    final pipeline = _FakePipeline(
      page,
      _classifications(questionIds, const [
        MarkState.blank,
        MarkState.blank,
        MarkState.blank,
      ]),
    );
    final sameIdentityDifferentQuestions = templateWithQuestions([
      _question('different'),
    ]);

    final result = _engine(pipeline).scan(
      encodedImage: Uint8List.fromList([1]),
      template: sameIdentityDifferentQuestions,
      pageLayout: page,
      config: ScannerConfig(),
    );

    expect(result.error.code, 'SCAN_TEMPLATE_LAYOUT_MISMATCH');
    expect(pipeline.calls, isEmpty);
  });

  test('optional blank remains accepted', () {
    final result = _scanWithStates(template, page, questionIds, const [
      MarkState.marked,
      MarkState.marked,
      MarkState.blank,
    ]);

    expect(result.pageState, ScanPageState.accepted);
    expect(result.summary.blank, 1);
    expect(result.reviewQuestionIds, isEmpty);
  });

  test('required blank needs review without changing its P8 state', () {
    final result = _scanWithStates(template, page, questionIds, const [
      MarkState.marked,
      MarkState.blank,
      MarkState.marked,
    ]);

    expect(result.pageState, ScanPageState.needsReview);
    expect(result.questions[1].state, MarkState.blank);
    expect(result.reviewReasons, [ScanReviewReason.requiredQuestionBlank]);
    expect(result.reviewQuestionIds, [QuestionId('required')]);
    expect(result.summary.requiredBlank, 1);
  });

  test('required blank policy can explicitly ignore submission review', () {
    final pipeline = _FakePipeline(
      page,
      _classifications(questionIds, const [
        MarkState.marked,
        MarkState.blank,
        MarkState.marked,
      ]),
    );
    final result = _engine(pipeline).scan(
      encodedImage: Uint8List.fromList([1]),
      template: template,
      pageLayout: page,
      config: ScannerConfig(
        requiredQuestionPolicy: RequiredQuestionPolicy.ignore,
      ),
    );

    expect(result.value.pageState, ScanPageState.accepted);
    expect(result.value.summary.requiredBlank, 0);
  });

  test('ambiguous and multiple questions need review with correct IDs', () {
    final result = _scanWithStates(template, page, questionIds, const [
      MarkState.ambiguous,
      MarkState.marked,
      MarkState.multiple,
    ]);

    expect(result.pageState, ScanPageState.needsReview);
    expect(result.reviewReasons, [
      ScanReviewReason.ambiguousQuestion,
      ScanReviewReason.multipleSelection,
    ]);
    expect(result.reviewQuestionIds, [QuestionId('first'), QuestionId('last')]);
  });

  test('invalid state has priority and reports low-quality evidence', () {
    final classifications = _classifications(questionIds, const [
      MarkState.multiple,
      MarkState.blank,
      MarkState.invalid,
    ]);
    final pipeline = _FakePipeline(page, classifications);
    final result = _engine(pipeline)
        .scan(
          encodedImage: Uint8List.fromList([1]),
          template: template,
          pageLayout: page,
          config: ScannerConfig(),
        )
        .value;

    expect(result.pageState, ScanPageState.invalid);
    expect(result.reviewReasons, contains(ScanReviewReason.invalidQuestion));
    expect(
      result.reviewReasons,
      contains(ScanReviewReason.lowQualityMeasurement),
    );
    expect(result.reviewQuestionIds, questionIds);
  });

  test('summary counts all classification states and measured bubbles', () {
    final result = _scanWithStates(template, page, questionIds, const [
      MarkState.marked,
      MarkState.ambiguous,
      MarkState.blank,
    ]);

    expect(result.summary.totalQuestions, 3);
    expect(result.summary.marked, 1);
    expect(result.summary.blank, 1);
    expect(result.summary.multiple, 0);
    expect(result.summary.ambiguous, 1);
    expect(result.summary.invalid, 0);
    expect(result.summary.requiredBlank, 0);
    expect(result.summary.measuredBubbles, page.bubbleRegions.length);
    expect(
      result.diagnostics.totalProcessingDuration,
      greaterThanOrEqualTo(Duration.zero),
    );
    final stages = result.diagnostics.stageDurations;
    final stageTotal =
        stages.alignment +
        stages.preprocessing +
        stages.measurement +
        stages.classification +
        stages.validation;
    expect(
      result.diagnostics.totalProcessingDuration,
      greaterThanOrEqualTo(stageTotal),
    );
  });

  test('rejects classifier output that changes PageLayout order', () {
    final reversed = _classifications(questionIds.reversed.toList(), const [
      MarkState.marked,
      MarkState.marked,
      MarkState.marked,
    ]);
    final pipeline = _FakePipeline(page, reversed);

    final result = _engine(pipeline).scan(
      encodedImage: Uint8List.fromList([1]),
      template: template,
      pageLayout: page,
      config: ScannerConfig(),
    );

    expect(result.error.code, 'SCAN_RESULT_INVALID');
  });

  test('result collections are unmodifiable', () {
    final result = _scanWithStates(template, page, questionIds, const [
      MarkState.marked,
      MarkState.marked,
      MarkState.blank,
    ]);

    expect(() => result.questions.clear(), throwsUnsupportedError);
    expect(() => result.reviewReasons.clear(), throwsUnsupportedError);
    expect(() => result.reviewQuestionIds.clear(), throwsUnsupportedError);
  });

  test('same inputs produce the same semantic result', () {
    ScanResult run() => _scanWithStates(template, page, questionIds, const [
      MarkState.marked,
      MarkState.blank,
      MarkState.ambiguous,
    ]);

    final first = run();
    final second = run();
    expect(_semanticProjection(first), _semanticProjection(second));
  });

  test('source image bytes are not mutated even by an unsafe stage', () {
    final source = Uint8List.fromList([4, 5, 6]);
    final pipeline = _FakePipeline(
      page,
      _classifications(questionIds, const [
        MarkState.marked,
        MarkState.marked,
        MarkState.marked,
      ]),
      mutateInput: true,
    );

    _engine(pipeline).scan(
      encodedImage: source,
      template: template,
      pageLayout: page,
      config: ScannerConfig(),
    );

    expect(source, [4, 5, 6]);
  });
}

TemplateQuestion _question(String id, {bool required = false}) =>
    TemplateQuestion(
      id: QuestionId(id),
      type: QuestionType.singleChoice,
      prompt: id,
      required: required,
      options: [
        TemplateOption(id: OptionId('$id-a'), label: 'A'),
        TemplateOption(id: OptionId('$id-b'), label: 'B'),
      ],
    );

OfflineScannerEngine _engine(_FakePipeline pipeline) => OfflineScannerEngine(
  alignment: pipeline,
  preprocessing: pipeline,
  measurement: pipeline,
  classification: pipeline,
);

ScanResult _scanWithStates(
  TemplateDefinition template,
  PageLayout page,
  List<QuestionId> questionIds,
  List<MarkState> states,
) {
  final pipeline = _FakePipeline(page, _classifications(questionIds, states));
  return _engine(pipeline)
      .scan(
        encodedImage: Uint8List.fromList([1, 2]),
        template: template,
        pageLayout: page,
        config: ScannerConfig(),
      )
      .value;
}

List<QuestionClassification> _classifications(
  List<QuestionId> ids,
  List<MarkState> states,
) => [
  for (var index = 0; index < ids.length; index++)
    QuestionClassification(
      questionId: ids[index],
      questionNumber: index + 1,
      questionType: QuestionType.singleChoice,
      state: states[index],
      selectedOptionIds: const [],
      numericSelection: null,
      bubbleDecisions: const [],
      diagnostics: QuestionClassificationDiagnostics(
        topScore: 0,
        secondScore: 0,
        scoreGap: 0,
        reason: states[index] == MarkState.invalid
            ? ClassificationReason.unusableQuality
            : states[index] == MarkState.blank
            ? ClassificationReason.clearBlank
            : ClassificationReason.uncertainEvidence,
      ),
    ),
];

List<Object?> _semanticProjection(ScanResult result) => [
  result.templateId,
  result.templateVersion,
  result.pageId,
  result.pageState,
  result.questions.map((question) => question.questionId).toList(),
  result.questions.map((question) => question.state).toList(),
  result.reviewReasons,
  result.reviewQuestionIds,
  result.summary.totalQuestions,
  result.summary.marked,
  result.summary.blank,
  result.summary.multiple,
  result.summary.ambiguous,
  result.summary.invalid,
  result.summary.requiredBlank,
];

final class _FakePipeline
    implements
        ScannerAlignmentStage,
        ScannerPreprocessingStage,
        ScannerMeasurementStage,
        ScannerClassificationStage {
  _FakePipeline(
    this.page,
    this.classifications, {
    this.failAt,
    this.mutateInput = false,
    this.failureDetails = const {'value': 7},
  });

  final PageLayout page;
  final List<QuestionClassification> classifications;
  final ScanStage? failAt;
  final bool mutateInput;
  final Map<String, Object?> failureDetails;
  final List<ScanStage> calls = [];
  BubbleMeasurementSet? measurementSet;
  BubbleMeasurementSet? classificationMeasurements;
  PageClassificationResult? classificationResult;

  EngineResult<T>? _failure<T>(ScanStage stage) {
    calls.add(stage);
    if (failAt != stage) return null;
    return EngineResult.failure(
      EngineError(
        code: 'CHILD_FAILED',
        message: 'stage failed',
        details: failureDetails,
      ),
    );
  }

  @override
  EngineResult<PageAlignmentResult> align(
    Uint8List encodedImage,
    PageLayout page,
    ArucoAlignmentConfig config,
  ) {
    final failure = _failure<PageAlignmentResult>(ScanStage.alignment);
    if (failure != null) return failure;
    if (mutateInput) encodedImage[0] = 99;
    final size = _size(page);
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
    CanonicalPageImage canonicalPage,
    PreprocessingConfig config,
  ) {
    final failure = _failure<PreprocessedPage>(ScanStage.preprocessing);
    if (failure != null) return failure;
    final pixels = Uint8List(canonicalPage.size.area);
    return EngineResult.success(
      PreprocessedPage(
        size: canonicalPage.size,
        grayscale: GrayImage(size: canonicalPage.size, pixels: pixels),
        normalizedGrayscale: GrayImage(
          size: canonicalPage.size,
          pixels: pixels,
        ),
        binary: BinaryImage(size: canonicalPage.size, pixels: pixels),
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
  ) {
    final failure = _failure<BubbleMeasurementSet>(ScanStage.measurement);
    if (failure != null) return failure;
    measurementSet = BubbleMeasurementSet(
      pageId: layout.pageId,
      measurements: [
        for (final bubble in layout.bubbleRegions)
          _emptyMeasurement(bubble.questionId, bubble.optionId),
      ],
    );
    return EngineResult.success(measurementSet!);
  }

  @override
  EngineResult<PageClassificationResult> classify(
    TemplateDefinition template,
    PageLayout page,
    BubbleMeasurementSet measurements,
    MarkClassificationConfig config,
  ) {
    final failure = _failure<PageClassificationResult>(
      ScanStage.classification,
    );
    if (failure != null) return failure;
    classificationMeasurements = measurements;
    classificationResult = PageClassificationResult(
      pageId: page.pageId,
      questions: classifications,
    );
    return EngineResult.success(classificationResult!);
  }

  BubbleMeasurement _emptyMeasurement(
    QuestionId questionId,
    OptionId? optionId,
  ) => BubbleMeasurement(
    pageId: page.pageId,
    questionId: questionId,
    optionId: optionId,
    numericColumnIndex: null,
    numericDigitValue: null,
    roi: CanonicalBubbleRoi(
      center: ImagePoint(1, 1),
      printedRadius: 1,
      interiorRadius: 0.5,
      baselineInnerRadius: 1.25,
      baselineOuterRadius: 2,
    ),
    sampledInteriorPixelCount: 1,
    sampledBaselinePixelCount: 1,
    interiorMeanIntensity: 255,
    interiorMedianIntensity: 255,
    localBaselineIntensity: 255,
    darknessContrast: 0,
    normalizedDarkness: 0,
    foregroundPixelCount: 0,
    fillRatio: 0,
    distributionScore: 0,
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

ImageSize _size(PageLayout page) => ImageSize(
  width: page.canonicalPageSpec.widthPixels,
  height: page.canonicalPageSpec.heightPixels,
);

const _statistics = ImageStatistics(
  meanIntensity: 200,
  intensityStandardDeviation: 20,
  minimumIntensity: 0,
  maximumIntensity: 255,
  darkPixelRatio: 0,
  brightPixelRatio: 0,
);
