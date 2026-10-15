import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/layout/domain/page_marker_id_allocator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const allocator = PageMarkerIdAllocator();
  const firstPage = MarkerIds(
    topLeft: 10,
    topRight: 11,
    bottomLeft: 12,
    bottomRight: 13,
  );

  test('allocates deterministic role-preserving marker IDs per page', () {
    expect(allocator.allocate(firstPage, 0).value.values, [10, 11, 12, 13]);
    expect(allocator.allocate(firstPage, 1).value.values, [14, 15, 16, 17]);
    expect(allocator.allocate(firstPage, 9).value.values, [46, 47, 48, 49]);
  });

  test('exposes DICT_4X4_50 capacity and never wraps IDs', () {
    expect(allocator.maximumPageCount(firstPage), 10);
    final result = allocator.allocate(firstPage, 10);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'ARUCO_PAGE_ID_CAPACITY_EXCEEDED');
    expect(result.error.details['maximumPageCount'], 10);
  });
}
