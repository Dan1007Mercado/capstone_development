import 'dart:collection';

import '../../../core/ids/identifiers.dart';
import '../../template/domain/question_type.dart';

enum MarkState { marked, blank, multiple, ambiguous, invalid }

enum BubbleEvidenceCategory {
  strongMark,
  possibleMark,
  clearBlank,
  conflicting,
  unreliable,
  invalid,
}

enum BubbleDecisionState { selected, notSelected, uncertain, invalid }

enum ClassificationReason {
  isolatedMark,
  clearBlank,
  multipleStrongMarks,
  closeCandidates,
  uncertainEvidence,
  unusableQuality,
  incompleteNumericGrid,
}

final class BubbleMarkDecision {
  const BubbleMarkDecision({
    required this.pageId,
    required this.questionId,
    required this.optionId,
    required this.numericColumnIndex,
    required this.numericDigitValue,
    required this.fillRatio,
    required this.normalizedDarkness,
    required this.darknessContrast,
    required this.fillComponent,
    required this.normalizedDarknessComponent,
    required this.darknessContrastComponent,
    required this.combinedScore,
    required this.category,
    required this.state,
    required this.qualityUsable,
  });

  final PageId pageId;
  final QuestionId questionId;
  final OptionId? optionId;
  final int? numericColumnIndex;
  final int? numericDigitValue;
  final double fillRatio;
  final double normalizedDarkness;
  final double darknessContrast;
  final double fillComponent;
  final double normalizedDarknessComponent;
  final double darknessContrastComponent;
  final double combinedScore;
  final BubbleEvidenceCategory category;
  final BubbleDecisionState state;
  final bool qualityUsable;

  BubbleMarkDecision withState(BubbleDecisionState value) => BubbleMarkDecision(
    pageId: pageId,
    questionId: questionId,
    optionId: optionId,
    numericColumnIndex: numericColumnIndex,
    numericDigitValue: numericDigitValue,
    fillRatio: fillRatio,
    normalizedDarkness: normalizedDarkness,
    darknessContrast: darknessContrast,
    fillComponent: fillComponent,
    normalizedDarknessComponent: normalizedDarknessComponent,
    darknessContrastComponent: darknessContrastComponent,
    combinedScore: combinedScore,
    category: category,
    state: value,
    qualityUsable: qualityUsable,
  );
}

final class QuestionClassificationDiagnostics {
  const QuestionClassificationDiagnostics({
    required this.topScore,
    required this.secondScore,
    required this.scoreGap,
    required this.reason,
  });

  final double topScore;
  final double secondScore;
  final double scoreGap;
  final ClassificationReason reason;
}

final class NumericColumnClassification {
  NumericColumnClassification({
    required this.columnIndex,
    required this.state,
    required this.selectedDigit,
    required Iterable<BubbleMarkDecision> decisions,
  }) : decisions = UnmodifiableListView(List.of(decisions));

  final int columnIndex;
  final MarkState state;
  final int? selectedDigit;
  final List<BubbleMarkDecision> decisions;
}

final class NumericGridSelection {
  NumericGridSelection(Iterable<NumericColumnClassification> columns)
    : columns = UnmodifiableListView(List.of(columns));

  final List<NumericColumnClassification> columns;

  String? get completeDigitString {
    if (columns.any(
      (column) =>
          column.state != MarkState.marked || column.selectedDigit == null,
    )) {
      return null;
    }
    return columns.map((column) => column.selectedDigit).join();
  }
}

final class QuestionClassification {
  QuestionClassification({
    required this.questionId,
    required this.questionType,
    required this.state,
    required Iterable<OptionId> selectedOptionIds,
    required this.numericSelection,
    required Iterable<BubbleMarkDecision> bubbleDecisions,
    required this.diagnostics,
  }) : selectedOptionIds = UnmodifiableListView(List.of(selectedOptionIds)),
       bubbleDecisions = UnmodifiableListView(List.of(bubbleDecisions));

  final QuestionId questionId;
  final QuestionType questionType;
  final MarkState state;
  final List<OptionId> selectedOptionIds;
  final NumericGridSelection? numericSelection;
  final List<BubbleMarkDecision> bubbleDecisions;
  final QuestionClassificationDiagnostics diagnostics;
}

final class PageClassificationResult {
  PageClassificationResult({
    required this.pageId,
    required Iterable<QuestionClassification> questions,
  }) : questions = UnmodifiableListView(List.of(questions));

  final PageId pageId;
  final List<QuestionClassification> questions;
}
