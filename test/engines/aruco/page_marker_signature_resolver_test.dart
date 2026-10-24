import 'package:capstone_development/engines/aruco/domain/page_marker_signature_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout/layout_test_fixtures.dart';

void main() {
  final pages = buildLayout(longTemplate(30)).pages;
  final resolver = PageMarkerSignatureResolver.fromPages(pages);

  test('resolves exact page signatures without detector-order dependence', () {
    final first = resolver.resolve([13, 10, 12, 11]);
    final secondIds = pages[1].markerRegions
        .map((marker) => marker.markerId)
        .toList();
    final second = resolver.resolve(secondIds.reversed);

    expect(first.value.pageId, pages[0].pageId);
    expect(second.value.pageId, pages[1].pageId);
  });

  test('ignores reserved packet identity markers during page resolution', () {
    final result = resolver.resolve([13, 2, 10, 2, 12, 7, 11, 6]);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(result.value.pageId, pages.first.pageId);
  });

  test('rejects incomplete, mixed, unknown, and duplicate marker sets', () {
    expect(
      resolver.resolve([10, 11, 12]).error.code,
      'SCAN_PAGE_MARKERS_INCOMPLETE',
    );
    expect(
      resolver.resolve([10, 11, 16, 17]).error.code,
      'SCAN_UNKNOWN_PAGE_MARKERS',
    );
    expect(
      resolver.resolve([30, 31, 32, 33]).error.code,
      'SCAN_UNKNOWN_PAGE_MARKERS',
    );
    expect(
      resolver.resolve([10, 11, 12, 12]).error.code,
      'SCAN_DUPLICATE_PAGE_MARKERS',
    );
  });

  test('layout pages have collision-free signatures', () {
    final allIds = pages
        .expand((page) => page.markerRegions)
        .map((marker) => marker.markerId)
        .toList();

    expect(allIds.toSet(), hasLength(allIds.length));
  });
}
