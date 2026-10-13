import 'package:capstone_development/core/geometry/geometry_converter.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/layout/domain/layout_regions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_test_fixtures.dart';

void main() {
  test('same template and configuration produce equal documents', () {
    final template = fullTemplate();
    final config = testConfig();

    final first = buildLayout(template, config: config);
    final second = buildLayout(template, config: config);

    expect(first, second);
    expect(first.hashCode, second.hashCode);
  });

  test('page IDs are deterministic', () {
    final first = buildLayout(fullTemplate());
    final second = buildLayout(fullTemplate());

    expect(
      first.pages.map((page) => page.pageId),
      second.pages.map((page) => page.pageId),
    );
    expect(first.pages.first.pageId.value, 'survey-v1-p1');
  });

  test('default marker IDs are stable and unique', () {
    expect(MarkerIds.defaults.values, [10, 11, 12, 13]);
    expect(MarkerIds.defaults.areUnique, isTrue);
  });

  test('every page contains all four semantic marker roles', () {
    final page = buildLayout(fullTemplate()).pages.first;

    expect(page.markerRegions, hasLength(4));
    expect(page.markerRegions.map((marker) => marker.role), [
      MarkerRole.topLeft,
      MarkerRole.topRight,
      MarkerRole.bottomLeft,
      MarkerRole.bottomRight,
    ]);
  });

  test('marker IDs map to the expected roles', () {
    final markers = buildLayout(fullTemplate()).pages.first.markerRegions;

    expect(markers.map((marker) => marker.markerId), [10, 11, 12, 13]);
  });

  test('marker registration uses each page-facing inner corner', () {
    final markers = buildLayout(fullTemplate()).pages.first.markerRegions;

    for (final marker in markers) {
      final bounds = marker.physicalMarkerBounds;
      final point = marker.physicalRegistrationPoint;
      switch (marker.role) {
        case MarkerRole.topLeft:
          expect(point.x, bounds.right);
          expect(point.y, bounds.bottom);
        case MarkerRole.topRight:
          expect(point.x, bounds.left);
          expect(point.y, bounds.bottom);
        case MarkerRole.bottomLeft:
          expect(point.x, bounds.right);
          expect(point.y, bounds.top);
        case MarkerRole.bottomRight:
          expect(point.x, bounds.left);
          expect(point.y, bounds.top);
      }
    }
  });

  test('detectable marker bounds exclude one quiet-zone module per edge', () {
    final markers = buildLayout(fullTemplate()).pages.first.markerRegions;

    for (final marker in markers) {
      final outer = marker.physicalBounds;
      final inner = marker.physicalMarkerBounds;
      final expectedInset =
          outer.width.millimeters / ArucoMarkerPrintContract.totalModules;

      expect(outer.containsRect(inner), isTrue);
      expect(inner.left.millimeters - outer.left.millimeters, expectedInset);
      expect(inner.top.millimeters - outer.top.millimeters, expectedInset);
      expect(outer.right.millimeters - inner.right.millimeters, expectedInset);
      expect(
        outer.bottom.millimeters - inner.bottom.millimeters,
        expectedInset,
      );
      expect(
        inner.width.millimeters,
        outer.width.millimeters *
            ArucoMarkerPrintContract.markerModules /
            ArucoMarkerPrintContract.totalModules,
      );
    }
  });

  test('marker normalized geometry is converted from physical geometry', () {
    final page = buildLayout(fullTemplate()).pages.first;

    for (final marker in page.markerRegions) {
      expect(
        marker.normalizedBounds,
        GeometryConverter.physicalRectToNormalized(
          marker.physicalBounds,
          page.pageSpec.size,
        ),
      );
      expect(
        marker.normalizedMarkerBounds,
        GeometryConverter.physicalRectToNormalized(
          marker.physicalMarkerBounds,
          page.pageSpec.size,
        ),
      );
      expect(
        marker.normalizedRegistrationPoint,
        GeometryConverter.physicalPointToNormalized(
          marker.physicalRegistrationPoint,
          page.pageSpec.size,
        ),
      );
    }
  });

  test('printable bounds remain inside the physical page', () {
    final page = buildLayout(fullTemplate()).pages.first;

    expect(page.physicalPageBounds.containsRect(page.printableBounds), isTrue);
  });

  test('safe bounds remain inside printable bounds', () {
    final page = buildLayout(fullTemplate()).pages.first;

    expect(page.printableBounds.containsRect(page.safeBounds), isTrue);
  });

  test('identity region avoids all marker regions', () {
    final page = buildLayout(fullTemplate()).pages.first;

    for (final marker in page.markerRegions) {
      expect(
        page.templateIdentityRegion.physicalBounds.intersects(
          marker.physicalBounds,
        ),
        isFalse,
      );
    }
  });

  test('all normalized rectangles remain within page space', () {
    final document = buildLayout(fullTemplate());

    for (final page in document.pages) {
      final rectangles = [
        page.normalizedPageBounds,
        page.normalizedPrintableBounds,
        page.normalizedSafeBounds,
        page.templateIdentityRegion.normalizedBounds,
        ...page.markerRegions.map((marker) => marker.normalizedBounds),
        ...page.markerRegions.map((marker) => marker.normalizedMarkerBounds),
        ...page.questionRegions.map((question) => question.normalizedBounds),
        ...page.bubbleRegions.map((bubble) => bubble.normalizedBounds),
      ];
      for (final rect in rectangles) {
        expect(rect.left.value, inInclusiveRange(0, 1));
        expect(rect.top.value, inInclusiveRange(0, 1));
        expect(rect.right.value, inInclusiveRange(0, 1));
        expect(rect.bottom.value, inInclusiveRange(0, 1));
      }
    }
  });

  test(
    'scanner geometry uses centralized physical-to-normalized conversion',
    () {
      final page = buildLayout(fullTemplate()).pages.first;
      final bubble = page.bubbleRegions.first;

      expect(
        bubble.normalizedBounds,
        GeometryConverter.physicalRectToNormalized(
          bubble.physicalBounds,
          page.pageSpec.size,
        ),
      );
      expect(
        bubble.normalizedCenter,
        GeometryConverter.physicalPointToNormalized(
          bubble.physicalCenter,
          page.pageSpec.size,
        ),
      );
    },
  );

  test('layout collections are immutable', () {
    final document = buildLayout(fullTemplate());
    final page = document.pages.first;

    expect(() => document.pages.clear(), throwsUnsupportedError);
    expect(() => page.markerRegions.clear(), throwsUnsupportedError);
    expect(() => page.sectionRegions.clear(), throwsUnsupportedError);
    expect(() => page.questionRegions.clear(), throwsUnsupportedError);
    expect(() => page.bubbleRegions.clear(), throwsUnsupportedError);
  });
}
