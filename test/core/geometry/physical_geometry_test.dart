import 'package:capstone_development/core/geometry/physical_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PhysicalLength', () {
    test('rejects negative and non-finite values', () {
      expect(() => PhysicalLength(-0.1), throwsRangeError);
      expect(() => PhysicalLength(double.nan), throwsRangeError);
      expect(() => PhysicalLength(double.infinity), throwsRangeError);
    });
  });

  group('PhysicalSize', () {
    test('requires positive dimensions', () {
      expect(() => PhysicalSize.millimeters(0, 10), throwsRangeError);
      expect(() => PhysicalSize.millimeters(10, 0), throwsRangeError);
      expect(() => PhysicalSize.millimeters(-1, 10), throwsRangeError);
    });

    test('compares by width and height', () {
      expect(
        PhysicalSize.millimeters(210, 297),
        PhysicalSize.millimeters(210, 297),
      );
    });
  });

  group('PhysicalRect', () {
    final rect = PhysicalRect.millimeters(
      left: 10,
      top: 20,
      width: 40,
      height: 60,
    );

    test('requires positive dimensions', () {
      expect(
        () => PhysicalRect.millimeters(left: 0, top: 0, width: 0, height: 1),
        throwsRangeError,
      );
    });

    test('calculates derived properties', () {
      expect(rect.right.millimeters, 50);
      expect(rect.bottom.millimeters, 80);
      expect(rect.center, PhysicalPoint.millimeters(30, 50));
    });

    test('contains points including its boundary', () {
      expect(rect.containsPoint(PhysicalPoint.millimeters(10, 20)), isTrue);
      expect(rect.containsPoint(PhysicalPoint.millimeters(50, 80)), isTrue);
      expect(rect.containsPoint(PhysicalPoint.millimeters(9, 20)), isFalse);
    });

    test('contains rectangles including an equal rectangle', () {
      expect(rect.containsRect(rect), isTrue);
      expect(
        rect.containsRect(
          PhysicalRect.millimeters(left: 20, top: 30, width: 10, height: 10),
        ),
        isTrue,
      );
      expect(
        rect.containsRect(
          PhysicalRect.millimeters(left: 0, top: 20, width: 20, height: 20),
        ),
        isFalse,
      );
    });

    test('detects only positive-area intersections', () {
      final overlapping = PhysicalRect.millimeters(
        left: 40,
        top: 70,
        width: 30,
        height: 20,
      );
      final edgeTouching = PhysicalRect.millimeters(
        left: 50,
        top: 20,
        width: 10,
        height: 10,
      );
      expect(rect.intersects(overlapping), isTrue);
      expect(rect.intersects(edgeTouching), isFalse);
    });

    test('returns the overlap rectangle or null', () {
      final overlapping = PhysicalRect.millimeters(
        left: 40,
        top: 70,
        width: 30,
        height: 20,
      );
      expect(
        rect.intersection(overlapping),
        PhysicalRect.millimeters(left: 40, top: 70, width: 10, height: 10),
      );
      expect(
        rect.intersection(
          PhysicalRect.millimeters(left: 100, top: 100, width: 10, height: 10),
        ),
        isNull,
      );
    });
  });
}
