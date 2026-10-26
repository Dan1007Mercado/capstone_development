import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../aruco/domain/image_geometry.dart';
import '../domain/live_frame_analysis.dart';

abstract interface class DocumentDetector {
  DetectedDocument? detect({
    required Uint8List pixels,
    required int width,
    required int height,
    required double cannyLowThreshold,
    required double cannyHighThreshold,
    required double polygonEpsilonRatio,
  });
}

final class DocumentDetectionAttempt {
  const DocumentDetectionAttempt({this.document, this.error});

  final DetectedDocument? document;
  final String? error;

  bool get failed => error != null;
}

DocumentDetectionAttempt detectDocumentBestEffort({
  required DocumentDetector detector,
  required Uint8List pixels,
  required int width,
  required int height,
  required double cannyLowThreshold,
  required double cannyHighThreshold,
  required double polygonEpsilonRatio,
}) {
  try {
    return DocumentDetectionAttempt(
      document: detector.detect(
        pixels: pixels,
        width: width,
        height: height,
        cannyLowThreshold: cannyLowThreshold,
        cannyHighThreshold: cannyHighThreshold,
        polygonEpsilonRatio: polygonEpsilonRatio,
      ),
    );
  } on Object catch (error) {
    return DocumentDetectionAttempt(error: _shortDiagnostic(error));
  }
}

final class OpenCvDocumentDetector implements DocumentDetector {
  const OpenCvDocumentDetector();

  static const double _minimumCandidateAreaRatio = 0.01;
  static const double _minimumRectangularity = 0.2;
  static const double _maximumCandidatePerspectiveRatio = 12;
  static const double _minimumSidePixels = 8;

  @override
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
      final minimumArea = width * height * _minimumCandidateAreaRatio;
      for (var index = 0; index < contours.length; index++) {
        final contour = contours[index];
        cv.VecPoint? polygon;
        try {
          final perimeter = cv.arcLength(contour, true);
          if (!perimeter.isFinite || perimeter <= 0) continue;
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
          if (points.any((point) => !point.x.isFinite || !point.y.isFinite)) {
            continue;
          }
          final ordered = tryOrderDocumentCorners(points);
          if (ordered == null || !_isConvex(ordered)) continue;
          final area = _polygonArea(ordered).abs();
          final boundingWidth = _boundingWidth(ordered);
          final boundingHeight = _boundingHeight(ordered);
          if (!area.isFinite ||
              area < minimumArea ||
              !boundingWidth.isFinite ||
              !boundingHeight.isFinite ||
              boundingWidth < _minimumSidePixels ||
              boundingHeight < _minimumSidePixels) {
            continue;
          }
          final sides = [
            for (var side = 0; side < 4; side++)
              ordered[side].distanceTo(ordered[(side + 1) % 4]),
          ];
          final minimumSide = sides.reduce(math.min);
          final maximumSide = sides.reduce(math.max);
          final perspective = maximumSide / minimumSide;
          final rectangularity = area / (boundingWidth * boundingHeight);
          if (minimumSide < _minimumSidePixels ||
              !perspective.isFinite ||
              perspective > _maximumCandidatePerspectiveRatio ||
              !rectangularity.isFinite ||
              rectangularity < _minimumRectangularity) {
            continue;
          }
          if (area > bestArea) {
            bestArea = area;
            best = ordered;
          }
        } on Object {
          // A malformed/noisy contour is expected input, not a frame failure.
          continue;
        } finally {
          polygon?.dispose();
        }
      }
      if (best == null) return null;
      final ordered = best;
      final areaRatio = bestArea / (width * height);
      final sides = [
        for (var index = 0; index < 4; index++)
          ordered[index].distanceTo(ordered[(index + 1) % 4]),
      ];
      final minimumSide = sides.reduce(math.min);
      if (!minimumSide.isFinite || minimumSide <= 0) return null;
      final perspective = sides.reduce(math.max) / minimumSide;
      final centroid = ImagePoint(
        ordered.fold<double>(0, (sum, point) => sum + point.x) / 4,
        ordered.fold<double>(0, (sum, point) => sum + point.y) / 4,
      );
      if (!centroid.x.isFinite ||
          !centroid.y.isFinite ||
          !perspective.isFinite) {
        return null;
      }
      final boundingArea = _boundingWidth(ordered) * _boundingHeight(ordered);
      if (!boundingArea.isFinite || boundingArea <= 0) return null;
      final rectangularity = (bestArea / boundingArea).clamp(0.0, 1.0);
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
  final ordered = tryOrderDocumentCorners(source);
  if (ordered != null) return ordered;
  final points = List<ImagePoint>.of(source);
  if (points.length != 4) {
    throw ArgumentError.value(source, 'source', 'Four corners required.');
  }
  throw StateError('Document corners cannot be ordered uniquely.');
}

List<ImagePoint>? tryOrderDocumentCorners(Iterable<ImagePoint> source) {
  final points = List<ImagePoint>.of(source);
  if (points.length != 4 ||
      points.toSet().length != 4 ||
      points.any((point) => !point.x.isFinite || !point.y.isFinite)) {
    return null;
  }
  final centroid = ImagePoint(
    points.fold<double>(0, (sum, point) => sum + point.x) / 4,
    points.fold<double>(0, (sum, point) => sum + point.y) / 4,
  );
  if (!centroid.x.isFinite || !centroid.y.isFinite) return null;
  points.sort(
    (left, right) => math
        .atan2(left.y - centroid.y, left.x - centroid.x)
        .compareTo(math.atan2(right.y - centroid.y, right.x - centroid.x)),
  );
  var topLeftIndex = 0;
  var minimumSum = double.infinity;
  for (var index = 0; index < points.length; index++) {
    final sum = points[index].x + points[index].y;
    if (sum < minimumSum) {
      minimumSum = sum;
      topLeftIndex = index;
    }
  }
  final ordered = [
    for (var offset = 0; offset < 4; offset++)
      points[(topLeftIndex + offset) % 4],
  ];
  if (_polygonArea(ordered) < 0) {
    return [ordered[0], ordered[3], ordered[2], ordered[1]];
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

String _shortDiagnostic(Object error) {
  final normalized = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  const maximumLength = 180;
  return normalized.length <= maximumLength
      ? normalized
      : '${normalized.substring(0, maximumLength - 1)}…';
}
