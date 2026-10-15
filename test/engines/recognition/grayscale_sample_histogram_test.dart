import 'package:capstone_development/engines/recognition/application/grayscale_sample_histogram.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'histogram mean and interpolated percentiles match sorted-list math',
    () {
      final values = <int>[255, 0, 17, 17, 63, 128, 240, 91, 42, 200];
      final histogram = GrayscaleSampleHistogram();
      for (final value in values) {
        histogram.add(value);
      }

      expect(histogram.count, values.length);
      expect(histogram.mean, _mean(values));
      for (final percentile in [0.0, 0.1, 0.25, 0.5, 0.8, 1.0]) {
        expect(
          histogram.percentile(percentile),
          _sortedPercentile(values, percentile),
        );
      }
    },
  );

  test('histogram preserves repeated-value and boundary semantics', () {
    final histogram = GrayscaleSampleHistogram();
    for (final value in [0, 0, 255, 255]) {
      histogram.add(value);
    }

    expect(histogram.percentile(0), 0);
    expect(histogram.percentile(0.5), 127.5);
    expect(histogram.percentile(1), 255);
  });
}

double _mean(List<int> values) =>
    values.fold<int>(0, (sum, value) => sum + value) / values.length;

double _sortedPercentile(List<int> values, double percentile) {
  final sorted = List<int>.of(values)..sort();
  final position = percentile * (sorted.length - 1);
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower].toDouble();
  final fraction = position - lower;
  return sorted[lower] * (1 - fraction) + sorted[upper] * fraction;
}
