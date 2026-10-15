import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import 'layout_config.dart';

/// Allocates one deterministic four-marker signature per physical page.
final class PageMarkerIdAllocator {
  const PageMarkerIdAllocator({this.maximumMarkerId = 49});

  final int maximumMarkerId;

  static const markersPerPage = 4;

  int maximumPageCount(MarkerIds firstPage) {
    final highestBase = firstPage.values.reduce((a, b) => a > b ? a : b);
    if (highestBase > maximumMarkerId) return 0;
    return ((maximumMarkerId - highestBase) ~/ markersPerPage) + 1;
  }

  EngineResult<MarkerIds> allocate(MarkerIds firstPage, int pageIndex) {
    if (pageIndex < 0) {
      throw RangeError.value(pageIndex, 'pageIndex', 'Must be non-negative.');
    }
    final offset = pageIndex * markersPerPage;
    final allocated = MarkerIds(
      topLeft: firstPage.topLeft + offset,
      topRight: firstPage.topRight + offset,
      bottomLeft: firstPage.bottomLeft + offset,
      bottomRight: firstPage.bottomRight + offset,
    );
    if (allocated.values.any((id) => id > maximumMarkerId)) {
      return EngineResult.failure(
        EngineError(
          code: 'ARUCO_PAGE_ID_CAPACITY_EXCEEDED',
          message:
              'The layout requires more page markers than DICT_4X4_50 provides.',
          details: {
            'pageIndex': pageIndex,
            'maximumMarkerId': maximumMarkerId,
            'maximumPageCount': maximumPageCount(firstPage),
          },
        ),
      );
    }
    return EngineResult.success(allocated);
  }
}
