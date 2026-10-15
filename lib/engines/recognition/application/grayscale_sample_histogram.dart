import 'dart:typed_data';

/// Allocation-bounded statistics for 8-bit grayscale samples.
final class GrayscaleSampleHistogram {
  final Uint32List _bins = Uint32List(256);
  int count = 0;
  int _sum = 0;

  void add(int value) {
    if (value < 0 || value > 255) {
      throw RangeError.range(value, 0, 255, 'value');
    }
    _bins[value]++;
    count++;
    _sum += value;
  }

  double get mean {
    if (count == 0) throw StateError('No grayscale samples were recorded.');
    return _sum / count;
  }

  double percentile(double percentile) {
    if (count == 0) throw StateError('No grayscale samples were recorded.');
    if (!percentile.isFinite || percentile < 0 || percentile > 1) {
      throw RangeError.range(percentile, 0, 1, 'percentile');
    }
    final position = percentile * (count - 1);
    final lowerRank = position.floor();
    final upperRank = position.ceil();
    final lower = _valueAtRank(lowerRank);
    if (lowerRank == upperRank) return lower.toDouble();
    final upper = _valueAtRank(upperRank);
    final fraction = position - lowerRank;
    return lower * (1 - fraction) + upper * fraction;
  }

  int _valueAtRank(int rank) {
    var cumulative = 0;
    for (var value = 0; value < _bins.length; value++) {
      cumulative += _bins[value];
      if (rank < cumulative) return value;
    }
    throw StateError('Histogram rank is outside the recorded sample count.');
  }
}
