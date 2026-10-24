import 'dart:math' as math;

import '../../../engines/aruco/domain/image_geometry.dart';
import '../../../engines/camera/domain/camera_models.dart';

final class PreviewSize {
  const PreviewSize(this.width, this.height)
    : assert(width > 0),
      assert(height > 0);

  final double width;
  final double height;
}

/// Maps source analysis coordinates onto the center-cropped CameraPreview.
///
/// CameraPreview applies sensor/device orientation before BoxFit.cover. The
/// mapper mirrors that transform and optionally mirrors front-camera output.
final class PreviewCoordinateMapper {
  const PreviewCoordinateMapper();

  List<ImagePoint> mapQuadrilateral({
    required List<ImagePoint> sourcePoints,
    required ImageSize sourceSize,
    required PreviewSize viewportSize,
    required int sensorOrientationDegrees,
    required CameraDeviceOrientation deviceOrientation,
    required bool mirrored,
  }) {
    if (sourcePoints.length != 4) return const [];
    return [
      for (final point in sourcePoints)
        mapPoint(
          sourcePoint: point,
          sourceSize: sourceSize,
          viewportSize: viewportSize,
          sensorOrientationDegrees: sensorOrientationDegrees,
          deviceOrientation: deviceOrientation,
          mirrored: mirrored,
        ),
    ];
  }

  ImagePoint mapPoint({
    required ImagePoint sourcePoint,
    required ImageSize sourceSize,
    required PreviewSize viewportSize,
    required int sensorOrientationDegrees,
    required CameraDeviceOrientation deviceOrientation,
    required bool mirrored,
  }) {
    final rotation = _previewRotation(
      sensorOrientationDegrees,
      deviceOrientation,
      mirrored,
    );
    final rotated = _rotate(sourcePoint, sourceSize, rotation);
    final orientedSize = orientedSourceSize(
      sourceSize: sourceSize,
      sensorOrientationDegrees: sensorOrientationDegrees,
      deviceOrientation: deviceOrientation,
      mirrored: mirrored,
    );
    final orientedWidth = orientedSize.width;
    final orientedHeight = orientedSize.height;
    final orientedX = mirrored ? orientedWidth - rotated.x : rotated.x;
    final scale = math.max(
      viewportSize.width / orientedWidth,
      viewportSize.height / orientedHeight,
    );
    final cropX = (orientedWidth * scale - viewportSize.width) / 2;
    final cropY = (orientedHeight * scale - viewportSize.height) / 2;
    return ImagePoint(orientedX * scale - cropX, rotated.y * scale - cropY);
  }

  PreviewSize orientedSourceSize({
    required ImageSize sourceSize,
    required int sensorOrientationDegrees,
    required CameraDeviceOrientation deviceOrientation,
    required bool mirrored,
  }) {
    final rotation = _previewRotation(
      sensorOrientationDegrees,
      deviceOrientation,
      mirrored,
    );
    return rotation == 90 || rotation == 270
        ? PreviewSize(sourceSize.height.toDouble(), sourceSize.width.toDouble())
        : PreviewSize(
            sourceSize.width.toDouble(),
            sourceSize.height.toDouble(),
          );
  }

  int _previewRotation(
    int sensorOrientation,
    CameraDeviceOrientation deviceOrientation,
    bool frontFacing,
  ) {
    final deviceDegrees = switch (deviceOrientation) {
      CameraDeviceOrientation.portraitUp => 0,
      CameraDeviceOrientation.landscapeLeft => 90,
      CameraDeviceOrientation.portraitDown => 180,
      CameraDeviceOrientation.landscapeRight => 270,
      CameraDeviceOrientation.unknown => 0,
    };
    final degrees = frontFacing
        ? sensorOrientation + deviceDegrees
        : sensorOrientation - deviceDegrees;
    return ((degrees % 360) + 360) % 360;
  }

  ImagePoint _rotate(ImagePoint point, ImageSize size, int degrees) =>
      switch (degrees) {
        0 => point,
        90 => ImagePoint(size.height - point.y, point.x),
        180 => ImagePoint(size.width - point.x, size.height - point.y),
        270 => ImagePoint(point.y, size.width - point.x),
        _ => throw ArgumentError.value(
          degrees,
          'sensorOrientationDegrees',
          'Only right-angle camera rotations are supported.',
        ),
      };
}
