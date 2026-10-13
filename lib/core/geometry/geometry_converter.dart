import 'normalized_geometry.dart';
import 'physical_geometry.dart';

/// Central conversion boundary between physical and normalized page geometry.
abstract final class GeometryConverter {
  static NormalizedPoint physicalPointToNormalized(
    PhysicalPoint point,
    PhysicalSize pageSize,
  ) {
    _requirePointInsidePage(point, pageSize);
    return NormalizedPoint.values(
      point.x.millimeters / pageSize.width.millimeters,
      point.y.millimeters / pageSize.height.millimeters,
    );
  }

  static PhysicalPoint normalizedPointToPhysical(
    NormalizedPoint point,
    PhysicalSize pageSize,
  ) => PhysicalPoint.millimeters(
    point.x.value * pageSize.width.millimeters,
    point.y.value * pageSize.height.millimeters,
  );

  static NormalizedRect physicalRectToNormalized(
    PhysicalRect rect,
    PhysicalSize pageSize,
  ) {
    _requireRectInsidePage(rect, pageSize);
    return NormalizedRect.values(
      left: rect.left.millimeters / pageSize.width.millimeters,
      top: rect.top.millimeters / pageSize.height.millimeters,
      width: rect.width.millimeters / pageSize.width.millimeters,
      height: rect.height.millimeters / pageSize.height.millimeters,
    );
  }

  static PhysicalRect normalizedRectToPhysical(
    NormalizedRect rect,
    PhysicalSize pageSize,
  ) => PhysicalRect.millimeters(
    left: rect.left.value * pageSize.width.millimeters,
    top: rect.top.value * pageSize.height.millimeters,
    width: rect.width.value * pageSize.width.millimeters,
    height: rect.height.value * pageSize.height.millimeters,
  );

  static void _requirePointInsidePage(
    PhysicalPoint point,
    PhysicalSize pageSize,
  ) {
    if (point.x.millimeters > pageSize.width.millimeters ||
        point.y.millimeters > pageSize.height.millimeters) {
      throw RangeError('Physical point must be inside the page.');
    }
  }

  static void _requireRectInsidePage(PhysicalRect rect, PhysicalSize pageSize) {
    if (rect.right.millimeters > pageSize.width.millimeters ||
        rect.bottom.millimeters > pageSize.height.millimeters) {
      throw RangeError('Physical rectangle must be inside the page.');
    }
  }
}
