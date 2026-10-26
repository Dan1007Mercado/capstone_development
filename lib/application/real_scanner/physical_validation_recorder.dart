import 'dart:collection';

import '../../core/ids/identifiers.dart';
import '../../engines/recognition/domain/mark_classification.dart';
import '../../engines/scanner/domain/scan_result.dart';
import '../../engines/template/domain/template_definition.dart';

/// Known-answer input for one question in a local physical validation run.
final class PhysicalValidationExpectedAnswer {
  PhysicalValidationExpectedAnswer({
    required this.questionId,
    required this.state,
    Iterable<OptionId> optionIds = const [],
    this.numericAnswer,
  }) : optionIds = UnmodifiableListView(List.of(optionIds));

  final QuestionId questionId;
  final MarkState state;
  final List<OptionId> optionIds;
  final String? numericAnswer;

  String get answerLabel {
    if (numericAnswer != null) return numericAnswer!;
    if (optionIds.isNotEmpty) return optionIds.map((id) => id.value).join('+');
    return '—';
  }
}

final class PhysicalValidationPlan {
  PhysicalValidationPlan({
    required this.templateId,
    required this.templateVersion,
    required Iterable<PhysicalValidationExpectedAnswer> answers,
  }) : answersByQuestion = UnmodifiableMapView({
         for (final answer in answers) answer.questionId: answer,
       });

  final TemplateId templateId;
  final TemplateVersion templateVersion;
  final Map<QuestionId, PhysicalValidationExpectedAnswer> answersByQuestion;

  factory PhysicalValidationPlan.fromJson(Map<String, Object?> value) =>
      PhysicalValidationPlan(
        templateId: TemplateId(value['templateId'] as String),
        templateVersion: TemplateVersion(
          (value['templateVersion'] as num).toInt(),
        ),
        answers: [
          for (final raw in value['answers'] as List)
            PhysicalValidationExpectedAnswer(
              questionId: QuestionId((raw as Map)['questionId'] as String),
              state: MarkState.values.byName(raw['state'] as String),
              optionIds: [
                for (final id in (raw['optionIds'] as List? ?? const []))
                  OptionId(id as String),
              ],
              numericAnswer: raw['numericAnswer'] as String?,
            ),
        ],
      );

  Map<String, Object?> toJson() => {
    'templateId': templateId.value,
    'templateVersion': templateVersion.value,
    'answers': [
      for (final answer in answersByQuestion.values)
        {
          'questionId': answer.questionId.value,
          'state': answer.state.name,
          'optionIds': answer.optionIds.map((id) => id.value).toList(),
          'numericAnswer': answer.numericAnswer,
        },
    ],
  };
}

/// P13.8's repeatable printed-paper protocol: mark B on Q01 and C on Q21;
/// leave every other bubble untouched.
PhysicalValidationPlan? buildP13_8DenseKnownAnswerPlan(
  TemplateDefinition template,
) {
  if (template.id.value != 'p13-6-dense-a4-validation' ||
      template.version.value != 1) {
    return null;
  }
  final questions = [
    for (final section in template.sections) ...section.questions,
  ];
  final ids = questions.map((question) => question.id.value).toSet();
  if (!ids.containsAll(const {'dense-q01', 'dense-q21'})) return null;
  return PhysicalValidationPlan(
    templateId: template.id,
    templateVersion: template.version,
    answers: [
      for (final question in questions)
        PhysicalValidationExpectedAnswer(
          questionId: question.id,
          state: const {'dense-q01', 'dense-q21'}.contains(question.id.value)
              ? MarkState.marked
              : MarkState.blank,
          optionIds: switch (question.id.value) {
            'dense-q01' => [OptionId('dense-q01-2')],
            'dense-q21' => [OptionId('dense-q21-3')],
            _ => const [],
          },
        ),
    ],
  );
}

final class PhysicalValidationBubbleRecord {
  const PhysicalValidationBubbleRecord({
    required this.templateId,
    required this.templateVersion,
    required this.pageId,
    required this.questionId,
    required this.questionNumber,
    required this.optionId,
    required this.expectedSelected,
    required this.expectedState,
    required this.expectedAnswer,
    required this.detectedState,
    required this.detectedAnswer,
    required this.decision,
    required this.questionDiagnostics,
    required this.totalProcessingDuration,
    required this.stageDurations,
  });

