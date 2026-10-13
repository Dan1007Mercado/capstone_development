import '../../../core/geometry/physical_geometry.dart';

/// Central conversion between physical page millimeters and PDF points.
abstract final class PdfUnits {
  static const double pointsPerInch = 72;
  static const double millimetersPerInch = 25.4;

  static double millimetersToPoints(double millimeters) {
    if (!millimeters.isFinite) {
      throw ArgumentError.value(millimeters, 'millimeters', 'Must be finite.');
    }
    return millimeters * pointsPerInch / millimetersPerInch;
  }

  static double lengthToPoints(PhysicalLength length) =>
      millimetersToPoints(length.millimeters);

  static PdfPointRect rectToPoints(PhysicalRect rect) => PdfPointRect(
    left: lengthToPoints(rect.left),
    top: lengthToPoints(rect.top),
    width: lengthToPoints(rect.width),
    height: lengthToPoints(rect.height),
  );
}

final class PdfPointRect {
  const PdfPointRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final double left;
  final double top;
  final double width;
  final double height;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PdfPointRect &&
          other.left == left &&
          other.top == top &&
          other.width == width &&
          other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);
}
