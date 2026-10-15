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
import 'package:capstone_development/engines/scanner/domain/scanner_identity.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_stages.dart';
import 'package:capstone_development/engines/pdf/domain/template_page_identity_codec.dart';
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

  test('identity stage reuses aligned canonical page before preprocessing', () {
    final pipeline = _FakePipeline(
      page,
      _classifications(questionIds, const [
        MarkState.marked,
        MarkState.marked,
        MarkState.blank,
      ]),
    );
    final identity = _FakeIdentityStage(
      TemplatePageIdentity(
        templateId: template.id,
        templateVersion: template.version,
        pageId: page.pageId,
      ),
    );
    final scanner = OfflineScannerEngine(
      alignment: pipeline,
      identity: identity,
      preprocessing: pipeline,
      measurement: pipeline,
      classification: pipeline,
    );

    final result = scanner.scan(
      encodedImage: Uint8List.fromList([1, 2, 3]),
      template: template,
      pageLayout: page,
      config: ScannerConfig(),
    );

    expect(result.isSuccess, isTrue);
    expect(identity.canonicalPage, same(pipeline.alignedCanonicalPage));
    expect(pipeline.preprocessedCanonicalPage, same(identity.canonicalPage));
    expect(result.value.diagnostics.identity?.payloadDecoded, isTrue);
  });

  test('identity mismatch remains an exact typed scanner failure', () {
    final pipeline = _FakePipeline(
      page,
      _classifications(questionIds, const [
        MarkState.marked,
        MarkState.marked,
        MarkState.blank,
      ]),
    );
    final scanner = OfflineScannerEngine(
      alignment: pipeline,
      identity: _FakeIdentityStage(
        TemplatePageIdentity(
          templateId: template.id,
          templateVersion: TemplateVersion(template.version.value + 1),
          pageId: page.pageId,
        ),
      ),
      preprocessing: pipeline,
      measurement: pipeline,
      classification: pipeline,
    );

    final result = scanner.scan(
      encodedImage: Uint8List.fromList([1]),
      template: template,
      pageLayout: page,
      config: ScannerConfig(),
    );

    expect(result.error.code, 'SCAN_TEMPLATE_VERSION_MISMATCH');
    expect(result.error.details['identityPayloadDecoded'], isTrue);
    expect(pipeline.calls, [ScanStage.alignment]);
  });

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
  });

  final PageLayout page;
  final List<QuestionClassification> classifications;
  final ScanStage? failAt;
  final bool mutateInput;
  final List<ScanStage> calls = [];
  CanonicalPageImage? alignedCanonicalPage;
  CanonicalPageImage? preprocessedCanonicalPage;

  EngineResult<T>? _failure<T>(ScanStage stage) {
    calls.add(stage);
    if (failAt != stage) return null;
    return EngineResult.failure(
      EngineError(
        code: 'CHILD_FAILED',
        message: 'stage failed',
        details: const {'value': 7},
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
    alignedCanonicalPage = CanonicalPageImage(size: size, pngBytes: const [1]);
    return EngineResult.success(
      PageAlignmentResult(
        canonicalPage: alignedCanonicalPage!,
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
    preprocessedCanonicalPage = canonicalPage;
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
    return EngineResult.success(
      BubbleMeasurementSet(
        pageId: layout.pageId,
        measurements: [
          for (final bubble in layout.bubbleRegions)
            _emptyMeasurement(bubble.questionId, bubble.optionId),
        ],
      ),
    );
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
    return EngineResult.success(
      PageClassificationResult(pageId: page.pageId, questions: classifications),
    );
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

final class _FakeIdentityStage implements ScannerIdentityStage {
  _FakeIdentityStage(this.identity);

  final TemplatePageIdentity identity;
  CanonicalPageImage? canonicalPage;

  @override
  EngineResult<ScannerIdentityResult> identify(
    CanonicalPageImage page,
    PageLayout layout,
  ) {
    canonicalPage = page;
    return EngineResult.success(
      ScannerIdentityResult(
        identity: identity,
        diagnostics: ScannerIdentityDiagnostics(
          source: ScannerIdentitySource.canonicalCrop,
          cropSize: ImageSize(width: 10, height: 10),
          upscaleFactor: 1,
          payloadDecoded: true,
          processingDuration: Duration.zero,
          attemptCount: 1,
        ),
      ),
    );
  }

  @override
  void dispose() {}
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
