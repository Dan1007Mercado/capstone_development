import '../../../core/geometry/page_spec.dart';
import '../../../core/geometry/physical_geometry.dart';
import 'layout_selection.dart';

enum LayoutProfile { comfortable, dense, answerSheet }

/// Configurable IDs assigned to the four marker roles.
final class MarkerIds {
  const MarkerIds({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  static const defaults = MarkerIds(
    topLeft: 10,
    topRight: 11,
    bottomLeft: 12,
    bottomRight: 13,
  );

  final int topLeft;
  final int topRight;
  final int bottomLeft;
  final int bottomRight;

  List<int> get values => [topLeft, topRight, bottomLeft, bottomRight];

  bool get areUnique => values.toSet().length == values.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkerIds &&
          other.topLeft == topLeft &&
          other.topRight == topRight &&
          other.bottomLeft == bottomLeft &&
          other.bottomRight == bottomRight;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomLeft, bottomRight);
}

/// Explicit policy values used by the deterministic flow layout.
///
/// Defaults are initial engineering values and require later physical
/// print/scan calibration before they can be treated as production constants.
final class LayoutConfig {
  const LayoutConfig({
    required this.profile,
    required this.pageSpec,
    required this.margins,
    required this.canonicalPageSpec,
    required this.markerSizeMm,
    required this.markerInsetMm,
    required this.markerIds,
    required this.bubbleDiameterMm,
    required this.bubbleHorizontalGapMm,
    required this.bubbleVerticalGapMm,
    required this.optionCellWidthMm,
    required this.questionVerticalGapMm,
    required this.sectionGapMm,
    required this.headerHeightMm,
    required this.identityRegionHeightMm,
    required this.minimumContentGapMm,
    required this.estimatedLineHeightMm,
    required this.estimatedCharactersPerLine,
    required this.estimatedTextWidthMm,
    required this.humanReadableFieldHeightMm,
    required this.columnCount,
    required this.columnGapMm,
    required this.maximumColumnPromptLines,
    this.allowedColumnCounts = const [1],
    this.adaptiveColumns = false,
    this.preferredColumnCount = 1,
    this.selectionPolicy = const LayoutSelectionPolicy(),
    this.answerGroupHeadingHeightMm = 0,
    this.questionNumberWidthMm = 0,
    this.bubbleLabelCenterExclusionRatio = 0,
  });

  factory LayoutConfig.a4Default() =>
      LayoutConfig.forProfile(LayoutProfile.comfortable);

  factory LayoutConfig.a4Dense() =>
      LayoutConfig.forProfile(LayoutProfile.dense);

  factory LayoutConfig.a4AnswerSheet() =>
      LayoutConfig.forProfile(LayoutProfile.answerSheet);

