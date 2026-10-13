import 'physical_geometry.dart';

enum PageOrientation { portrait, landscape }

/// Physical page dimensions and their intended orientation.
final class PageSpec {
  const PageSpec({required this.size, required this.orientation});

  factory PageSpec.a4Portrait() => PageSpec(
    size: PhysicalSize.millimeters(210, 297),
    orientation: PageOrientation.portrait,
  );

  factory PageSpec.a4Landscape() => PageSpec(
    size: PhysicalSize.millimeters(297, 210),
    orientation: PageOrientation.landscape,
  );

  final PhysicalSize size;
  final PageOrientation orientation;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PageSpec &&
          other.size == size &&
          other.orientation == orientation;

  @override
  int get hashCode => Object.hash(size, orientation);
}

/// Non-negative physical insets around page content.
final class PageMargins {
  const PageMargins({
    required this.top,
    required this.right,
    required this.bottom,
    required this.left,
  });

  factory PageMargins.all(PhysicalLength value) =>
      PageMargins(top: value, right: value, bottom: value, left: value);

  final PhysicalLength top;
  final PhysicalLength right;
  final PhysicalLength bottom;
  final PhysicalLength left;

  PhysicalRect contentRect(PhysicalSize pageSize) {
    final contentWidth =
        pageSize.width.millimeters - left.millimeters - right.millimeters;
    final contentHeight =
        pageSize.height.millimeters - top.millimeters - bottom.millimeters;
    if (contentWidth <= 0 || contentHeight <= 0) {
      throw RangeError('Margins must leave a positive page content area.');
    }
    return PhysicalRect.millimeters(
      left: left.millimeters,
      top: top.millimeters,
      width: contentWidth,
      height: contentHeight,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PageMargins &&
          other.top == top &&
          other.right == right &&
          other.bottom == bottom &&
          other.left == left;

  @override
  int get hashCode => Object.hash(top, right, bottom, left);
}

/// Pixel dimensions of a future rectified, top-down page image.
final class CanonicalPageSpec {
  factory CanonicalPageSpec({
    required int widthPixels,
    required int heightPixels,
  }) {
    if (widthPixels <= 0) {
      throw RangeError.value(widthPixels, 'widthPixels', 'Must be positive.');
    }
    if (heightPixels <= 0) {
      throw RangeError.value(heightPixels, 'heightPixels', 'Must be positive.');
    }
    return CanonicalPageSpec._(
      widthPixels: widthPixels,
      heightPixels: heightPixels,
    );
  }

  const CanonicalPageSpec._({
    required this.widthPixels,
    required this.heightPixels,
  });

  factory CanonicalPageSpec.a4FromWidth(
    int widthPixels, {
    PageOrientation orientation = PageOrientation.portrait,
  }) {
    final ratio = orientation == PageOrientation.portrait
        ? 297 / 210
        : 210 / 297;
    return CanonicalPageSpec(
      widthPixels: widthPixels,
      heightPixels: (widthPixels * ratio).round(),
    );
  }

  factory CanonicalPageSpec.a4FromHeight(
    int heightPixels, {
    PageOrientation orientation = PageOrientation.portrait,
  }) {
    final ratio = orientation == PageOrientation.portrait
        ? 210 / 297
        : 297 / 210;
    return CanonicalPageSpec(
      widthPixels: (heightPixels * ratio).round(),
      heightPixels: heightPixels,
    );
  }

  final int widthPixels;
  final int heightPixels;

  double get aspectRatio => widthPixels / heightPixels;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanonicalPageSpec &&
          other.widthPixels == widthPixels &&
          other.heightPixels == heightPixels;

  @override
  int get hashCode => Object.hash(widthPixels, heightPixels);

  @override
  String toString() =>
      'CanonicalPageSpec(widthPixels: $widthPixels, heightPixels: $heightPixels)';
}
