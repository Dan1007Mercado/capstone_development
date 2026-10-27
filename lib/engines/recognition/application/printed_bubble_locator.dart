import 'dart:math' as math;
import 'dart:typed_data';

import '../../aruco/domain/image_geometry.dart';
import '../../preprocessing/domain/pixel_images.dart';
import '../domain/bubble_registration.dart';
import '../domain/canonical_bubble_roi.dart';

/// Bounded association with a known target, not page-wide contour discovery.
/// A component proposes a center; circular edge coverage independently checks
/// that the proposal represents an outline rather than a label or dark patch.
final class PrintedBubbleLocator {
  const PrintedBubbleLocator();

  BubbleCenterObservation? locate(
    GrayImage image,
    CanonicalBubbleRoi roi,
    int index,
    String question,
    BubbleRegistrationConfig config,
  ) {
    final extent =
        (roi.printedRadius * (1 + config.maximumShiftRatio)).ceil() + 2;
    final left = roi.center.x.floor() - extent;
    final top = roi.center.y.floor() - extent;
    final side = extent * 2 + 1;
    if (left < 0 ||
        top < 0 ||
        left + side > image.size.width ||
        top + side > image.size.height) {
      return null;
    }
    final width = image.size.width;
    final pixels = image.pixels;
    final histogram = List<int>.filled(256, 0);
    var count = 0;
    for (var y = 0; y < side; y += config.paperSamplingStride) {
      for (var x = 0; x < side; x += config.paperSamplingStride) {
        histogram[pixels[(top + y) * width + left + x]]++;
        count++;
      }
    }
    var cumulative = 0, paper = 255;
    for (var value = 0; value < 256; value++) {
      cumulative += histogram[value];
      if (cumulative >= count * config.paperPercentile) {
        paper = value;
        break;
      }
    }
    final threshold = paper * config.inkThresholdRatio;
    final visited = Uint8List(side * side);
    final candidates = <BubbleCenterObservation>[];
    bool dark(int x, int y) => pixels[(top + y) * width + left + x] < threshold;
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final start = y * side + x;
        if (visited[start] != 0 || !dark(x, y)) continue;
        final queue = <int>[start];
        visited[start] = 1;
        var minX = x, maxX = x, minY = y, maxY = y;
        for (var i = 0; i < queue.length; i++) {
          final px = queue[i] % side, py = queue[i] ~/ side;
          minX = math.min(minX, px);
          maxX = math.max(maxX, px);
          minY = math.min(minY, py);
          maxY = math.max(maxY, py);
          for (var dy = -1; dy <= 1; dy++) {
            for (var dx = -1; dx <= 1; dx++) {
              final nx = px + dx, ny = py + dy;
              if (nx < 0 || ny < 0 || nx >= side || ny >= side) continue;
              final next = ny * side + nx;
              if (visited[next] != 0 || !dark(nx, ny)) continue;
              visited[next] = 1;
              queue.add(next);
            }
          }
        }
        if (minX == 0 || minY == 0 || maxX == side - 1 || maxY == side - 1) {
          continue;
        }
        final rx = (maxX - minX + 1) / 2, ry = (maxY - minY + 1) / 2;
        final radius = (rx + ry) / 2;
        if (math.min(rx, ry) < roi.printedRadius * config.minimumRadiusRatio ||
            math.max(rx, ry) > roi.printedRadius * config.maximumRadiusRatio ||
            math.max(rx, ry) / math.min(rx, ry) > config.maximumAspectRatio) {
          continue;
        }
        final center = ImagePoint(
          left + (minX + maxX + 1) / 2,
          top + (minY + maxY + 1) / 2,
        );
        if (center.distanceTo(roi.center) >
            roi.printedRadius * config.maximumShiftRatio) {
          continue;
        }
        var supported = 0;
        final angles = config.outlineSampleCount;
        for (var angle = 0; angle < angles; angle++) {
          final theta = 2 * math.pi * angle / angles;
          final cos = math.cos(theta), sin = math.sin(theta);
          var ring = 255;
          for (final offset in [-2.0, -1.0, 0.0, 1.0]) {
            final sx = (center.x + cos * (radius + offset)).floor();
            final sy = (center.y + sin * (radius + offset)).floor();
            ring = math.min(ring, pixels[sy * width + sx]);
          }
          final outsideOffset =
              roi.printedRadius * config.outsideSampleOffsetRatio;
          final ox = (center.x + cos * (radius + outsideOffset)).floor();
          final oy = (center.y + sin * (radius + outsideOffset)).floor();
          if (ox < 0 || oy < 0 || ox >= width || oy >= image.size.height) {
            continue;
          }
          if (pixels[oy * width + ox] - ring >=
              paper * config.minimumContrastRatio) {
            supported++;
          }
        }
        final coverage = supported / angles;
        if (coverage < config.minimumOutlineCoverage) continue;
        candidates.add(
          BubbleCenterObservation(
            index: index,
            question: question,
            expected: roi.center,
            observed: center,
            radius: radius,
            outlineCoverage: coverage,
          ),
        );
      }
    }
    // Ambiguous associations are missing evidence, never a darkest/nearest pick.
    return candidates.length == 1 ? candidates.single : null;
  }
}
