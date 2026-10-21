import 'dart:collection';

import 'layout_value_equality.dart';

/// Centralized deterministic policy for adaptive dense-layout selection.
final class LayoutSelectionPolicy {
  const LayoutSelectionPolicy({
    this.minimumColumnWidthMm = 34,
    this.minimumColumnGapMm = 4,
    this.minimumBubbleDiameterMm = 5,
    this.minimumBubbleClearanceMm = 1,
    this.maximumPreferredPromptLines = 2,
    this.maximumAllowedPromptLines = 6,
    this.maximumHorizontalOptionLabelCharacters = 12,
    this.pagePenalty = 10000,
    this.unusedAreaPenalty = 100,
    this.wrapPenalty = 100,
    this.questionModeFallbackPenalty = 500,
    this.sectionFragmentPenalty = 25,
    this.preferredColumnDeviationPenalty = 25,
  });

  /// Smallest readable/scanner-safe flow lane for the current print style.
  final double minimumColumnWidthMm;

  /// Physical separation between adjacent flow lanes.
  final double minimumColumnGapMm;

  /// Physical bubble floor; density must come from flow, not smaller targets.
  final double minimumBubbleDiameterMm;

  /// Required clear edge-to-edge distance between bubble targets.
  final double minimumBubbleClearanceMm;

  /// Wrapping beyond this count is valid but contributes selection cost.
  final int maximumPreferredPromptLines;

  /// A column candidate exceeding this is rejected as unreadable.
  final int maximumAllowedPromptLines;

  /// Longer labels use stacked rows instead of compressed horizontal cells.
  final int maximumHorizontalOptionLabelCharacters;

  final double pagePenalty;
  final double unusedAreaPenalty;
  final double wrapPenalty;
  final double questionModeFallbackPenalty;
  final double sectionFragmentPenalty;
  final double preferredColumnDeviationPenalty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutSelectionPolicy &&
          other.minimumColumnWidthMm == minimumColumnWidthMm &&
          other.minimumColumnGapMm == minimumColumnGapMm &&
          other.minimumBubbleDiameterMm == minimumBubbleDiameterMm &&
          other.minimumBubbleClearanceMm == minimumBubbleClearanceMm &&
          other.maximumPreferredPromptLines == maximumPreferredPromptLines &&
          other.maximumAllowedPromptLines == maximumAllowedPromptLines &&
          other.maximumHorizontalOptionLabelCharacters ==
              maximumHorizontalOptionLabelCharacters &&
          other.pagePenalty == pagePenalty &&
          other.unusedAreaPenalty == unusedAreaPenalty &&
          other.wrapPenalty == wrapPenalty &&
          other.questionModeFallbackPenalty == questionModeFallbackPenalty &&
          other.sectionFragmentPenalty == sectionFragmentPenalty &&
          other.preferredColumnDeviationPenalty ==
              preferredColumnDeviationPenalty;

  @override
  int get hashCode => Object.hashAll([
    minimumColumnWidthMm,
    minimumColumnGapMm,
    minimumBubbleDiameterMm,
    minimumBubbleClearanceMm,
    maximumPreferredPromptLines,
    maximumAllowedPromptLines,
    maximumHorizontalOptionLabelCharacters,
    pagePenalty,
    unusedAreaPenalty,
    wrapPenalty,
    questionModeFallbackPenalty,
    sectionFragmentPenalty,
    preferredColumnDeviationPenalty,
  ]);
}

/// Developer-facing measurements for one simulated column candidate.
final class LayoutCandidateDiagnostics {
  LayoutCandidateDiagnostics({
    required this.columnCount,
    required this.pageCount,
    required this.unusedAreaRatio,
    required this.excessivePromptWrappingCount,
    required this.questionModeFallbackCount,
    required this.sectionFragmentCount,
    required this.inlineQuestionCount,
    required this.stackedQuestionCount,
    required this.cost,
    required Iterable<String> rejectedReasons,
  }) : rejectedReasons = UnmodifiableListView(List.of(rejectedReasons));

  final int columnCount;
  final int pageCount;
  final double unusedAreaRatio;
  final int excessivePromptWrappingCount;
  final int questionModeFallbackCount;
  final int sectionFragmentCount;
  final int inlineQuestionCount;
  final int stackedQuestionCount;
  final double cost;
  final List<String> rejectedReasons;

  bool get isValid => rejectedReasons.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutCandidateDiagnostics &&
          other.columnCount == columnCount &&
          other.pageCount == pageCount &&
          other.unusedAreaRatio == unusedAreaRatio &&
          other.excessivePromptWrappingCount == excessivePromptWrappingCount &&
          other.questionModeFallbackCount == questionModeFallbackCount &&
          other.sectionFragmentCount == sectionFragmentCount &&
          other.inlineQuestionCount == inlineQuestionCount &&
          other.stackedQuestionCount == stackedQuestionCount &&
          other.cost == cost &&
          layoutListEquals(other.rejectedReasons, rejectedReasons);

  @override
  int get hashCode => Object.hashAll([
    columnCount,
    pageCount,
    unusedAreaRatio,
    excessivePromptWrappingCount,
    questionModeFallbackCount,
    sectionFragmentCount,
    inlineQuestionCount,
    stackedQuestionCount,
    cost,
    Object.hashAll(rejectedReasons),
  ]);
}

final class LayoutSelectionDiagnostics {
  LayoutSelectionDiagnostics({
    required this.selectedColumnCount,
    required Iterable<LayoutCandidateDiagnostics> candidates,
  }) : candidates = UnmodifiableListView(List.of(candidates));

  final int selectedColumnCount;
  final List<LayoutCandidateDiagnostics> candidates;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutSelectionDiagnostics &&
          other.selectedColumnCount == selectedColumnCount &&
          layoutListEquals(other.candidates, candidates);

  @override
  int get hashCode =>
      Object.hash(selectedColumnCount, Object.hashAll(candidates));
}
