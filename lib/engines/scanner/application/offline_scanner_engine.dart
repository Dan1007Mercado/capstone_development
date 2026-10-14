import 'dart:typed_data';

import '../../../core/errors/engine_error.dart';
import '../../../core/ids/identifiers.dart';
import '../../../core/result/engine_result.dart';
import '../../layout/domain/page_layout.dart';
import '../../recognition/domain/mark_classification.dart';
import '../../template/domain/template_definition.dart';
import '../../template/domain/template_question.dart';
import '../domain/scan_result.dart';
import '../domain/scanner_config.dart';
import '../domain/scanner_stages.dart';

final class OfflineScannerEngine {
  const OfflineScannerEngine({
    required this.alignment,
    required this.preprocessing,
    required this.measurement,
    required this.classification,
  });

  final ScannerAlignmentStage alignment;
  final ScannerPreprocessingStage preprocessing;
  final ScannerMeasurementStage measurement;
  final ScannerClassificationStage classification;

  EngineResult<ScanResult> scan({
    required Uint8List encodedImage,
    required TemplateDefinition template,
    required PageLayout pageLayout,
    required ScannerConfig config,
  }) {
    final validation = _validateTemplateLayout(template, pageLayout);
    if (validation != null) return EngineResult.failure(validation);

    final totalStopwatch = Stopwatch()..start();
    final alignmentStopwatch = Stopwatch()..start();
    final alignmentResult = alignment.align(
      Uint8List.fromList(encodedImage),
      pageLayout,
      config.alignment,
    );
    alignmentStopwatch.stop();
    if (alignmentResult.isFailure) {
      return _stageFailure(
        ScanStage.alignment,
        alignmentResult.error,
        pageLayout,
      );
    }

    final preprocessingStopwatch = Stopwatch()..start();
    final preprocessingResult = preprocessing.process(
      alignmentResult.value.canonicalPage,
      config.preprocessing,
    );
    preprocessingStopwatch.stop();
    if (preprocessingResult.isFailure) {
      return _stageFailure(
        ScanStage.preprocessing,
        preprocessingResult.error,
        pageLayout,
      );
    }

    final measurementStopwatch = Stopwatch()..start();
    final measurementResult = measurement.measure(
      pageLayout,
      preprocessingResult.value,
      config.measurement,
    );
    measurementStopwatch.stop();
    if (measurementResult.isFailure) {
      return _stageFailure(
        ScanStage.measurement,
        measurementResult.error,
        pageLayout,
      );
    }

    final classificationStopwatch = Stopwatch()..start();
    final classificationResult = classification.classify(
      template,
      pageLayout,
      measurementResult.value,
      config.classification,
    );
    classificationStopwatch.stop();
    if (classificationResult.isFailure) {
      return _stageFailure(
        ScanStage.classification,
        classificationResult.error,
        pageLayout,
      );
    }

    final classificationContractError = _validateClassificationResult(
      classificationResult.value,
      pageLayout,
    );
    if (classificationContractError != null) {
      return EngineResult.failure(classificationContractError);
    }

    final questionsById = _questionsById(template);
    final questions = classificationResult.value.questions;
    final reviewReasons = <ScanReviewReason>{};
    final reviewQuestionIds = <QuestionId>[];
    final reviewQuestionIdSet = <QuestionId>{};
    var marked = 0;
    var blank = 0;
    var multiple = 0;
    var ambiguous = 0;
    var invalid = 0;
    var requiredBlank = 0;

    void addReview(QuestionId id, ScanReviewReason reason) {
      reviewReasons.add(reason);
      if (reviewQuestionIdSet.add(id)) reviewQuestionIds.add(id);
    }

    for (final question in questions) {
      switch (question.state) {
        case MarkState.marked:
          marked++;
          break;
        case MarkState.blank:
          blank++;
          if (questionsById[question.questionId]!.required &&
              config.requiredQuestionPolicy ==
                  RequiredQuestionPolicy.needsReview) {
            requiredBlank++;
            addReview(
              question.questionId,
              ScanReviewReason.requiredQuestionBlank,
            );
          }
          break;
        case MarkState.multiple:
          multiple++;
          addReview(question.questionId, ScanReviewReason.multipleSelection);
          break;
        case MarkState.ambiguous:
          ambiguous++;
          addReview(question.questionId, ScanReviewReason.ambiguousQuestion);
          break;
        case MarkState.invalid:
          invalid++;
          addReview(question.questionId, ScanReviewReason.invalidQuestion);
          if (question.diagnostics.reason ==
              ClassificationReason.unusableQuality) {
            reviewReasons.add(ScanReviewReason.lowQualityMeasurement);
          }
          break;
      }
    }

    final pageState = invalid > 0
        ? ScanPageState.invalid
        : reviewQuestionIds.isNotEmpty
        ? ScanPageState.needsReview
        : ScanPageState.accepted;
    totalStopwatch.stop();
    final summary = ScanSummary(
      totalQuestions: questions.length,
      marked: marked,
      blank: blank,
      multiple: multiple,
      ambiguous: ambiguous,
      invalid: invalid,
      requiredBlank: requiredBlank,
      measuredBubbles: measurementResult.value.measurements.length,
    );
    return EngineResult.success(
      ScanResult(
        templateId: template.id,
        templateVersion: template.version,
        pageId: pageLayout.pageId,
        questions: questions,
        pageState: pageState,
        reviewReasons: reviewReasons,
        reviewQuestionIds: reviewQuestionIds,
        diagnostics: ScanDiagnostics(
          totalProcessingDuration: totalStopwatch.elapsed,
          stageDurations: ScanStageDurations(
            alignment: alignmentStopwatch.elapsed,
            preprocessing: preprocessingStopwatch.elapsed,
            measurement: measurementStopwatch.elapsed,
            classification: classificationStopwatch.elapsed,
          ),
          alignment: alignmentResult.value.diagnostics,
          preprocessing: preprocessingResult.value.diagnostics,
          summary: summary,
        ),
      ),
    );
  }