  factory LayoutConfig.forProfile(LayoutProfile profile) => switch (profile) {
    LayoutProfile.comfortable => LayoutConfig(
      profile: LayoutProfile.comfortable,
      pageSpec: PageSpec.a4Portrait(),
      margins: PageMargins.all(PhysicalLength(12)),
      canonicalPageSpec: CanonicalPageSpec.a4FromWidth(2100),
      markerSizeMm: 14,
      markerInsetMm: 10,
      markerIds: MarkerIds.defaults,
      bubbleDiameterMm: 5,
      bubbleHorizontalGapMm: 5,
      bubbleVerticalGapMm: 3,
      optionCellWidthMm: 28,
      questionVerticalGapMm: 6,
      sectionGapMm: 8,
      headerHeightMm: 10,
      identityRegionHeightMm: 12,
      minimumContentGapMm: 4,
      estimatedLineHeightMm: 5,
      estimatedCharactersPerLine: 70,
      estimatedTextWidthMm: 154,
      humanReadableFieldHeightMm: 12,
      columnCount: 1,
      columnGapMm: 6,
      maximumColumnPromptLines: 1000,
      allowedColumnCounts: const [1],
      adaptiveColumns: false,
      preferredColumnCount: 1,
    ),
    LayoutProfile.dense => LayoutConfig(
      profile: LayoutProfile.dense,
      pageSpec: PageSpec.a4Portrait(),
      margins: PageMargins.all(PhysicalLength(12)),
      canonicalPageSpec: CanonicalPageSpec.a4FromWidth(2100),
      markerSizeMm: 14,
      markerInsetMm: 10,
      markerIds: MarkerIds.defaults,
      bubbleDiameterMm: 5,
      bubbleHorizontalGapMm: 1.5,
      bubbleVerticalGapMm: 2,
      optionCellWidthMm: 8,
      questionVerticalGapMm: 1,
      sectionGapMm: 3,
      headerHeightMm: 6,
      identityRegionHeightMm: 5,
      minimumContentGapMm: 1.5,
      estimatedLineHeightMm: 3.5,
      estimatedCharactersPerLine: 34,
      estimatedTextWidthMm: 76.5,
      humanReadableFieldHeightMm: 10,
      columnCount: 2,
      columnGapMm: 4.5,
      maximumColumnPromptLines: 3,
      allowedColumnCounts: const [2, 3, 4],
      adaptiveColumns: true,
      preferredColumnCount: 3,
    ),
    LayoutProfile.answerSheet => LayoutConfig(
      profile: LayoutProfile.answerSheet,
      pageSpec: PageSpec.a4Portrait(),
      margins: PageMargins.all(PhysicalLength(12)),
      canonicalPageSpec: CanonicalPageSpec.a4FromWidth(2100),
      markerSizeMm: 14,
      markerInsetMm: 10,
      markerIds: MarkerIds.defaults,
      bubbleDiameterMm: 5,
      bubbleHorizontalGapMm: 2,
      bubbleVerticalGapMm: 2,
      optionCellWidthMm: 5,
      questionVerticalGapMm: 1.25,
      sectionGapMm: 3,
      headerHeightMm: 6,
      identityRegionHeightMm: 5,
      minimumContentGapMm: 1.5,
      estimatedLineHeightMm: 3.5,
      estimatedCharactersPerLine: 34,
      estimatedTextWidthMm: 76.5,
      humanReadableFieldHeightMm: 10,
      columnCount: 3,
      columnGapMm: 4.5,
      maximumColumnPromptLines: 1,
      allowedColumnCounts: const [2, 3, 4],
      adaptiveColumns: true,
      preferredColumnCount: 3,
      answerGroupHeadingHeightMm: 4,
      questionNumberWidthMm: 8,
      bubbleLabelCenterExclusionRatio: 0.5,
    ),
  };

  final LayoutProfile profile;
  final PageSpec pageSpec;
  final PageMargins margins;
  final CanonicalPageSpec canonicalPageSpec;
  final double markerSizeMm;
  final double markerInsetMm;
  final MarkerIds markerIds;
  final double bubbleDiameterMm;
  final double bubbleHorizontalGapMm;
  final double bubbleVerticalGapMm;
  final double optionCellWidthMm;
  final double questionVerticalGapMm;
  final double sectionGapMm;
  final double headerHeightMm;
  final double identityRegionHeightMm;
  final double minimumContentGapMm;
  final double estimatedLineHeightMm;
  final int estimatedCharactersPerLine;
  final double estimatedTextWidthMm;
  final double humanReadableFieldHeightMm;
  final int columnCount;
  final double columnGapMm;
  final int maximumColumnPromptLines;
  final List<int> allowedColumnCounts;
  final bool adaptiveColumns;
  final int preferredColumnCount;
  final LayoutSelectionPolicy selectionPolicy;
  final double answerGroupHeadingHeightMm;
  final double questionNumberWidthMm;
  final double bubbleLabelCenterExclusionRatio;

