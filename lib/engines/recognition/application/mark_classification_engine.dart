import '../../../core/errors/engine_error.dart';
import '../../../core/ids/identifiers.dart';
import '../../../core/result/engine_result.dart';
import '../../layout/domain/layout_regions.dart';
import '../../layout/domain/page_layout.dart';
import '../../template/domain/question_type.dart';
import '../../template/domain/template_definition.dart';
import '../../template/domain/template_question.dart';
import '../domain/bubble_measurement.dart';
import '../domain/mark_classification.dart';
import '../domain/mark_classification_config.dart';
import 'bubble_evidence_evaluator.dart';

final class MarkClassificationEngine {
  const MarkClassificationEngine({
    this.evaluator = const BubbleEvidenceEvaluator(),
  });

  final BubbleEvidenceEvaluator evaluator;

  EngineResult<PageClassificationResult> classify(
    TemplateDefinition template,
    PageLayout page,
    BubbleMeasurementSet measurements, [
    MarkClassificationConfig config = const MarkClassificationConfig(),
  ]) {
    final configError = config.validationMessage();
    if (configError != null) {
      return _failure('MARK_CLASSIFICATION_INVALID_CONFIG', configError);
    }
    if (page.templateId != template.id ||
        page.templateVersion != template.version) {
      return _failure(
        'MARK_CLASSIFICATION_TEMPLATE_MISMATCH',
        'PageLayout does not belong to the supplied template version.',
      );
    }
    if (measurements.pageId != page.pageId ||
        measurements.measurements.any(
          (measurement) => measurement.pageId != page.pageId,
        )) {
      return _failure(
        'MARK_CLASSIFICATION_PAGE_MISMATCH',
        'Measurements do not belong to the supplied page.',
      );
    }

    try {
      final templateQuestions = <QuestionId, TemplateQuestion>{};
      for (final section in template.sections) {
        for (final question in section.questions) {
          if (templateQuestions.containsKey(question.id)) {
            return _failure(
              'MARK_CLASSIFICATION_TEMPLATE_MISMATCH',
              'Template contains duplicate question identities.',
            );
          }
          templateQuestions[question.id] = question;
        }
      }

      final expected = <_TargetKey, BubbleRegion>{};
      for (final bubble in page.bubbleRegions) {
        final key = _TargetKey.fromBubble(bubble);
        if (expected.containsKey(key)) {
          return _failure(
            'MARK_CLASSIFICATION_MEASUREMENT_MISMATCH',
            'PageLayout contains a duplicate bubble target.',
          );
        }
        expected[key] = bubble;
      }

      final actual = <_TargetKey, BubbleMeasurement>{};
      for (final measurement in measurements.measurements) {
        if (!_validMeasurement(measurement)) {
          return _failure(
            'MARK_CLASSIFICATION_INVALID_MEASUREMENT',
            'A bubble measurement contains invalid numeric evidence.',
            {'questionId': measurement.questionId.value},
          );
        }
        final key = _TargetKey.fromMeasurement(measurement);
        if (actual.containsKey(key)) {
          return _failure(
            'MARK_CLASSIFICATION_MEASUREMENT_MISMATCH',
            'Duplicate measurement target detected.',
            {'questionId': measurement.questionId.value},
          );
        }
        if (!expected.containsKey(key)) {
          return _failure(
            'MARK_CLASSIFICATION_MEASUREMENT_MISMATCH',
            'Unknown measurement target detected.',
            {'questionId': measurement.questionId.value},
          );
        }
        actual[key] = measurement;
      }
      if (actual.length != expected.length ||
          expected.keys.any((key) => !actual.containsKey(key))) {
        return _failure(
          'MARK_CLASSIFICATION_MEASUREMENT_MISMATCH',
          'Every PageLayout bubble must have exactly one measurement.',
          {'expectedCount': expected.length, 'actualCount': actual.length},
        );
      }

      final assignedKeys = <_TargetKey>{};
      final classifications = <QuestionClassification>[];
      final seenQuestionIds = <QuestionId>{};
      for (final region in page.questionRegions) {
        if (!seenQuestionIds.add(region.questionId)) {
          return _failure(
            'MARK_CLASSIFICATION_TEMPLATE_MISMATCH',
            'PageLayout contains duplicate question regions.',
          );
        }
        final question = templateQuestions[region.questionId];
        if (question == null || question.type != region.questionType) {
          return _failure(
            'MARK_CLASSIFICATION_TEMPLATE_MISMATCH',
            'Question semantics do not match the PageLayout.',
            {'questionId': region.questionId.value},
          );
        }
        final structuralError = _validateQuestionStructure(question, region);
        if (structuralError != null) {
          return _failure(
            'MARK_CLASSIFICATION_TEMPLATE_MISMATCH',
            structuralError,
            {'questionId': region.questionId.value},
          );
        }
        final orderedMeasurements = <BubbleMeasurement>[];
        for (final bubble in region.bubbleRegions) {
          final key = _TargetKey.fromBubble(bubble);
          if (!expected.containsKey(key) || !assignedKeys.add(key)) {
            return _failure(
              'MARK_CLASSIFICATION_MEASUREMENT_MISMATCH',
              'Question-region bubbles do not match the page bubble contract.',
              {'questionId': region.questionId.value},
            );
          }
          orderedMeasurements.add(actual[key]!);
        }
        classifications.add(
          _classifyQuestion(question, orderedMeasurements, config),
        );
      }
      if (assignedKeys.length != expected.length) {
        return _failure(
          'MARK_CLASSIFICATION_MEASUREMENT_MISMATCH',
          'Some page bubbles are not owned by an ordered question region.',
        );
      }
      return EngineResult.success(
        PageClassificationResult(
          pageId: page.pageId,
          questions: classifications,
        ),
      );
    } on Object catch (error) {
      return _failure(
        'MARK_CLASSIFICATION_FAILED',
        'Mark classification failed unexpectedly.',
        {'cause': error.toString()},
      );
    }
  }