  final TemplateId templateId;
  final TemplateVersion templateVersion;
  final PageId pageId;
  final QuestionId questionId;
  final int questionNumber;
  final OptionId? optionId;
  final bool expectedSelected;
  final MarkState expectedState;
  final String expectedAnswer;
  final MarkState detectedState;
  final String detectedAnswer;
  final BubbleMarkDecision decision;
  final QuestionClassificationDiagnostics questionDiagnostics;
  final Duration totalProcessingDuration;
  final ScanStageDurations stageDurations;

  Map<String, Object?> toJson() => {
    'templateId': templateId.value,
    'templateVersion': templateVersion.value,
    'pageId': pageId.value,
    'questionId': questionId.value,
    'questionNumber': questionNumber,
    'optionId': optionId?.value,
    'numericColumnIndex': decision.numericColumnIndex,
    'numericDigitValue': decision.numericDigitValue,
    'expectedState': expectedState.name,
    'expectedAnswer': expectedAnswer,
    'expectedSelected': expectedSelected,
    'detectedState': detectedState.name,
    'detectedAnswer': detectedAnswer,
    'fillRatio': decision.fillRatio,
    'coverageScore': decision.coverageScore,
    'normalizedDarkness': decision.normalizedDarkness,
    'darknessContrast': decision.darknessContrast,
    'darknessScore': decision.darknessScore,
    'distributionScore': decision.distributionScore,
    'combinedMarkScore': decision.combinedMarkScore,
    'combinedScore': decision.combinedMarkScore,
    'evidenceCategory': decision.category.name,
    'topScore': questionDiagnostics.topScore,
    'secondScore': questionDiagnostics.secondScore,
    'scoreGap': questionDiagnostics.scoreGap,
    'coverageGap': questionDiagnostics.coverageGap,
    'coverageRatio': questionDiagnostics.coverageRatio,
    'interiorMeanIntensity': decision.interiorMeanIntensity,
    'interiorMedianIntensity': decision.interiorMedianIntensity,
    'localBaselineIntensity': decision.localBaselineIntensity,
    'baselineForegroundRatio': decision.quality.baselineForegroundRatio,
    'localBaselineReliable': decision.quality.localBaselineReliable,
    'interiorValidSampleRatio': decision.quality.interiorValidSampleRatio,
    'baselineValidSampleRatio': decision.quality.baselineValidSampleRatio,
    'totalProcessingMs': totalProcessingDuration.inMicroseconds / 1000,
    'stageTimingsMs': _stageTimingsJson(stageDurations),
  };
}

final class PhysicalValidationQuestionRecord {
  PhysicalValidationQuestionRecord({
    required this.templateId,
    required this.templateVersion,
    required this.pageId,
    required this.expected,
    required this.detected,
    required Iterable<PhysicalValidationBubbleRecord> bubbles,
    required this.totalProcessingDuration,
    required this.stageDurations,
  }) : bubbles = UnmodifiableListView(List.of(bubbles));

  final TemplateId templateId;
  final TemplateVersion templateVersion;
  final PageId pageId;
  final PhysicalValidationExpectedAnswer expected;
  final QuestionClassification detected;
  final List<PhysicalValidationBubbleRecord> bubbles;
  final Duration totalProcessingDuration;
  final ScanStageDurations stageDurations;

  String get detectedAnswer => _detectedAnswer(detected);
  bool get isAmbiguous => detected.state == MarkState.ambiguous;
  bool get isCorrect =>
      detected.state == expected.state &&
      switch (expected.state) {
        MarkState.marked || MarkState.multiple =>
          expected.numericAnswer != null
              ? detected.numericSelection?.completeDigitString ==
                    expected.numericAnswer
              : _sameOptionIds(expected.optionIds, detected.selectedOptionIds),
        _ => true,
      };