  /// Creates one fixed candidate without changing any physical tuning.
  LayoutConfig withFixedColumnCount(int value) => LayoutConfig(
    profile: profile,
    pageSpec: pageSpec,
    margins: margins,
    canonicalPageSpec: canonicalPageSpec,
    markerSizeMm: markerSizeMm,
    markerInsetMm: markerInsetMm,
    markerIds: markerIds,
    bubbleDiameterMm: bubbleDiameterMm,
    bubbleHorizontalGapMm: bubbleHorizontalGapMm,
    bubbleVerticalGapMm: bubbleVerticalGapMm,
    optionCellWidthMm: optionCellWidthMm,
    questionVerticalGapMm: questionVerticalGapMm,
    sectionGapMm: sectionGapMm,
    headerHeightMm: headerHeightMm,
    identityRegionHeightMm: identityRegionHeightMm,
    minimumContentGapMm: minimumContentGapMm,
    estimatedLineHeightMm: estimatedLineHeightMm,
    estimatedCharactersPerLine: estimatedCharactersPerLine,
    estimatedTextWidthMm: estimatedTextWidthMm,
    humanReadableFieldHeightMm: humanReadableFieldHeightMm,
    columnCount: value,
    columnGapMm: columnGapMm,
    maximumColumnPromptLines: maximumColumnPromptLines,
    allowedColumnCounts: List.unmodifiable([value]),
    adaptiveColumns: false,
    preferredColumnCount: preferredColumnCount,
    selectionPolicy: selectionPolicy,
    answerGroupHeadingHeightMm: answerGroupHeadingHeightMm,
    questionNumberWidthMm: questionNumberWidthMm,
    bubbleLabelCenterExclusionRatio: bubbleLabelCenterExclusionRatio,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutConfig &&
          other.profile == profile &&
          other.pageSpec == pageSpec &&
          other.margins == margins &&
          other.canonicalPageSpec == canonicalPageSpec &&
          other.markerSizeMm == markerSizeMm &&
          other.markerInsetMm == markerInsetMm &&
          other.markerIds == markerIds &&
          other.bubbleDiameterMm == bubbleDiameterMm &&
          other.bubbleHorizontalGapMm == bubbleHorizontalGapMm &&
          other.bubbleVerticalGapMm == bubbleVerticalGapMm &&
          other.optionCellWidthMm == optionCellWidthMm &&
          other.questionVerticalGapMm == questionVerticalGapMm &&
          other.sectionGapMm == sectionGapMm &&
          other.headerHeightMm == headerHeightMm &&
          other.identityRegionHeightMm == identityRegionHeightMm &&
          other.minimumContentGapMm == minimumContentGapMm &&
          other.estimatedLineHeightMm == estimatedLineHeightMm &&
          other.estimatedCharactersPerLine == estimatedCharactersPerLine &&
          other.estimatedTextWidthMm == estimatedTextWidthMm &&
          other.humanReadableFieldHeightMm == humanReadableFieldHeightMm &&
          other.columnCount == columnCount &&
          other.columnGapMm == columnGapMm &&
          other.maximumColumnPromptLines == maximumColumnPromptLines &&
          other.allowedColumnCounts.length == allowedColumnCounts.length &&
          _sameInts(other.allowedColumnCounts, allowedColumnCounts) &&
          other.adaptiveColumns == adaptiveColumns &&
          other.preferredColumnCount == preferredColumnCount &&
          other.selectionPolicy == selectionPolicy &&
          other.answerGroupHeadingHeightMm == answerGroupHeadingHeightMm &&
          other.questionNumberWidthMm == questionNumberWidthMm &&
          other.bubbleLabelCenterExclusionRatio ==
              bubbleLabelCenterExclusionRatio;

  @override
  int get hashCode => Object.hashAll([
    profile,
    pageSpec,
    margins,
    canonicalPageSpec,
    markerSizeMm,
    markerInsetMm,
    markerIds,
    bubbleDiameterMm,
    bubbleHorizontalGapMm,
    bubbleVerticalGapMm,
    optionCellWidthMm,
    questionVerticalGapMm,
    sectionGapMm,
    headerHeightMm,
    identityRegionHeightMm,
    minimumContentGapMm,
    estimatedLineHeightMm,
    estimatedCharactersPerLine,
    estimatedTextWidthMm,
    humanReadableFieldHeightMm,
    columnCount,
    columnGapMm,
    maximumColumnPromptLines,
    Object.hashAll(allowedColumnCounts),
    adaptiveColumns,
    preferredColumnCount,
    selectionPolicy,
    answerGroupHeadingHeightMm,
    questionNumberWidthMm,
    bubbleLabelCenterExclusionRatio,
  ]);
}

bool _sameInts(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
