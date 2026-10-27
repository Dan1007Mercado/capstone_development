import 'dart:collection';

import '../../../core/ids/identifiers.dart';
import '../../aruco/domain/image_geometry.dart';
import 'canonical_bubble_roi.dart';
import 'bubble_registration.dart';

enum BubbleRoiClipping { none, partial }

final class BubbleMeasurementQuality {
  const BubbleMeasurementQuality({
    required this.interiorValidSampleRatio,
    required this.baselineValidSampleRatio,
    required this.clipping,
    required this.baselineForegroundRatio,
    required this.localBaselineReliable,
    required this.neighborMaskedPixelCount,
  });

  final double interiorValidSampleRatio;
  final double baselineValidSampleRatio;
  final BubbleRoiClipping clipping;
  final double baselineForegroundRatio;
  final bool localBaselineReliable;
  final int neighborMaskedPixelCount;
}

final class BubbleMeasurement {
  const BubbleMeasurement({
    required this.pageId,
    required this.questionId,
    required this.optionId,
    required this.numericColumnIndex,
    required this.numericDigitValue,
    required this.roi,
    required this.sampledInteriorPixelCount,
    required this.sampledBaselinePixelCount,
    required this.interiorMeanIntensity,
    required this.interiorMedianIntensity,
    required this.localBaselineIntensity,
    required this.darknessContrast,
    required this.normalizedDarkness,
    required this.foregroundPixelCount,
    required this.fillRatio,
    required this.distributionScore,
    required this.quality,
  });

  final PageId pageId;
  final QuestionId questionId;
  final OptionId? optionId;
  final int? numericColumnIndex;
  final int? numericDigitValue;
  final CanonicalBubbleRoi roi;
  final int sampledInteriorPixelCount;
  final int sampledBaselinePixelCount;
  final double interiorMeanIntensity;
  final double interiorMedianIntensity;
  final double localBaselineIntensity;
  final double darknessContrast;
  final double normalizedDarkness;
  final int foregroundPixelCount;
  final double fillRatio;

  /// Fraction of fixed-grid interior cells containing meaningful foreground.
  /// This describes ink spread, not confidence or probability.
  final double distributionScore;
  final BubbleMeasurementQuality quality;

  ImagePoint get canonicalCenter => roi.center;
  double get canonicalMeasurementRadius => roi.interiorRadius;
}

final class BubbleMeasurementSet {
  BubbleMeasurementSet({
    required this.pageId,
    required Iterable<BubbleMeasurement> measurements,
    this.registration,
  }) : measurements = UnmodifiableListView(List.of(measurements));

  final PageId pageId;
  final List<BubbleMeasurement> measurements;
  final BubbleRegistration? registration;
}
