import 'dart:collection';

import '../../aruco/domain/image_geometry.dart';
import 'canonical_bubble_roi.dart';

/// Geometry limits, expressed relative to the published circle radius.
/// These do not alter mark classification or the published layout.
final class BubbleRegistrationConfig {
  const BubbleRegistrationConfig({
    this.maximumShiftRatio = 1,
    this.minimumRadiusRatio = .82,
    this.maximumRadiusRatio = 1.18,
    this.minimumOutlineCoverage = .7,
    this.minimumContrastRatio = .15,
    this.inkThresholdRatio = .6,
    this.maximumAspectRatio = 1.2,
    this.paperPercentile = .8,
    this.paperSamplingStride = 3,
    this.outlineSampleCount = 32,
    this.outsideSampleOffsetRatio = .25,
    this.fitErrorRatio = .12,
    this.validationErrorRatio = .16,
    this.minimumInlierFraction = .8,
    this.maximumHypotheses = 128,
  });

  /// Maximum corrected-center displacement / published radius.
  final double maximumShiftRatio;

  /// Smallest acceptable detected outline radius / published radius.
  final double minimumRadiusRatio;

  /// Largest acceptable detected outline radius / published radius.
  final double maximumRadiusRatio;

  /// Required fraction of angular samples with a dark outline edge.
  final double minimumOutlineCoverage;

  /// Required outline-to-paper intensity gap / local paper intensity.
  final double minimumContrastRatio;

  /// Local paper intensity multiplier used to segment dark components.
  final double inkThresholdRatio;

  /// Largest accepted component major/minor radius ratio.
  final double maximumAspectRatio;

  /// Local intensity percentile used as the paper estimate.
  final double paperPercentile;

  /// Pixel stride used to build the local paper histogram.
  final int paperSamplingStride;

  /// Angular samples used by circular outline validation.
  final int outlineSampleCount;

  /// Outside-ring offset / published radius for contrast validation.
  final double outsideSampleOffsetRatio;

  /// Fitting inlier error / published radius.
  final double fitErrorRatio;

  /// Held-out prediction error / published radius.
  final double validationErrorRatio;

  /// Required robust-fit inlier count / detected landmark count.
  final double minimumInlierFraction;

  /// Deterministic cap on robust-fit hypotheses.
  final int maximumHypotheses;

  bool get valid =>
      [
        maximumShiftRatio,
        minimumRadiusRatio,
        maximumRadiusRatio,
        minimumOutlineCoverage,
        minimumContrastRatio,
        inkThresholdRatio,
        maximumAspectRatio,
        paperPercentile,
        outsideSampleOffsetRatio,
        fitErrorRatio,
        validationErrorRatio,
        minimumInlierFraction,
      ].every((v) => v.isFinite && v > 0) &&
      maximumShiftRatio <= 1 &&
      minimumRadiusRatio < 1 &&
      maximumRadiusRatio > 1 &&
      maximumRadiusRatio <= 1.3 &&
      minimumOutlineCoverage <= 1 &&
      minimumContrastRatio < 1 &&
      inkThresholdRatio < 1 &&
      maximumAspectRatio >= 1 &&
      maximumAspectRatio <= 1.5 &&
      paperPercentile < 1 &&
      paperSamplingStride > 0 &&
      paperSamplingStride <= 8 &&
      outlineSampleCount >= 16 &&
      outlineSampleCount <= 128 &&
      outsideSampleOffsetRatio < 1 &&
      fitErrorRatio < validationErrorRatio &&
      validationErrorRatio < .25 &&
      minimumInlierFraction <= 1 &&
      maximumHypotheses > 0 &&
      maximumHypotheses <= 1024;
}

final class BubbleCenterObservation {
  const BubbleCenterObservation({
    required this.index,
    required this.question,
    required this.expected,
    required this.observed,
    required this.radius,
    required this.outlineCoverage,
  });
  final int index;
  final String question;
  final ImagePoint expected;
  final ImagePoint observed;
  final double radius;
  final double outlineCoverage;
}

/// One capture's validated sampling plan. Never persisted as template geometry.
final class BubbleRegistration {
  BubbleRegistration({
    required Iterable<CanonicalBubbleRoi> rois,
    required Iterable<BubbleCenterObservation> observations,
    required Iterable<Map<String, Object?>> regions,
    required this.duration,
  }) : rois = UnmodifiableListView(List.of(rois)),
       observations = UnmodifiableListView(List.of(observations)),
       regions = UnmodifiableListView([
         for (final r in regions) Map<String, Object?>.unmodifiable(r),
       ]);
  final List<CanonicalBubbleRoi> rois;
  final List<BubbleCenterObservation> observations;
  final List<Map<String, Object?>> regions;
  final Duration duration;

  Map<String, Object?> toJson() => {
    'durationMs': duration.inMicroseconds / 1000,
    'regions': regions,
    'observations': [
      for (final o in observations)
        {
          'index': o.index,
          'question': o.question,
          'expected': [o.expected.x, o.expected.y],
          'observed': [o.observed.x, o.observed.y],
          'radius': o.radius,
          'outlineCoverage': o.outlineCoverage,
        },
    ],
    'samplingCenters': [
      for (final roi in rois) [roi.center.x, roi.center.y],
    ],
  };
}
