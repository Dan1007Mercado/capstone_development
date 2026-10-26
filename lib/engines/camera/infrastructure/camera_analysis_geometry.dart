import 'dart:math' as math;
import 'dart:typed_data';

import '../../aruco/application/marker_correspondence_service.dart';
import '../../aruco/domain/detected_marker.dart';
import '../../aruco/domain/image_geometry.dart';
import '../../layout/domain/layout_regions.dart';

final class PreparedCameraAnalysisImage {
  const PreparedCameraAnalysisImage({
    required this.pixels,
    required this.sourceSize,
    required this.analysisSize,
    required this.analysisScaleX,
    required this.analysisScaleY,
    required this.brightness,
  });

  final Uint8List pixels;
  final ImageSize sourceSize;
  final ImageSize analysisSize;

  /// Analysis pixels per source pixel. Values never exceed one.
  final double analysisScaleX;
  final double analysisScaleY;
  final double brightness;
}

PreparedCameraAnalysisImage prepareCameraAnalysisImage({
  required Uint8List source,
  required int width,
  required int height,
  required int bytesPerRow,
  required int bytesPerPixel,
  required int maximumDimension,
}) {
  if (width <= 0 ||
      height <= 0 ||
      bytesPerRow <= 0 ||
      bytesPerPixel <= 0 ||
      maximumDimension <= 0) {
    throw ArgumentError('Camera analysis dimensions must be positive.');
  }
  final requiredLength =
      (height - 1) * bytesPerRow + (width - 1) * bytesPerPixel + 1;
  if (source.length < requiredLength) {
    throw ArgumentError('Camera luma buffer is shorter than its strides.');
  }

  final longestEdge = math.max(width, height);
  final scale = longestEdge <= maximumDimension
      ? 1.0
      : maximumDimension / longestEdge;
  final analysisWidth = math.max(1, (width * scale).round());
  final analysisHeight = math.max(1, (height * scale).round());
  final isUnscaled = analysisWidth == width && analysisHeight == height;
  final isCompact = bytesPerPixel == 1 && bytesPerRow == width;

  late final Uint8List pixels;
  var sum = 0;
  if (isUnscaled && isCompact) {
    pixels = Uint8List.sublistView(source, 0, width * height);
    for (final value in pixels) {
      sum += value;
    }
  } else {
    pixels = Uint8List(analysisWidth * analysisHeight);
    for (var y = 0; y < analysisHeight; y++) {
      final sourceY = math.min(height - 1, y * height ~/ analysisHeight);
      final sourceRow = sourceY * bytesPerRow;
      final destinationRow = y * analysisWidth;
      for (var x = 0; x < analysisWidth; x++) {
        final sourceX = math.min(width - 1, x * width ~/ analysisWidth);
        final value = source[sourceRow + sourceX * bytesPerPixel];
        pixels[destinationRow + x] = value;
        sum += value;
      }
    }
  }

  return PreparedCameraAnalysisImage(
    pixels: pixels,
    sourceSize: ImageSize(width: width, height: height),
    analysisSize: ImageSize(width: analysisWidth, height: analysisHeight),
    analysisScaleX: analysisWidth / width,
    analysisScaleY: analysisHeight / height,
    brightness: sum / pixels.length,
  );
}

ArucoDetection remapArucoDetectionToSource(
  ArucoDetection detection,
  ImageSize sourceSize,
) {
  final scaleX = sourceSize.width / detection.sourceSize.width;
  final scaleY = sourceSize.height / detection.sourceSize.height;
  ImagePoint remap(ImagePoint point) =>
      ImagePoint(point.x * scaleX, point.y * scaleY);

  return ArucoDetection(
    sourceSize: sourceSize,
    markers: [
      for (final marker in detection.markers)
        DetectedMarker(
          id: marker.id,
          topLeft: remap(marker.corner(MarkerCorner.topLeft)),
          topRight: remap(marker.corner(MarkerCorner.topRight)),
          bottomRight: remap(marker.corner(MarkerCorner.bottomRight)),
          bottomLeft: remap(marker.corner(MarkerCorner.bottomLeft)),
          confidence: marker.confidence,
        ),
    ],
  );
}

final class CameraMarkerGeometry {
  CameraMarkerGeometry({
    required this.detectedMarkerIds,
    required this.registrationPoints,
    required this.pageAreaRatio,
    required this.perspectiveRatio,
    required this.minimumMarkerSidePixels,
  });

  final List<int> detectedMarkerIds;
  final List<ImagePoint> registrationPoints;
  final double? pageAreaRatio;
  final double? perspectiveRatio;
  final double? minimumMarkerSidePixels;
}

