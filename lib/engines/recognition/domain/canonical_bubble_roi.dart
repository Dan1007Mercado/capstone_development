import '../../aruco/domain/image_geometry.dart';

final class CanonicalBubbleRoi {
  const CanonicalBubbleRoi({
    required this.center,
    required this.printedRadius,
    required this.interiorRadius,
    required this.baselineInnerRadius,
    required this.baselineOuterRadius,
  });

  final ImagePoint center;
  final double printedRadius;
  final double interiorRadius;
  final double baselineInnerRadius;
  final double baselineOuterRadius;

  bool containsInteriorPixel(int x, int y) =>
      _squaredDistanceToPixelCenter(x, y) <= interiorRadius * interiorRadius;

  bool containsPrintedPixel(int x, int y) =>
      _squaredDistanceToPixelCenter(x, y) <= printedRadius * printedRadius;

  bool containsBaselinePixel(int x, int y) {
    final squaredDistance = _squaredDistanceToPixelCenter(x, y);
    return squaredDistance >= baselineInnerRadius * baselineInnerRadius &&
        squaredDistance <= baselineOuterRadius * baselineOuterRadius;
  }

  double _squaredDistanceToPixelCenter(int x, int y) {
    final dx = x + 0.5 - center.x;
    final dy = y + 0.5 - center.y;
    return dx * dx + dy * dy;
  }
}
