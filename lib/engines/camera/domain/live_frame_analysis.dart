import 'dart:collection';

import '../../aruco/domain/image_geometry.dart';

final class DocumentGeometry {
  DocumentGeometry({
    required Iterable<ImagePoint> corners,
    required this.areaRatio,
    required this.centroid,
    required this.perspectiveRatio,
  }) : corners = UnmodifiableListView(List.of(corners)) {
    if (this.corners.length != 4) {
      throw ArgumentError.value(corners, 'corners', 'Four corners required.');
    }
  }

  /// Canonical order: top-left, top-right, bottom-right, bottom-left.
  final List<ImagePoint> corners;
  final double areaRatio;
  final ImagePoint centroid;
  final double perspectiveRatio;
}

final class DetectedDocument {
  const DetectedDocument({required this.geometry, required this.confidence});

  final DocumentGeometry geometry;
  final double confidence;
}

enum DocumentTrackingPhase { searching, acquired, tracking, temporarilyLost }

final class DocumentTrackingUpdate {
  const DocumentTrackingUpdate({
    required this.phase,
    required this.document,
    required this.isFresh,
    required this.temporaryMissCount,
  });

  const DocumentTrackingUpdate.searching()
    : phase = DocumentTrackingPhase.searching,
      document = null,
      isFresh = false,
      temporaryMissCount = 0;

  final DocumentTrackingPhase phase;
  final DetectedDocument? document;
  final bool isFresh;
  final int temporaryMissCount;
}
