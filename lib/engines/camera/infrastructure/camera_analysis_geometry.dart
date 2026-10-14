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
    final spans = <double>[
      for (var index = 0; index < 4; index++)
        registrationPoints[index].distanceTo(
          registrationPoints[(index + 1) % 4],
        ),
      registrationPoints[0].distanceTo(registrationPoints[2]),
      registrationPoints[1].distanceTo(registrationPoints[3]),
    ];
    perspectiveRatio = spans.reduce(math.max) / spans.reduce(math.min);
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

double _polygonArea(List<ImagePoint> points) {
  var twiceArea = 0.0;
  for (var index = 0; index < points.length; index++) {
    final current = points[index];
    final next = points[(index + 1) % points.length];
    twiceArea += current.x * next.y - next.x * current.y;
  }
  return twiceArea / 2;
}
