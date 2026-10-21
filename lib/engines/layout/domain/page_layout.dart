import 'dart:collection';

import '../../../core/geometry/normalized_geometry.dart';
import '../../../core/geometry/page_spec.dart';
import '../../../core/geometry/physical_geometry.dart';
import '../../../core/ids/identifiers.dart';
import 'layout_regions.dart';
import 'layout_selection.dart';
import 'layout_value_equality.dart';

/// Authoritative geometry for one printable/scannable page.
final class PageLayout {
  PageLayout({
    required this.templateId,
    required this.templateVersion,
    required this.pageId,
    required this.pageIndex,
    required this.totalPageCount,
    required this.pageSpec,
    required this.canonicalPageSpec,
    required this.physicalPageBounds,
    required this.normalizedPageBounds,
    required this.printableBounds,
    required this.normalizedPrintableBounds,
    required this.safeBounds,
    required this.normalizedSafeBounds,
    required Iterable<MarkerRegion> markerRegions,
    required this.templateIdentityRegion,
    required this.headerRegion,
    required Iterable<LayoutColumnRegion> contentColumnRegions,
    required Iterable<SectionRegion> sectionRegions,
    required Iterable<QuestionRegion> questionRegions,
    required Iterable<BubbleRegion> bubbleRegions,
  }) : markerRegions = UnmodifiableListView(List.of(markerRegions)),
       contentColumnRegions = UnmodifiableListView(
         List.of(contentColumnRegions),
       ),
       sectionRegions = UnmodifiableListView(List.of(sectionRegions)),
       questionRegions = UnmodifiableListView(List.of(questionRegions)),
       bubbleRegions = UnmodifiableListView(List.of(bubbleRegions));

  final TemplateId templateId;
  final TemplateVersion templateVersion;
  final PageId pageId;

  /// Zero-based stable page index.
  final int pageIndex;
  final int totalPageCount;
  final PageSpec pageSpec;
  final CanonicalPageSpec canonicalPageSpec;
  final PhysicalRect physicalPageBounds;
  final NormalizedRect normalizedPageBounds;
  final PhysicalRect printableBounds;
  final NormalizedRect normalizedPrintableBounds;
  final PhysicalRect safeBounds;
  final NormalizedRect normalizedSafeBounds;
  final List<MarkerRegion> markerRegions;
  final TemplateIdentityRegion templateIdentityRegion;
  final ContentRegion headerRegion;
  final List<LayoutColumnRegion> contentColumnRegions;
  final List<SectionRegion> sectionRegions;
  final List<QuestionRegion> questionRegions;
  final List<BubbleRegion> bubbleRegions;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PageLayout &&
          other.templateId == templateId &&
          other.templateVersion == templateVersion &&
          other.pageId == pageId &&
          other.pageIndex == pageIndex &&
          other.totalPageCount == totalPageCount &&
          other.pageSpec == pageSpec &&
          other.canonicalPageSpec == canonicalPageSpec &&
          other.physicalPageBounds == physicalPageBounds &&
          other.normalizedPageBounds == normalizedPageBounds &&
          other.printableBounds == printableBounds &&
          other.normalizedPrintableBounds == normalizedPrintableBounds &&
          other.safeBounds == safeBounds &&
          other.normalizedSafeBounds == normalizedSafeBounds &&
          layoutListEquals(other.markerRegions, markerRegions) &&
          other.templateIdentityRegion == templateIdentityRegion &&
          other.headerRegion == headerRegion &&
          layoutListEquals(other.contentColumnRegions, contentColumnRegions) &&
          layoutListEquals(other.sectionRegions, sectionRegions) &&
          layoutListEquals(other.questionRegions, questionRegions) &&
          layoutListEquals(other.bubbleRegions, bubbleRegions);

  @override
  int get hashCode => Object.hashAll([
    templateId,
    templateVersion,
    pageId,
    pageIndex,
    totalPageCount,
    pageSpec,
    canonicalPageSpec,
    physicalPageBounds,
    normalizedPageBounds,
    printableBounds,
    normalizedPrintableBounds,
    safeBounds,
    normalizedSafeBounds,
    Object.hashAll(markerRegions),
    templateIdentityRegion,
    headerRegion,
    Object.hashAll(contentColumnRegions),
    Object.hashAll(sectionRegions),
    Object.hashAll(questionRegions),
    Object.hashAll(bubbleRegions),
  ]);
}

final class LayoutDocument {
  LayoutDocument({
    required this.templateId,
    required this.templateVersion,
    required Iterable<PageLayout> pages,
    this.selectionDiagnostics,
  }) : pages = UnmodifiableListView(List.of(pages));

  final TemplateId templateId;
  final TemplateVersion templateVersion;
  final List<PageLayout> pages;
  final LayoutSelectionDiagnostics? selectionDiagnostics;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutDocument &&
          other.templateId == templateId &&
          other.templateVersion == templateVersion &&
          other.selectionDiagnostics == selectionDiagnostics &&
          layoutListEquals(other.pages, pages);

  @override
  int get hashCode => Object.hash(
    templateId,
    templateVersion,
    Object.hashAll(pages),
    selectionDiagnostics,
  );
}
