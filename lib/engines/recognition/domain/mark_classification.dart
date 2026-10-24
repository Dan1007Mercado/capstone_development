import 'dart:collection';

import '../../../core/ids/identifiers.dart';
import '../../template/domain/question_type.dart';
import 'bubble_measurement.dart';

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
  singleStrongMark,
  strongCoverageDominance,
  borderlineMark,
  clearBlank,
  multipleStrongMarks,
  closeCandidates,
  ambiguousCandidates,
  uncertainEvidence,
  unreliableBaseline,
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
    required this.coverageScore,
    required this.normalizedDarknessComponent,
    required this.darknessContrastComponent,
    required this.darknessScore,
    required this.distributionScore,
    required this.combinedMarkScore,
    required this.category,
    required this.state,
    required this.qualityUsable,
    required this.interiorMeanIntensity,
    required this.interiorMedianIntensity,
    required this.localBaselineIntensity,
    required this.foregroundPixelCount,
    required this.quality,
  });

  final PageId pageId;
  final QuestionId questionId;
  final OptionId? optionId;
  final int? numericColumnIndex;
  final int? numericDigitValue;
  final double fillRatio;
  final double normalizedDarkness;
  final double darknessContrast;
  final double coverageScore;
  final double normalizedDarknessComponent;
  final double darknessContrastComponent;
  final double darknessScore;
  final double distributionScore;
  final double combinedMarkScore;
  final BubbleEvidenceCategory category;
  final BubbleDecisionState state;
  final bool qualityUsable;
  final double interiorMeanIntensity;
  final double interiorMedianIntensity;
  final double localBaselineIntensity;
  final int foregroundPixelCount;
  final BubbleMeasurementQuality quality;

  /// Compatibility aliases for existing reports while callers migrate to the
  /// explicit coverage-weighted terminology.
  double get fillComponent => coverageScore;
  double get combinedScore => combinedMarkScore;

  BubbleMarkDecision withState(BubbleDecisionState value) => BubbleMarkDecision(
    pageId: pageId,
    questionId: questionId,
    optionId: optionId,
    numericColumnIndex: numericColumnIndex,
    numericDigitValue: numericDigitValue,
    fillRatio: fillRatio,
    normalizedDarkness: normalizedDarkness,
    darknessContrast: darknessContrast,
    coverageScore: coverageScore,
    normalizedDarknessComponent: normalizedDarknessComponent,
    darknessContrastComponent: darknessContrastComponent,
    darknessScore: darknessScore,
    distributionScore: distributionScore,
    combinedMarkScore: combinedMarkScore,
    category: category,
    state: value,
    qualityUsable: qualityUsable,
    interiorMeanIntensity: interiorMeanIntensity,
    interiorMedianIntensity: interiorMedianIntensity,
    localBaselineIntensity: localBaselineIntensity,
    foregroundPixelCount: foregroundPixelCount,
    quality: quality,
  );
}

final class QuestionClassificationDiagnostics {
  const QuestionClassificationDiagnostics({
    required this.topScore,
    required this.secondScore,
    required this.scoreGap,
    required this.reason,
    this.topCoverage = 0,
    this.secondCoverage = 0,
    this.coverageGap = 0,
    this.coverageRatio = 0,
  });

  final double topScore;
  final double secondScore;
  final double scoreGap;
  final double topCoverage;
  final double secondCoverage;
  final double coverageGap;
  final double coverageRatio;
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
    required this.questionNumber,
    required this.questionType,
    required this.state,
    required Iterable<OptionId> selectedOptionIds,
    required this.numericSelection,
    required Iterable<BubbleMarkDecision> bubbleDecisions,
    required this.diagnostics,
  }) : selectedOptionIds = UnmodifiableListView(List.of(selectedOptionIds)),
       bubbleDecisions = UnmodifiableListView(List.of(bubbleDecisions));

  final QuestionId questionId;

  /// One-based logical number copied from the authoritative [QuestionRegion].
  final int questionNumber;
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