  QuestionClassification _classifyQuestion(
    TemplateQuestion question,
    List<BubbleMeasurement> measurements,
    MarkClassificationConfig config,
  ) {
    final decisions = measurements
        .map((measurement) => evaluator.evaluate(measurement, config))
        .toList(growable: false);
    if (question.type == QuestionType.numericGrid) {
      return _classifyNumeric(question, decisions, config);
    }
    if (question.type == QuestionType.multipleChoice) {
      return _classifyMultipleChoice(question, decisions);
    }
    final outcome = _classifyExclusive(decisions, config);
    return QuestionClassification(
      questionId: question.id,
      questionType: question.type,
      state: outcome.state,
      selectedOptionIds:
          outcome.state == MarkState.marked ||
              outcome.state == MarkState.multiple
          ? outcome.selected
                .map((decision) => decision.optionId)
                .whereType<OptionId>()
          : const [],
      numericSelection: null,
      bubbleDecisions: outcome.decisions,
      diagnostics: outcome.diagnostics,
    );
  }

  QuestionClassification _classifyMultipleChoice(
    TemplateQuestion question,
    List<BubbleMarkDecision> decisions,
  ) {
    final checklistDecisions = decisions
        .map(
          (decision) => decision.category == BubbleEvidenceCategory.possibleMark
              ? decision.withState(BubbleDecisionState.selected)
              : decision,
        )
        .toList(growable: false);
    final scores = _scores(checklistDecisions);
    if (checklistDecisions.any(
      (decision) => decision.category == BubbleEvidenceCategory.invalid,
    )) {
      return _question(
        question,
        MarkState.invalid,
        checklistDecisions,
        const [],
        scores,
        ClassificationReason.unusableQuality,
      );
    }
    if (checklistDecisions.any(
      (decision) =>
          decision.category == BubbleEvidenceCategory.conflicting ||
          decision.category == BubbleEvidenceCategory.unreliable,
    )) {
      return _question(
        question,
        MarkState.ambiguous,
        checklistDecisions,
        const [],
        scores,
        ClassificationReason.uncertainEvidence,
      );
    }
    final selected = checklistDecisions
        .where((decision) => decision.state == BubbleDecisionState.selected)
        .toList(growable: false);
    return _question(
      question,
      selected.isEmpty ? MarkState.blank : MarkState.marked,
      checklistDecisions,
      selected.map((decision) => decision.optionId).whereType<OptionId>(),
      scores,
      selected.isEmpty
          ? ClassificationReason.clearBlank
          : ClassificationReason.isolatedMark,
    );
  }

