import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/layout/application/layout_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_test_fixtures.dart';

void main() {
  test('long templates paginate deterministically', () {
    final template = longTemplate(30);

    final first = buildLayout(template);
    final second = buildLayout(template);

    expect(first.pages.length, greaterThan(1));
    expect(first, second);
  });

  test('overflowing questions move to a next page without clipping', () {
    final template = longTemplate(30);
    final document = buildLayout(template);

    expect(document.pages.length, greaterThan(1));
    for (final page in document.pages) {
      for (final question in page.questionRegions) {
        expect(
          question.physicalBounds.bottom.millimeters,
          lessThanOrEqualTo(page.safeBounds.bottom.millimeters),
        );
      }
    }
    expect(
      document.pages
          .expand((page) => page.questionRegions)
          .map((question) => question.questionId),
      [for (var index = 0; index < 30; index++) QuestionId('q$index')],
    );
  });

  test('a question too large for a fresh page returns structured failure', () {
    final hugePrompt = List.filled(5000, 'x').join();
    final result = LayoutEngine().build(
      templateWithQuestions([choiceQuestion('huge', prompt: hugePrompt)]),
      testConfig(),
    );

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'QUESTION_TOO_LARGE');
  });

  test('multi-page indices are stable and zero based', () {
    final pages = buildLayout(longTemplate(30)).pages;

    expect(pages.map((page) => page.pageIndex), [
      for (var index = 0; index < pages.length; index++) index,
    ]);
  });

  test('multi-page IDs are stable and one based in their suffix', () {
    final pages = buildLayout(longTemplate(30)).pages;

    expect(pages.map((page) => page.pageId.value), [
      for (var index = 0; index < pages.length; index++)
        'survey-v1-p${index + 1}',
    ]);
  });

  test('every page reports the final total page count', () {
    final pages = buildLayout(longTemplate(30)).pages;

    expect(pages.map((page) => page.totalPageCount).toSet(), {pages.length});
  });

  test('page-specific IDs change without changing marker geometry', () {
    final pages = buildLayout(longTemplate(30)).pages;
    expect(pages.length, greaterThan(1));
    expect(pages[0].markerRegions.map((marker) => marker.markerId), [
      10,
      11,
      12,
      13,
    ]);
    expect(pages[1].markerRegions.map((marker) => marker.markerId), [
      14,
      15,
      16,
      17,
    ]);
    for (var index = 0; index < 4; index++) {
      expect(
        pages[1].markerRegions[index].physicalBounds,
        pages[0].markerRegions[index].physicalBounds,
      );
      expect(
        pages[1].markerRegions[index].role,
        pages[0].markerRegions[index].role,
      );
    }
  });

  test('layout fails explicitly when pagination exceeds marker capacity', () {
    final result = LayoutEngine().build(longTemplate(120), testConfig());

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'ARUCO_PAGE_ID_CAPACITY_EXCEEDED');
    expect(result.error.details['maximumPageCount'], 10);
  });
}