  EngineError? _validateTemplateLayout(
    TemplateDefinition template,
    PageLayout page,
  ) {
    if (page.templateId != template.id ||
        page.templateVersion != template.version) {
      return _mismatch('PageLayout does not belong to the supplied template.');
    }
    final questions = _questionsById(template);
    final seen = <QuestionId>{};
    for (final region in page.questionRegions) {
      final question = questions[region.questionId];
      if (!seen.add(region.questionId) ||
          question == null ||
          question.type != region.questionType ||
          region.bubbleRegions.any(
            (bubble) =>
                bubble.pageId != page.pageId ||
                bubble.questionId != region.questionId,
          )) {
        return _mismatch(
          'PageLayout question regions do not belong to the supplied template.',
        );
      }
    }
    if (page.bubbleRegions.any(
      (bubble) =>
          bubble.pageId != page.pageId || !seen.contains(bubble.questionId),
    )) {
      return _mismatch(
        'PageLayout bubbles do not belong to its ordered question regions.',
      );
    }
    return null;
  }

  Map<QuestionId, TemplateQuestion> _questionsById(
    TemplateDefinition template,
  ) => {
    for (final section in template.sections)
      for (final question in section.questions) question.id: question,
  };

  EngineError? _validateClassificationResult(
    PageClassificationResult result,
    PageLayout page,
  ) {
    final expectedIds = page.questionRegions
        .map((region) => region.questionId)
        .toList(growable: false);
    final actualIds = result.questions
        .map((question) => question.questionId)
        .toList(growable: false);
    if (result.pageId != page.pageId ||
        actualIds.length != expectedIds.length ||
        [
          for (var index = 0; index < expectedIds.length; index++)
            actualIds[index] == expectedIds[index],
        ].contains(false)) {
      return EngineError(
        code: 'SCAN_RESULT_INVALID',
        message:
            'Classification output does not match the PageLayout page and order.',
        details: {'pageId': page.pageId.value},
      );
    }
    return null;
  }

  EngineError _mismatch(String message) =>
      EngineError(code: 'SCAN_TEMPLATE_LAYOUT_MISMATCH', message: message);

  EngineResult<ScanResult> _stageFailure(
    ScanStage stage,
    EngineError cause,
    PageLayout page,
  ) => EngineResult.failure(
    EngineError(
      code: switch (stage) {
        ScanStage.alignment => 'SCAN_ALIGNMENT_FAILED',
        ScanStage.preprocessing => 'SCAN_PREPROCESSING_FAILED',
        ScanStage.measurement => 'SCAN_MEASUREMENT_FAILED',
        ScanStage.classification => 'SCAN_CLASSIFICATION_FAILED',
        ScanStage.complete => 'SCAN_RESULT_INVALID',
      },
      message: 'Offline scanning failed during ${stage.name}.',
      details: {
        'failedStage': stage.name,
        'pageId': page.pageId.value,
        'causeCode': cause.code,
        'causeMessage': cause.message,
        'causeDetails': cause.details,
      },
    ),
  );
}