  Map<String, Object?> toJson() => {
    'templateId': templateId.value,
    'templateVersion': templateVersion.value,
    'pageId': pageId.value,
    'questionId': expected.questionId.value,
    'questionNumber': detected.questionNumber,
    'expectedState': expected.state.name,
    'expectedAnswer': expected.answerLabel,
    'detectedState': detected.state.name,
    'detectedAnswer': detectedAnswer,
    'correct': isCorrect,
    'topScore': detected.diagnostics.topScore,
    'secondScore': detected.diagnostics.secondScore,
    'scoreGap': detected.diagnostics.scoreGap,
    'coverageGap': detected.diagnostics.coverageGap,
    'coverageRatio': detected.diagnostics.coverageRatio,
    'reason': detected.diagnostics.reason.name,
    'totalProcessingMs': totalProcessingDuration.inMicroseconds / 1000,
    'stageTimingsMs': _stageTimingsJson(stageDurations),
    'bubbles': bubbles.map((bubble) => bubble.toJson()).toList(),
  };
}

final class PhysicalValidationSummary {
  const PhysicalValidationSummary({
    required this.totalQuestions,
    required this.correct,
    required this.wrong,
    required this.ambiguous,
    required this.blankAccuracy,
    required this.markedAccuracy,
    required this.multipleAccuracy,
    required this.falsePositiveMarks,
    required this.falseBlank,
    required this.wrongConfidentCount,
    required this.accuracyPercentage,
    required this.ambiguousPercentage,
    required this.averageProcessingDuration,
  });

  final int totalQuestions;
  final int correct;
  final int wrong;
  final int ambiguous;
  final double blankAccuracy;
  final double markedAccuracy;
  final double multipleAccuracy;
  final int falsePositiveMarks;
  final int falseBlank;
  final int wrongConfidentCount;
  final double accuracyPercentage;
  final double ambiguousPercentage;
  final Duration averageProcessingDuration;

  Map<String, Object?> toJson() => {
    'totalQuestions': totalQuestions,
    'correct': correct,
    'wrong': wrong,
    'ambiguous': ambiguous,
    'blankAccuracy': blankAccuracy,
    'markedAccuracy': markedAccuracy,
    'multipleAccuracy': multipleAccuracy,
    'falsePositiveMarks': falsePositiveMarks,
    'falseBlank': falseBlank,
    'wrongConfidentCount': wrongConfidentCount,
    'accuracyPercentage': accuracyPercentage,
    'ambiguousPercentage': ambiguousPercentage,
    'averageProcessingMs': averageProcessingDuration.inMicroseconds / 1000,
  };
}

final class PhysicalValidationReport {
  PhysicalValidationReport({
    required this.plan,
    required Iterable<PhysicalValidationQuestionRecord> questions,
    required this.summary,
  }) : questions = UnmodifiableListView(List.of(questions));

  factory PhysicalValidationReport.record({
    required PhysicalValidationPlan plan,
    required Iterable<ScanResult> results,
  }) {
    final orderedResults = results.toList(growable: false);
    final records = <PhysicalValidationQuestionRecord>[];
    for (final result in orderedResults) {
      if (result.templateId != plan.templateId ||
          result.templateVersion != plan.templateVersion) {
        throw ArgumentError('Scan result does not match the validation plan.');
      }
      for (final detected in result.questions) {
        final expected = plan.answersByQuestion[detected.questionId];
        if (expected == null) {
          throw ArgumentError(
            'Validation plan has no answer for ${detected.questionId.value}.',
          );
        }
        final detectedAnswer = _detectedAnswer(detected);
        final bubbles = [
          for (final decision in detected.bubbleDecisions)
            PhysicalValidationBubbleRecord(
              templateId: result.templateId,
              templateVersion: result.templateVersion,
              pageId: result.pageId,
              questionId: detected.questionId,
              questionNumber: detected.questionNumber,
              optionId: decision.optionId,
              expectedSelected: _expectedSelected(expected, decision),
              expectedState: expected.state,
              expectedAnswer: expected.answerLabel,
              detectedState: detected.state,
              detectedAnswer: detectedAnswer,
              decision: decision,
              questionDiagnostics: detected.diagnostics,
              totalProcessingDuration:
                  result.diagnostics.totalProcessingDuration,
              stageDurations: result.diagnostics.stageDurations,
            ),
        ];
        records.add(
          PhysicalValidationQuestionRecord(
            templateId: result.templateId,
            templateVersion: result.templateVersion,
            pageId: result.pageId,
            expected: expected,
            detected: detected,
            bubbles: bubbles,
            totalProcessingDuration: result.diagnostics.totalProcessingDuration,
            stageDurations: result.diagnostics.stageDurations,
          ),
        );
      }
    }
    return PhysicalValidationReport(
      plan: plan,
      questions: records,
      summary: _summarize(records, orderedResults),
    );
  }

