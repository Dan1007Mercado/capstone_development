/// A finite page-relative coordinate in the inclusive range [0, 1].
final class NormalizedCoordinate {
  factory NormalizedCoordinate(double value) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw RangeError.range(value, 0, 1, 'value');
    }
    return NormalizedCoordinate._(value);
  }

  const NormalizedCoordinate._(this.value);

  final double value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalizedCoordinate && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'NormalizedCoordinate($value)';
}

final class NormalizedPoint {
  const NormalizedPoint({required this.x, required this.y});

  factory NormalizedPoint.values(double x, double y) =>
      NormalizedPoint(x: NormalizedCoordinate(x), y: NormalizedCoordinate(y));

  final NormalizedCoordinate x;
  final NormalizedCoordinate y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalizedPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'NormalizedPoint(x: $x, y: $y)';
}

/// Positive normalized dimensions, each no greater than one.
final class NormalizedSize {
  factory NormalizedSize({
    required NormalizedCoordinate width,
    required NormalizedCoordinate height,
  }) {
    _requirePositive(width, 'width');
    _requirePositive(height, 'height');
    return NormalizedSize._(width: width, height: height);
  }

  factory NormalizedSize.values(double width, double height) => NormalizedSize(
    width: NormalizedCoordinate(width),
    height: NormalizedCoordinate(height),
  );

  const NormalizedSize._({required this.width, required this.height});

  final NormalizedCoordinate width;
  final NormalizedCoordinate height;

  static void _requirePositive(NormalizedCoordinate value, String name) {
    if (value.value <= 0) {
      throw RangeError.value(value.value, name, '$name must be positive.');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalizedSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'NormalizedSize(width: $width, height: $height)';
}

/// A positive-area rectangle fully contained by normalized page space.
final class NormalizedRect {
  factory NormalizedRect({
    required NormalizedCoordinate left,
    required NormalizedCoordinate top,
    required NormalizedCoordinate width,
    required NormalizedCoordinate height,
  }) {
    if (width.value <= 0) {
      throw RangeError.value(width.value, 'width', 'Width must be positive.');
    }
    if (height.value <= 0) {
      throw RangeError.value(
        height.value,
        'height',
        'Height must be positive.',
      );
    }
    if (left.value + width.value > 1) {
      throw RangeError('Normalized rectangle exceeds the page width.');
    }
    if (top.value + height.value > 1) {
      throw RangeError('Normalized rectangle exceeds the page height.');
    }
    return NormalizedRect._(left: left, top: top, width: width, height: height);
  }

  factory NormalizedRect.values({
    required double left,
    required double top,
    required double width,
    required double height,
  }) => NormalizedRect(
    left: NormalizedCoordinate(left),
    top: NormalizedCoordinate(top),
    width: NormalizedCoordinate(width),
    height: NormalizedCoordinate(height),
  );

  const NormalizedRect._({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final NormalizedCoordinate left;
  final NormalizedCoordinate top;
  final NormalizedCoordinate width;
  final NormalizedCoordinate height;

  NormalizedCoordinate get right =>
      NormalizedCoordinate(left.value + width.value);

  NormalizedCoordinate get bottom =>
      NormalizedCoordinate(top.value + height.value);

  NormalizedPoint get center => NormalizedPoint.values(
    left.value + width.value / 2,
    top.value + height.value / 2,
  );

  bool containsPoint(NormalizedPoint point) =>
      point.x.value >= left.value &&
      point.x.value <= right.value &&
      point.y.value >= top.value &&
      point.y.value <= bottom.value;

  bool containsRect(NormalizedRect other) =>
      other.left.value >= left.value &&
      other.right.value <= right.value &&
      other.top.value >= top.value &&
      other.bottom.value <= bottom.value;

  /// Returns true only when the rectangles share positive area.
  bool intersects(NormalizedRect other) =>
      left.value < other.right.value &&
      right.value > other.left.value &&
      top.value < other.bottom.value &&
      bottom.value > other.top.value;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NormalizedRect &&
          other.left == left &&
          other.top == top &&
          other.width == width &&
          other.height == height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() =>
      'NormalizedRect(left: $left, top: $top, width: $width, height: $height)';
}