CameraMarkerGeometry calculateCameraMarkerGeometry({
  required ArucoDetection sourceDetection,
  required List<int> markerIds,
}) {
  if (markerIds.length != 4) {
    throw ArgumentError.value(markerIds, 'markerIds', 'Four IDs required.');
  }
  final markers = sourceDetection.markers;
  final detectedIds = markers.map((marker) => marker.id).toList()..sort();
  final rolesById = <int, MarkerRole>{
    markerIds[0]: MarkerRole.topLeft,
    markerIds[1]: MarkerRole.topRight,
    markerIds[2]: MarkerRole.bottomLeft,
    markerIds[3]: MarkerRole.bottomRight,
  };
  final detectedById = <int, List<DetectedMarker>>{};
  for (final marker in markers) {
    detectedById.putIfAbsent(marker.id, () => []).add(marker);
  }
  const roleOrder = [
    MarkerRole.topLeft,
    MarkerRole.topRight,
    MarkerRole.bottomRight,
    MarkerRole.bottomLeft,
  ];
  final idByRole = {
    for (final entry in rolesById.entries) entry.value: entry.key,
  };
  final requiredMarkers = <DetectedMarker>[];
  final registrationPoints = <ImagePoint>[];
  for (final role in roleOrder) {
    final matches = detectedById[idByRole[role]];
    if (matches == null || matches.length != 1) {
      requiredMarkers.clear();
      registrationPoints.clear();
      break;
    }
    final marker = matches.single;
    requiredMarkers.add(marker);
    registrationPoints.add(
      marker.corner(DetectedRegistrationCorner.forRole(role)),
    );
  }

  double? areaRatio;
  double? perspectiveRatio;
  double? minimumMarkerSide;
  if (registrationPoints.length == 4) {
    final sourceSize = sourceDetection.sourceSize;
    areaRatio =
        _polygonArea(registrationPoints).abs() /
        (sourceSize.width * sourceSize.height);
    perspectiveRatio = registrationPerspectiveRatio(registrationPoints);
    minimumMarkerSide = requiredMarkers
        .map((marker) => marker.minimumSideLength)
        .reduce(math.min);
  }
  return CameraMarkerGeometry(
    detectedMarkerIds: detectedIds,
    registrationPoints: registrationPoints,
    pageAreaRatio: areaRatio,
    perspectiveRatio: perspectiveRatio,
    minimumMarkerSidePixels: minimumMarkerSide,
  );
}

final class AnalysisRegionMetrics {
  const AnalysisRegionMetrics({
    required this.meanIntensity,
    required this.sharpness,
    required this.sampleCount,
  });

  final double meanIntensity;
  final double sharpness;
  final int sampleCount;
}

/// Measures only the registered page interior at a bounded 2x2 sampling rate.
AnalysisRegionMetrics measureAnalysisRegion({
  required Uint8List pixels,
  required int width,
  required int height,
  required List<ImagePoint> polygon,
}) {
  if (pixels.length != width * height || polygon.length != 4) {
    throw ArgumentError('A compact image and four region points are required.');
  }
  if (width < 3 || height < 3) {
    return const AnalysisRegionMetrics(
      meanIntensity: 0,
      sharpness: 0,
      sampleCount: 0,
    );
  }
  final minX = math.max(
    1,
    polygon.map((point) => point.x).reduce(math.min).floor(),
  );
  final maxX = math.min(
    width - 2,
    polygon.map((point) => point.x).reduce(math.max).ceil(),
  );
  final minY = math.max(
    1,
    polygon.map((point) => point.y).reduce(math.min).floor(),
  );
  final maxY = math.min(
    height - 2,
    polygon.map((point) => point.y).reduce(math.max).ceil(),
  );
  var count = 0;
  var intensityMean = 0.0;
  var laplacianMean = 0.0;
  var laplacianSquaredDifferenceSum = 0.0;
  for (var y = minY; y <= maxY; y += 2) {
    for (var x = minX; x <= maxX; x += 2) {
      if (!_insideConvexPolygon(x + 0.5, y + 0.5, polygon)) continue;
      final index = y * width + x;
      final intensity = pixels[index];
      final laplacian =
          4 * intensity -
          pixels[index - 1] -
          pixels[index + 1] -
          pixels[index - width] -
          pixels[index + width];
      count++;
      intensityMean += (intensity - intensityMean) / count;
      final delta = laplacian - laplacianMean;
      laplacianMean += delta / count;
      laplacianSquaredDifferenceSum += delta * (laplacian - laplacianMean);
    }
  }
  return AnalysisRegionMetrics(
    meanIntensity: count == 0 ? 0 : intensityMean,
    sharpness: count > 1 ? laplacianSquaredDifferenceSum / (count - 1) : 0,
    sampleCount: count,
  );
}

bool _insideConvexPolygon(double x, double y, List<ImagePoint> polygon) {
  double? sign;
  for (var index = 0; index < polygon.length; index++) {
    final start = polygon[index];
    final end = polygon[(index + 1) % polygon.length];
    final cross =
        (end.x - start.x) * (y - start.y) - (end.y - start.y) * (x - start.x);
    if (cross.abs() < 1e-9) continue;
    sign ??= cross.sign;
    if (cross.sign != sign) return false;
  }
  return sign != null;
}

double _polygonArea(List<ImagePoint> points) {
  var twiceArea = 0.0;
  for (var index = 0; index < points.length; index++) {
    final current = points[index];
    final next = points[(index + 1) % points.length];
    twiceArea += current.x * next.y - next.x * current.y;
  }
  return twiceArea / 2;
}
