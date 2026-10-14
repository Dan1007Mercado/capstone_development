import 'dart:math' as math;

/// A finite point in source or canonical image pixels.
///
/// The origin is top-left, x increases right, and y increases down.
final class ImagePoint {
  factory ImagePoint(double x, double y) {
    if (!x.isFinite || !y.isFinite) {
      throw ArgumentError('Image coordinates must be finite.');
    }
    return ImagePoint._(x, y);
  }

  const ImagePoint._(this.x, this.y);

  final double x;
  final double y;

  double distanceTo(ImagePoint other) =>
      math.sqrt(math.pow(other.x - x, 2) + math.pow(other.y - y, 2));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImagePoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
}

/// Positive integer dimensions in image-pixel space.
final class ImageSize {
  factory ImageSize({required int width, required int height}) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Image dimensions must be positive.');
    }
    return ImageSize._(width: width, height: height);
  }

  const ImageSize._({required this.width, required this.height});

  final int width;
  final int height;

  int get area => width * height;

  bool contains(ImagePoint point) =>
      point.x >= 0 &&
      point.y >= 0 &&
      point.x <= width - 1 &&
      point.y <= height - 1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ImageSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}
