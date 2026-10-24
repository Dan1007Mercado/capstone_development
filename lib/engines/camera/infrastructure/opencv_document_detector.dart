import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../aruco/domain/image_geometry.dart';
import '../domain/live_frame_analysis.dart';

final class OpenCvDocumentDetector {
  const OpenCvDocumentDetector();

  DetectedDocument? detect({
    required Uint8List pixels,
    required int width,
    required int height,
    required double cannyLowThreshold,
    required double cannyHighThreshold,
    required double polygonEpsilonRatio,
  }) {
    if (pixels.length != width * height || width <= 0 || height <= 0) {
      throw ArgumentError('Document pixels must match positive dimensions.');
    }
    cv.Mat? gray;
    cv.Mat? blurred;
    cv.Mat? edges;
    cv.Contours? contours;
    cv.Mat? hierarchy;
    try {
      gray = cv.Mat.fromList(height, width, cv.MatType.CV_8UC1, pixels);
      blurred = cv.gaussianBlur(gray, (5, 5), 0);
      edges = cv.canny(blurred, cannyLowThreshold, cannyHighThreshold);
      final found = cv.findContours(
        edges,
        cv.RETR_EXTERNAL,
        cv.CHAIN_APPROX_SIMPLE,
      );
      contours = found.$1;
      hierarchy = found.$2;

      List<ImagePoint>? best;
      var bestArea = 0.0;
      for (var index = 0; index < contours.length; index++) {
        final contour = contours[index];
        cv.VecPoint? polygon;
        try {
          final perimeter = cv.arcLength(contour, true);
          polygon = cv.approxPolyDP(
            contour,
            polygonEpsilonRatio * perimeter,
            true,
          );
          if (polygon.length != 4) continue;
          final points = [
            for (final point in polygon.toList())
              ImagePoint(point.x.toDouble(), point.y.toDouble()),
          ];
          if (!_isConvex(points)) continue;
          final area = _polygonArea(points).abs();
          if (area > bestArea) {
            bestArea = area;
            best = points;
          }
        } finally {
          polygon?.dispose();
        }
      }
      if (best == null) return null;
      final ordered = orderDocumentCorners(best);
      final areaRatio = bestArea / (width * height);
      final sides = [
        for (var index = 0; index < 4; index++)
          ordered[index].distanceTo(ordered[(index + 1) % 4]),
      ];
      final minimumSide = sides.reduce(math.min);
      if (minimumSide <= 0) return null;
      final perspective = sides.reduce(math.max) / minimumSide;
      final centroid = ImagePoint(
        ordered.fold<double>(0, (sum, point) => sum + point.x) / 4,
        ordered.fold<double>(0, (sum, point) => sum + point.y) / 4,
      );
      final rectangularity =
          (bestArea / (_boundingWidth(ordered) * _boundingHeight(ordered)))
              .clamp(0.0, 1.0);
      return DetectedDocument(
        geometry: DocumentGeometry(
          corners: ordered,
          areaRatio: areaRatio,
          centroid: centroid,
          perspectiveRatio: perspective,
        ),
        confidence: (areaRatio * rectangularity).clamp(0.0, 1.0),
      );
    } finally {
      hierarchy?.dispose();
      contours?.dispose();
      edges?.dispose();
      blurred?.dispose();
      gray?.dispose();
    }
  }
}

List<ImagePoint> orderDocumentCorners(Iterable<ImagePoint> source) {
  final points = List<ImagePoint>.of(source);
  if (points.length != 4) {
    throw ArgumentError.value(source, 'source', 'Four corners required.');
  }
  final topLeft = points.reduce(
    (left, right) => left.x + left.y <= right.x + right.y ? left : right,
  );
  final bottomRight = points.reduce(
    (left, right) => left.x + left.y >= right.x + right.y ? left : right,
  );
  final topRight = points.reduce(
    (left, right) => left.x - left.y >= right.x - right.y ? left : right,
  );
  final bottomLeft = points.reduce(
    (left, right) => left.x - left.y <= right.x - right.y ? left : right,
  );
  final ordered = [topLeft, topRight, bottomRight, bottomLeft];
  if (ordered.toSet().length != 4) {
    throw StateError('Document corners cannot be ordered uniquely.');
  }
  return ordered;
}

bool _isConvex(List<ImagePoint> points) {
  double? sign;
  for (var index = 0; index < points.length; index++) {
    final a = points[index];
    final b = points[(index + 1) % points.length];
    final c = points[(index + 2) % points.length];
    final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
    if (cross.abs() < 0.000001) return false;
    sign ??= cross.sign;
    if (cross.sign != sign) return false;
  }
  return true;
}

double _polygonArea(List<ImagePoint> points) {
  var twiceArea = 0.0;
  for (var index = 0; index < points.length; index++) {
    final next = points[(index + 1) % points.length];
    twiceArea += points[index].x * next.y - next.x * points[index].y;
  }
  return twiceArea / 2;
}

double _boundingWidth(List<ImagePoint> points) =>
    points.map((point) => point.x).reduce(math.max) -
    points.map((point) => point.x).reduce(math.min);

double _boundingHeight(List<ImagePoint> points) =>
    points.map((point) => point.y).reduce(math.max) -
    points.map((point) => point.y).reduce(math.min);