  final PhysicalValidationPlan plan;
  final List<PhysicalValidationQuestionRecord> questions;
  final PhysicalValidationSummary summary;

  Map<String, Object?> toJson() => {
    'templateId': plan.templateId.value,
    'templateVersion': plan.templateVersion.value,
    'summary': summary.toJson(),
    'questions': questions.map((question) => question.toJson()).toList(),
  };
}

PhysicalValidationSummary _summarize(
  List<PhysicalValidationQuestionRecord> records,
  List<ScanResult> results,
) {
  int expectedCount(MarkState state) =>
      records.where((record) => record.expected.state == state).length;
  int correctCount(MarkState state) => records
      .where((record) => record.expected.state == state && record.isCorrect)
      .length;
  double stateAccuracy(MarkState state) {
    final count = expectedCount(state);
    return count == 0 ? 0 : correctCount(state) / count;
  }

  final correct = records.where((record) => record.isCorrect).length;
  final ambiguous = records.where((record) => record.isAmbiguous).length;
  final totalMicros = results.fold<int>(
    0,
    (sum, result) =>
        sum + result.diagnostics.totalProcessingDuration.inMicroseconds,
  );
  return PhysicalValidationSummary(
    totalQuestions: records.length,
    correct: correct,
    wrong: records.length - correct,
    ambiguous: ambiguous,
    blankAccuracy: stateAccuracy(MarkState.blank),
    markedAccuracy: stateAccuracy(MarkState.marked),
    multipleAccuracy: stateAccuracy(MarkState.multiple),
    falsePositiveMarks: records
        .where(
          (record) =>
              record.expected.state == MarkState.blank &&
              (record.detected.state == MarkState.marked ||
                  record.detected.state == MarkState.multiple),
        )
        .length,
    falseBlank: records
        .where(
          (record) =>
              record.expected.state != MarkState.blank &&
              record.detected.state == MarkState.blank,
        )
        .length,
    wrongConfidentCount: records
        .where(
          (record) =>
              !record.isCorrect &&
              const {
                MarkState.marked,
                MarkState.blank,
                MarkState.multiple,
              }.contains(record.detected.state),
        )
        .length,
    accuracyPercentage: records.isEmpty ? 0 : correct * 100 / records.length,
    ambiguousPercentage: records.isEmpty ? 0 : ambiguous * 100 / records.length,
    averageProcessingDuration: results.isEmpty
        ? Duration.zero
        : Duration(microseconds: totalMicros ~/ results.length),
  );
}

bool _expectedSelected(
  PhysicalValidationExpectedAnswer expected,
  BubbleMarkDecision decision,
) {
  if (decision.optionId != null) {
    return expected.optionIds.contains(decision.optionId);
  }
  final numeric = expected.numericAnswer;
  final column = decision.numericColumnIndex;
  return numeric != null &&
      column != null &&
      column < numeric.length &&
      int.tryParse(numeric[column]) == decision.numericDigitValue;
}

String _detectedAnswer(QuestionClassification classification) =>
    classification.numericSelection?.completeDigitString ??
    (classification.selectedOptionIds.isEmpty
        ? '—'
        : classification.selectedOptionIds.map((id) => id.value).join('+'));

bool _sameOptionIds(List<OptionId> expected, List<OptionId> detected) =>
    expected.length == detected.length &&
    expected.toSet().containsAll(detected);

Map<String, Object?> _stageTimingsJson(ScanStageDurations durations) => {
  'alignment': durations.alignment.inMicroseconds / 1000,
  'preprocessing': durations.preprocessing.inMicroseconds / 1000,
  'measurement': durations.measurement.inMicroseconds / 1000,
  'classification': durations.classification.inMicroseconds / 1000,
  'validation': durations.validation.inMicroseconds / 1000,
};
