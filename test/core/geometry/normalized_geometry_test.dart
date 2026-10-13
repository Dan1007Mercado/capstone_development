import 'package:capstone_development/core/geometry/normalized_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NormalizedCoordinate', () {
    test('accepts the inclusive lower bound', () {
      expect(NormalizedCoordinate(0).value, 0);
    });

    test('accepts the inclusive upper bound', () {
      expect(NormalizedCoordinate(1).value, 1);
    });

    test('rejects out-of-range and non-finite values', () {
      expect(() => NormalizedCoordinate(-0.001), throwsRangeError);
      expect(() => NormalizedCoordinate(1.001), throwsRangeError);
      expect(() => NormalizedCoordinate(double.nan), throwsRangeError);
      expect(() => NormalizedCoordinate(double.infinity), throwsRangeError);
    });
  });

  group('NormalizedSize', () {
    test('requires positive dimensions', () {
      expect(() => NormalizedSize.values(0, 0.5), throwsRangeError);
      expect(() => NormalizedSize.values(0.5, 0), throwsRangeError);
    });
  });

  group('NormalizedRect', () {
    test('rejects rectangles extending beyond the page', () {
      expect(
        () => NormalizedRect.values(left: 0.8, top: 0, width: 0.3, height: 0.5),
        throwsRangeError,
      );
      expect(
        () => NormalizedRect.values(left: 0, top: 0.8, width: 0.5, height: 0.3),
        throwsRangeError,
      );
    });

    test('calculates derived values and containment', () {
      final rect = NormalizedRect.values(
        left: 0.1,
        top: 0.2,
        width: 0.4,
        height: 0.6,
      );
      expect(rect.right.value, closeTo(0.5, 1e-12));
      expect(rect.bottom.value, closeTo(0.8, 1e-12));
      expect(rect.center.x.value, closeTo(0.3, 1e-12));
      expect(rect.center.y.value, closeTo(0.5, 1e-12));
      expect(rect.containsPoint(NormalizedPoint.values(0.2, 0.4)), isTrue);
      expect(
        rect.containsRect(
          NormalizedRect.values(left: 0.2, top: 0.3, width: 0.1, height: 0.1),
        ),
        isTrue,
      );
    });

    test('uses positive-area intersection semantics', () {
      final first = NormalizedRect.values(
        left: 0,
        top: 0,
        width: 0.5,
        height: 0.5,
      );
      final overlap = NormalizedRect.values(
        left: 0.25,
        top: 0.25,
        width: 0.5,
        height: 0.5,
      );
      final edgeTouch = NormalizedRect.values(
        left: 0.5,
        top: 0,
        width: 0.5,
        height: 0.5,
      );
      expect(first.intersects(overlap), isTrue);
      expect(first.intersects(edgeTouch), isFalse);
    });
  });
}
