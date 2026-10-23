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
    this.pagePenalty = 100,
    this.unusedAreaPenalty = 10,
    this.wrapPenalty = 10000,
    this.questionModeFallbackPenalty = 20000,
    this.stackedVerticalFallbackPenalty = 5000,
    this.sectionFragmentPenalty = 25,
    this.preferredColumnDeviationPenalty = 1000,
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
  final double stackedVerticalFallbackPenalty;
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
          other.stackedVerticalFallbackPenalty ==
              stackedVerticalFallbackPenalty &&
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
    stackedVerticalFallbackPenalty,
    sectionFragmentPenalty,
    preferredColumnDeviationPenalty,
  ]);
}

/// Developer-facing measurements for one simulated column candidate.
final class LayoutCandidateDiagnostics {
  LayoutCandidateDiagnostics({
    required this.columnCount,
    required this.columnWidthMm,
    required this.columnGapMm,
    required this.bubbleDiameterMm,
    required this.pageCount,
    required this.unusedAreaRatio,
    required this.promptWrappingCount,
    required this.excessivePromptWrappingCount,
    required this.stackedVerticalFallbackCount,
    required this.fullWidthFallbackCount,
    required this.questionModeFallbackCount,
    required this.sectionFragmentCount,
    required this.continuationCount,
    required this.inlineQuestionCount,
    required this.stackedQuestionCount,
    required this.cost,
    required Iterable<String> rejectedReasons,
  }) : rejectedReasons = UnmodifiableListView(List.of(rejectedReasons));

  final int columnCount;
  final double columnWidthMm;
  final double columnGapMm;
  final double bubbleDiameterMm;
  final int pageCount;
  final double unusedAreaRatio;
  final int promptWrappingCount;
  final int excessivePromptWrappingCount;
  final int stackedVerticalFallbackCount;
  final int fullWidthFallbackCount;
  final int questionModeFallbackCount;
  final int sectionFragmentCount;
  final int continuationCount;
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
          other.columnWidthMm == columnWidthMm &&
          other.columnGapMm == columnGapMm &&
          other.bubbleDiameterMm == bubbleDiameterMm &&
          other.pageCount == pageCount &&
          other.unusedAreaRatio == unusedAreaRatio &&
          other.promptWrappingCount == promptWrappingCount &&
          other.excessivePromptWrappingCount == excessivePromptWrappingCount &&
          other.stackedVerticalFallbackCount == stackedVerticalFallbackCount &&
          other.fullWidthFallbackCount == fullWidthFallbackCount &&
          other.questionModeFallbackCount == questionModeFallbackCount &&
          other.sectionFragmentCount == sectionFragmentCount &&
          other.continuationCount == continuationCount &&
          other.inlineQuestionCount == inlineQuestionCount &&
          other.stackedQuestionCount == stackedQuestionCount &&
          other.cost == cost &&
          layoutListEquals(other.rejectedReasons, rejectedReasons);

  @override
  int get hashCode => Object.hashAll([
    columnCount,
    columnWidthMm,
    columnGapMm,
    bubbleDiameterMm,
    pageCount,
    unusedAreaRatio,
    promptWrappingCount,
    excessivePromptWrappingCount,
    stackedVerticalFallbackCount,
    fullWidthFallbackCount,
    questionModeFallbackCount,
    sectionFragmentCount,
    continuationCount,
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
