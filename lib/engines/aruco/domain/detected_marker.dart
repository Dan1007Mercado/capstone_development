import 'dart:collection';

import 'image_geometry.dart';

/// Stable marker-local corner order normalized at the backend boundary.
enum MarkerCorner { topLeft, topRight, bottomRight, bottomLeft }

/// One detected marker in source-image pixel space.
final class DetectedMarker {
  DetectedMarker({
    required this.id,
    required ImagePoint topLeft,
    required ImagePoint topRight,
    required ImagePoint bottomRight,
    required ImagePoint bottomLeft,
    this.confidence,
  }) : corners = UnmodifiableListView([
         topLeft,
         topRight,
         bottomRight,
         bottomLeft,
       ]) {
    if (id < 0) throw ArgumentError.value(id, 'id', 'Must be non-negative.');
    if (confidence != null &&
        (!confidence!.isFinite || confidence! < 0 || confidence! > 1)) {
      throw ArgumentError.value(confidence, 'confidence');
    }
  }

  final int id;
  final List<ImagePoint> corners;
  final double? confidence;

  ImagePoint corner(MarkerCorner corner) => corners[corner.index];

  ImagePoint get center => ImagePoint(
    corners.fold<double>(0, (sum, point) => sum + point.x) / corners.length,
    corners.fold<double>(0, (sum, point) => sum + point.y) / corners.length,
  );

  List<double> get sideLengths => UnmodifiableListView([
    corners[0].distanceTo(corners[1]),
    corners[1].distanceTo(corners[2]),
    corners[2].distanceTo(corners[3]),
    corners[3].distanceTo(corners[0]),
  ]);

  double get minimumSideLength =>
      sideLengths.reduce((first, second) => first < second ? first : second);
}

final class ArucoDetection {
  ArucoDetection({
    required this.sourceSize,
    required Iterable<DetectedMarker> markers,
  }) : markers = UnmodifiableListView(List.of(markers));

  final ImageSize sourceSize;
  final List<DetectedMarker> markers;
}
