import 'package:capstone_development/core/geometry/geometry_converter.dart';
import 'package:capstone_development/core/geometry/normalized_geometry.dart';
import 'package:capstone_development/core/geometry/physical_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pageSize = PhysicalSize.millimeters(200, 100);

  test('converts physical points to normalized points', () {
    final result = GeometryConverter.physicalPointToNormalized(
      PhysicalPoint.millimeters(50, 75),
      pageSize,
    );
    expect(result.x.value, closeTo(0.25, 1e-12));
    expect(result.y.value, closeTo(0.75, 1e-12));
  });

  test('rejects physical points outside the page', () {
    expect(
      () => GeometryConverter.physicalPointToNormalized(
        PhysicalPoint.millimeters(201, 50),
        pageSize,
      ),
      throwsRangeError,
    );
  });

  test('converts normalized points to physical points', () {
    final result = GeometryConverter.normalizedPointToPhysical(
      NormalizedPoint.values(0.25, 0.75),
      pageSize,
    );
    expect(result.x.millimeters, closeTo(50, 1e-12));
    expect(result.y.millimeters, closeTo(75, 1e-12));
  });

  test('converts physical rectangles to normalized rectangles', () {
    final result = GeometryConverter.physicalRectToNormalized(
      PhysicalRect.millimeters(left: 20, top: 10, width: 100, height: 40),
      pageSize,
    );
    expect(result.left.value, closeTo(0.1, 1e-12));
    expect(result.top.value, closeTo(0.1, 1e-12));
    expect(result.width.value, closeTo(0.5, 1e-12));
    expect(result.height.value, closeTo(0.4, 1e-12));
  });

  test('rejects physical rectangles outside the page', () {
    expect(
      () => GeometryConverter.physicalRectToNormalized(
        PhysicalRect.millimeters(left: 150, top: 10, width: 60, height: 40),
        pageSize,
      ),
      throwsRangeError,
    );
  });

  test('converts normalized rectangles to physical rectangles', () {
    final result = GeometryConverter.normalizedRectToPhysical(
      NormalizedRect.values(left: 0.1, top: 0.1, width: 0.5, height: 0.4),
      pageSize,
    );
    expect(result.left.millimeters, closeTo(20, 1e-12));
    expect(result.top.millimeters, closeTo(10, 1e-12));
    expect(result.width.millimeters, closeTo(100, 1e-12));
    expect(result.height.millimeters, closeTo(40, 1e-12));
  });

  test('round-trips a physical point', () {
    final original = PhysicalPoint.millimeters(37.2, 88.8);
    final normalized = GeometryConverter.physicalPointToNormalized(
      original,
      pageSize,
    );
    final roundTripped = GeometryConverter.normalizedPointToPhysical(
      normalized,
      pageSize,
    );
    expect(roundTripped.x.millimeters, closeTo(original.x.millimeters, 1e-10));
    expect(roundTripped.y.millimeters, closeTo(original.y.millimeters, 1e-10));
  });

  test('round-trips a physical rectangle', () {
    final original = PhysicalRect.millimeters(
      left: 12.3,
      top: 7.6,
      width: 98.4,
      height: 45.1,
    );
    final normalized = GeometryConverter.physicalRectToNormalized(
      original,
      pageSize,
    );
    final roundTripped = GeometryConverter.normalizedRectToPhysical(
      normalized,
      pageSize,
    );
    expect(
      roundTripped.left.millimeters,
      closeTo(original.left.millimeters, 1e-10),
    );
    expect(
      roundTripped.top.millimeters,
      closeTo(original.top.millimeters, 1e-10),
    );
    expect(
      roundTripped.width.millimeters,
      closeTo(original.width.millimeters, 1e-10),
    );
    expect(
      roundTripped.height.millimeters,
      closeTo(original.height.millimeters, 1e-10),
    );
  });
}
