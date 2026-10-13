/// A non-negative physical distance measured in millimeters.
final class PhysicalLength {
  factory PhysicalLength(double millimeters) {
    if (!millimeters.isFinite || millimeters < 0) {
      throw RangeError.value(
        millimeters,
        'millimeters',
        'Physical length must be finite and non-negative.',
      );
    }
    return PhysicalLength._(millimeters);
  }

  const PhysicalLength._(this.millimeters);

  factory PhysicalLength.zero() => const PhysicalLength._(0);

  final double millimeters;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhysicalLength && other.millimeters == millimeters;

  @override
  int get hashCode => millimeters.hashCode;

  @override
  String toString() => '${millimeters}mm';
}

/// A point in physical page space, with a top-left origin.
final class PhysicalPoint {
  const PhysicalPoint({required this.x, required this.y});

  factory PhysicalPoint.millimeters(double x, double y) =>
      PhysicalPoint(x: PhysicalLength(x), y: PhysicalLength(y));

  final PhysicalLength x;
  final PhysicalLength y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhysicalPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'PhysicalPoint(x: $x, y: $y)';
}

/// Positive physical dimensions measured in millimeters.
final class PhysicalSize {
  factory PhysicalSize({
    required PhysicalLength width,
    required PhysicalLength height,
  }) {
    _requirePositive(width, 'width');
    _requirePositive(height, 'height');
    return PhysicalSize._(width: width, height: height);
  }

  factory PhysicalSize.millimeters(double width, double height) => PhysicalSize(
    width: PhysicalLength(width),
    height: PhysicalLength(height),
  );

  const PhysicalSize._({required this.width, required this.height});

  final PhysicalLength width;
  final PhysicalLength height;

  static void _requirePositive(PhysicalLength length, String name) {
    if (length.millimeters <= 0) {
      throw RangeError.value(
        length.millimeters,
        name,
        '$name must be positive.',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhysicalSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'PhysicalSize(width: $width, height: $height)';
}

/// A positive-area rectangle in physical page space.
final class PhysicalRect {
  factory PhysicalRect({
    required PhysicalLength left,
    required PhysicalLength top,
    required PhysicalLength width,
    required PhysicalLength height,
  }) {
    if (width.millimeters <= 0) {
      throw RangeError.value(
        width.millimeters,
        'width',
        'Width must be positive.',
      );
    }
    if (height.millimeters <= 0) {
      throw RangeError.value(
        height.millimeters,
        'height',
        'Height must be positive.',
      );
    }
    return PhysicalRect._(left: left, top: top, width: width, height: height);
  }

  factory PhysicalRect.millimeters({
    required double left,
    required double top,
    required double width,
    required double height,
  }) => PhysicalRect(
    left: PhysicalLength(left),
    top: PhysicalLength(top),
    width: PhysicalLength(width),
    height: PhysicalLength(height),
  );

  const PhysicalRect._({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final PhysicalLength left;
  final PhysicalLength top;
  final PhysicalLength width;
  final PhysicalLength height;

  PhysicalLength get right =>
      PhysicalLength(left.millimeters + width.millimeters);

  PhysicalLength get bottom =>
      PhysicalLength(top.millimeters + height.millimeters);

  PhysicalPoint get center => PhysicalPoint.millimeters(
    left.millimeters + width.millimeters / 2,
    top.millimeters + height.millimeters / 2,
  );

  bool containsPoint(PhysicalPoint point) =>
      point.x.millimeters >= left.millimeters &&
      point.x.millimeters <= right.millimeters &&
      point.y.millimeters >= top.millimeters &&
      point.y.millimeters <= bottom.millimeters;

  bool containsRect(PhysicalRect other) =>
      other.left.millimeters >= left.millimeters &&
      other.right.millimeters <= right.millimeters &&
      other.top.millimeters >= top.millimeters &&
      other.bottom.millimeters <= bottom.millimeters;

  /// Returns true only when the rectangles share positive area.
  bool intersects(PhysicalRect other) =>
      left.millimeters < other.right.millimeters &&
      right.millimeters > other.left.millimeters &&
      top.millimeters < other.bottom.millimeters &&
      bottom.millimeters > other.top.millimeters;

  PhysicalRect? intersection(PhysicalRect other) {
    if (!intersects(other)) return null;

    final intersectionLeft = _max(left.millimeters, other.left.millimeters);
    final intersectionTop = _max(top.millimeters, other.top.millimeters);
    final intersectionRight = _min(right.millimeters, other.right.millimeters);
    final intersectionBottom = _min(
      bottom.millimeters,
      other.bottom.millimeters,
    );
    return PhysicalRect.millimeters(
      left: intersectionLeft,
      top: intersectionTop,
      width: intersectionRight - intersectionLeft,
      height: intersectionBottom - intersectionTop,
    );
  }

  static double _min(double first, double second) =>
      first < second ? first : second;

  static double _max(double first, double second) =>
      first > second ? first : second;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhysicalRect &&
          other.left == left &&
          other.top == top &&
          other.width == width &&
          other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() =>
      'PhysicalRect(left: $left, top: $top, width: $width, height: $height)';
}
