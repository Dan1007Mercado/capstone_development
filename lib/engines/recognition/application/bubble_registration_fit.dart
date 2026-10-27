import 'dart:math' as math;

import '../../aruco/domain/image_geometry.dart';
import '../domain/bubble_registration.dart';

/// A small robust affine displacement fit, limited by its observed convex hull.
final class BubbleRegistrationFit {
  BubbleRegistrationFit(this.origin, this.scale, this.x, this.y, this.inliers);
  final ImagePoint origin;
  final double scale;
  final List<double> x, y;
  final List<BubbleCenterObservation> inliers;

  ImagePoint project(ImagePoint point) {
    final f = [1.0, (point.x - origin.x) / scale, (point.y - origin.y) / scale];
    double dot(List<double> c) => c[0] * f[0] + c[1] * f[1] + c[2] * f[2];
    return ImagePoint(point.x + dot(x), point.y + dot(y));
  }

  static BubbleRegistrationFit? robust(
    List<BubbleCenterObservation> points,
    double tolerance,
    BubbleRegistrationConfig config,
  ) {
    if (points.length < 3) return null;
    final random = math.Random(0);
    List<BubbleCenterObservation>? best;
    var bestError = double.infinity;
    for (var trial = 0; trial < config.maximumHypotheses; trial++) {
      final indices = <int>{};
      while (indices.length < 3) {
        indices.add(random.nextInt(points.length));
      }
      final candidate = fit([for (final i in indices) points[i]]);
      if (candidate == null) continue;
      final inliers = <BubbleCenterObservation>[];
      var error = 0.0;
      for (final point in points) {
        final distance = candidate
            .project(point.expected)
            .distanceTo(point.observed);
        if (distance <= tolerance) {
          inliers.add(point);
          error += distance;
        }
      }
      if (best == null ||
          inliers.length > best.length ||
          (inliers.length == best.length && error < bestError)) {
        best = inliers;
        bestError = error;
      }
    }
    if (best == null ||
        best.length < 3 ||
        best.length / points.length < config.minimumInlierFraction) {
      return null;
    }
    final result = fit(best);
    if (result == null ||
        best.any(
          (o) => result.project(o.expected).distanceTo(o.observed) > tolerance,
        )) {
      return null;
    }
    return result;
  }

  static BubbleRegistrationFit? fit(List<BubbleCenterObservation> points) {
    final origin = points.first.expected;
    final scale = points
        .map((p) => p.expected.distanceTo(origin))
        .fold(1.0, math.max);
    final normal = List.generate(3, (_) => List<double>.filled(3, 0));
    final bx = List<double>.filled(3, 0), by = List<double>.filled(3, 0);
    for (final p in points) {
      final f = [
        1.0,
        (p.expected.x - origin.x) / scale,
        (p.expected.y - origin.y) / scale,
      ];
      for (var i = 0; i < 3; i++) {
        bx[i] += f[i] * (p.observed.x - p.expected.x);
        by[i] += f[i] * (p.observed.y - p.expected.y);
        for (var j = 0; j < 3; j++) {
          normal[i][j] += f[i] * f[j];
        }
      }
    }
    final x = _solve(normal, bx), y = _solve(normal, by);
    return x == null || y == null
        ? null
        : BubbleRegistrationFit(origin, scale, x, y, List.unmodifiable(points));
  }

  bool supports(ImagePoint point) {
    final points = inliers.map((o) => o.expected).toList()
      ..sort((a, b) => a.x == b.x ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
    double cross(ImagePoint a, ImagePoint b, ImagePoint c) =>
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
    List<ImagePoint> half(Iterable<ImagePoint> input) {
      final result = <ImagePoint>[];
      for (final p in input) {
        while (result.length >= 2 &&
            cross(result[result.length - 2], result.last, p) <= 0) {
          result.removeLast();
        }
        result.add(p);
      }
      return result;
    }

    final lower = half(points), upper = half(points.reversed);
    final hull = [
      ...lower.take(lower.length - 1),
      ...upper.take(upper.length - 1),
    ];
    if (hull.length < 3) return false;
    for (var i = 0; i < hull.length; i++) {
      if (cross(hull[i], hull[(i + 1) % hull.length], point) < -1e-6) {
        return false;
      }
    }
    return true;
  }

  static List<double>? _solve(List<List<double>> a, List<double> b) {
    final m = [
      for (var i = 0; i < 3; i++) [...a[i], b[i]],
    ];
    for (var col = 0; col < 3; col++) {
      var pivot = col;
      for (var row = col + 1; row < 3; row++) {
        if (m[row][col].abs() > m[pivot][col].abs()) pivot = row;
      }
      if (m[pivot][col].abs() < 1e-9) return null;
      final temp = m[col];
      m[col] = m[pivot];
      m[pivot] = temp;
      final scale = m[col][col];
      for (var j = col; j < 4; j++) {
        m[col][j] /= scale;
      }
      for (var row = 0; row < 3; row++) {
        if (row == col) continue;
        final factor = m[row][col];
        for (var j = col; j < 4; j++) {
          m[row][j] -= factor * m[col][j];
        }
      }
    }
    return [for (final row in m) row[3]];
  }
}