  QuestionClassification _classifyNumeric(
    TemplateQuestion question,
    List<BubbleMarkDecision> decisions,
    MarkClassificationConfig config,
  ) {
    final columns = <NumericColumnClassification>[];
    final columnCount = question.numericGridSpec!.columnCount;
    for (var columnIndex = 0; columnIndex < columnCount; columnIndex++) {
      final columnDecisions = decisions
          .where((decision) => decision.numericColumnIndex == columnIndex)
          .toList(growable: false);
      final outcome = _classifyExclusive(columnDecisions, config);
      columns.add(
        NumericColumnClassification(
          columnIndex: columnIndex,
          state: outcome.state,
          selectedDigit: outcome.state == MarkState.marked
              ? outcome.selected.single.numericDigitValue
              : null,
          decisions: outcome.decisions,
        ),
      );
    }
    final states = columns.map((column) => column.state).toList();
    late final MarkState state;
    late final ClassificationReason reason;
    if (states.contains(MarkState.invalid)) {
      state = MarkState.invalid;
      reason = ClassificationReason.unusableQuality;
    } else if (states.contains(MarkState.multiple)) {
      state = MarkState.multiple;
      reason = ClassificationReason.multipleStrongMarks;
    } else if (states.contains(MarkState.ambiguous)) {
      state = MarkState.ambiguous;
      reason = ClassificationReason.uncertainEvidence;
    } else if (states.every((column) => column == MarkState.blank)) {
      state = MarkState.blank;
      reason = ClassificationReason.clearBlank;
    } else if (states.every((column) => column == MarkState.marked)) {
      state = MarkState.marked;
      reason = ClassificationReason.isolatedMark;
    } else {
      state = MarkState.ambiguous;
      reason = ClassificationReason.incompleteNumericGrid;
    }
    final scores = _scores(decisions);
    return QuestionClassification(
      questionId: question.id,
      questionType: question.type,
      state: state,
      selectedOptionIds: const [],
      numericSelection: NumericGridSelection(columns),
      bubbleDecisions: columns.expand((column) => column.decisions),
      diagnostics: QuestionClassificationDiagnostics(
        topScore: scores.$1,
        secondScore: scores.$2,
        scoreGap: scores.$1 - scores.$2,
        reason: reason,
      ),
    );
  }

