import '../../../core/geometry/page_spec.dart';
import '../../../core/geometry/physical_geometry.dart';

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
    required this.humanReadableFieldHeightMm,
  });

  factory LayoutConfig.a4Default() => LayoutConfig(
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
    humanReadableFieldHeightMm: 12,
  );

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
  final double humanReadableFieldHeightMm;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutConfig &&
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
          other.humanReadableFieldHeightMm == humanReadableFieldHeightMm;

  @override
  int get hashCode => Object.hashAll([
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
    humanReadableFieldHeightMm,
  ]);
}