  _ExclusiveOutcome _classifyExclusive(
    List<BubbleMarkDecision> decisions,
    MarkClassificationConfig config,
  ) {
    final scores = _scores(decisions);
    QuestionClassificationDiagnostics diagnostics(
      ClassificationReason reason,
    ) => QuestionClassificationDiagnostics(
      topScore: scores.$1,
      secondScore: scores.$2,
      scoreGap: scores.$1 - scores.$2,
      reason: reason,
    );
    final invalid = decisions.where(
      (decision) => decision.category == BubbleEvidenceCategory.invalid,
    );
    if (invalid.isNotEmpty) {
      return _ExclusiveOutcome(
        MarkState.invalid,
        const [],
        decisions,
        diagnostics(ClassificationReason.unusableQuality),
      );
    }
    final strong = decisions
        .where(
          (decision) => decision.category == BubbleEvidenceCategory.strongMark,
        )
        .toList(growable: false);
    if (strong.length >= 2) {
      return _ExclusiveOutcome(
        MarkState.multiple,
        strong,
        decisions,
        diagnostics(ClassificationReason.multipleStrongMarks),
      );
    }
    final unreliableOrConflicting = decisions.any(
      (decision) =>
          decision.category == BubbleEvidenceCategory.unreliable ||
          decision.category == BubbleEvidenceCategory.conflicting,
    );
    final possible = decisions
        .where(
          (decision) =>
              decision.category == BubbleEvidenceCategory.possibleMark,
        )
        .toList(growable: false);
    if (strong.length == 1) {
      final top = strong.single;
      final closePossible = possible.any(
        (candidate) =>
            top.combinedScore - candidate.combinedScore <
            config.minimumTopSecondGap,
      );
      if (unreliableOrConflicting || closePossible) {
        return _ExclusiveOutcome(
          MarkState.ambiguous,
          const [],
          decisions,
          diagnostics(ClassificationReason.uncertainEvidence),
        );
      }
      return _ExclusiveOutcome(
        MarkState.marked,
        [top],
        decisions,
        diagnostics(ClassificationReason.isolatedMark),
      );
    }
    if (unreliableOrConflicting) {
      return _ExclusiveOutcome(
        MarkState.ambiguous,
        const [],
        decisions,
        diagnostics(ClassificationReason.uncertainEvidence),
      );
    }
    if (possible.isEmpty) {
      return _ExclusiveOutcome(
        MarkState.blank,
        const [],
        decisions,
        diagnostics(ClassificationReason.clearBlank),
      );
    }
    final ranked = List<BubbleMarkDecision>.of(possible)
      ..sort(
        (first, second) => second.combinedScore.compareTo(first.combinedScore),
      );
    final candidate = ranked.first;
    if (candidate.combinedScore - scores.$2 >= config.minimumTopSecondGap) {
      final updated = decisions
          .map(
            (decision) => identical(decision, candidate)
                ? decision.withState(BubbleDecisionState.selected)
                : decision,
          )
          .toList(growable: false);
      return _ExclusiveOutcome(
        MarkState.marked,
        [candidate.withState(BubbleDecisionState.selected)],
        updated,
        diagnostics(ClassificationReason.isolatedMark),
      );
    }
    return _ExclusiveOutcome(
      MarkState.ambiguous,
      const [],
      decisions,
      diagnostics(ClassificationReason.closeCandidates),
    );
  }

  QuestionClassification _question(
    TemplateQuestion question,
    MarkState state,
    List<BubbleMarkDecision> decisions,
    Iterable<OptionId> selected,
    (double, double) scores,
    ClassificationReason reason,
  ) => QuestionClassification(
    questionId: question.id,
    questionType: question.type,
    state: state,
    selectedOptionIds: selected,
    numericSelection: null,
    bubbleDecisions: decisions,
    diagnostics: QuestionClassificationDiagnostics(
      topScore: scores.$1,
      secondScore: scores.$2,
      scoreGap: scores.$1 - scores.$2,
      reason: reason,
    ),
  );

  (double, double) _scores(List<BubbleMarkDecision> decisions) {
    final scores = decisions.map((decision) => decision.combinedScore).toList()
      ..sort((first, second) => second.compareTo(first));
    return (
      scores.isEmpty ? 0 : scores.first,
      scores.length < 2 ? 0 : scores[1],
    );
  }

  String? _validateQuestionStructure(
    TemplateQuestion question,
    QuestionRegion region,
  ) {
    if (region.bubbleRegions.isEmpty) return 'Question has no layout bubbles.';
    if (question.type == QuestionType.numericGrid) {
      final spec = question.numericGridSpec;
      if (spec == null) return 'Numeric-grid specification is missing.';
      final expected = <(int, int)>{
        for (var column = 0; column < spec.columnCount; column++)
          for (final digit in spec.allowedDigits) (column, digit),
      };
      final actual = <(int, int)>{};
      for (final bubble in region.bubbleRegions) {
        if (!bubble.isNumericCellTarget || bubble.optionId != null) {
          return 'Numeric-grid layout contains an invalid bubble identity.';
        }
        if (!actual.add((
          bubble.numericColumnIndex!,
          bubble.numericDigitValue!,
        ))) {
          return 'Numeric-grid layout contains a duplicate cell.';
        }
      }
      if (actual.length != expected.length || !actual.containsAll(expected)) {
        return 'Numeric-grid layout does not match its template specification.';
      }
      return null;
    }
    final expected = question.options.map((option) => option.id).toSet();
    final actual = <OptionId>{};
    for (final bubble in region.bubbleRegions) {
      if (!bubble.isOptionTarget || bubble.isNumericCellTarget) {
        return 'Option question contains an invalid bubble identity.';
      }
      if (!actual.add(bubble.optionId!)) {
        return 'Option question layout contains a duplicate target.';
      }
    }
    if (actual.length != expected.length || !actual.containsAll(expected)) {
      return 'Option layout does not match the template options.';
    }
    return null;
  }

  bool _validMeasurement(BubbleMeasurement measurement) =>
      measurement.fillRatio.isFinite &&
      measurement.fillRatio >= 0 &&
      measurement.fillRatio <= 1 &&
      measurement.normalizedDarkness.isFinite &&
      measurement.darknessContrast.isFinite &&
      measurement.interiorMeanIntensity.isFinite &&
      measurement.interiorMedianIntensity.isFinite &&
      measurement.localBaselineIntensity.isFinite &&
      measurement.sampledInteriorPixelCount > 0 &&
      measurement.sampledBaselinePixelCount > 0 &&
      _unit(measurement.quality.interiorValidSampleRatio) &&
      _unit(measurement.quality.baselineValidSampleRatio) &&
      _unit(measurement.quality.baselineForegroundRatio);

  bool _unit(double value) => value.isFinite && value >= 0 && value <= 1;

  EngineResult<PageClassificationResult> _failure(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );
}

final class _ExclusiveOutcome {
  const _ExclusiveOutcome(
    this.state,
    this.selected,
    this.decisions,
    this.diagnostics,
  );

  final MarkState state;
  final List<BubbleMarkDecision> selected;
  final List<BubbleMarkDecision> decisions;
  final QuestionClassificationDiagnostics diagnostics;
}

final class _TargetKey {
  const _TargetKey({
    required this.pageId,
    required this.questionId,
    required this.optionId,
    required this.numericColumnIndex,
    required this.numericDigitValue,
  });

  factory _TargetKey.fromBubble(BubbleRegion bubble) => _TargetKey(
    pageId: bubble.pageId,
    questionId: bubble.questionId,
    optionId: bubble.optionId,
    numericColumnIndex: bubble.numericColumnIndex,
    numericDigitValue: bubble.numericDigitValue,
  );

  factory _TargetKey.fromMeasurement(BubbleMeasurement measurement) =>
      _TargetKey(
        pageId: measurement.pageId,
        questionId: measurement.questionId,
        optionId: measurement.optionId,
        numericColumnIndex: measurement.numericColumnIndex,
        numericDigitValue: measurement.numericDigitValue,
      );

  final PageId pageId;
  final QuestionId questionId;
  final OptionId? optionId;
  final int? numericColumnIndex;
  final int? numericDigitValue;

  @override
  bool operator ==(Object other) =>
      other is _TargetKey &&
      other.pageId == pageId &&
      other.questionId == questionId &&
      other.optionId == optionId &&
      other.numericColumnIndex == numericColumnIndex &&
      other.numericDigitValue == numericDigitValue;

  @override
  int get hashCode => Object.hash(
    pageId,
    questionId,
    optionId,
    numericColumnIndex,
    numericDigitValue,
  );
}
