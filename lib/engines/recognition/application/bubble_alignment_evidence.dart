import 'dart:collection';
import 'dart:math' as math;

import '../../aruco/domain/page_alignment_result.dart';
import '../../layout/domain/layout_regions.dart';
import '../../layout/domain/page_layout.dart';

enum BubbleAlignmentEvidenceStatus { measured, inconclusive }

/// Independent printed-outline evidence. It is diagnostic only and must never
/// be used as a production alignment or answer-classification gate.
final class BubbleAlignmentEvidence {
  BubbleAlignmentEvidence({
    required this.status,
    required Iterable<BubbleOutlineObservation> observations,
    required this.meanCenterDisplacementPixels,
    required this.percentile95CenterDisplacementPixels,
    required this.meanRadiusErrorPixels,
    required this.meanRingContrast,
    required this.observedCoverage,
    required this.confidenceScore,
    required Map<String, double> regionalMeanDisplacementPixels,
    this.inconclusiveReason,
  }) : observations = UnmodifiableListView(List.of(observations)),
       regionalMeanDisplacementPixels = UnmodifiableMapView(
         Map.of(regionalMeanDisplacementPixels),
       );

  final BubbleAlignmentEvidenceStatus status;
  final List<BubbleOutlineObservation> observations;
  final double? meanCenterDisplacementPixels;
  final double? percentile95CenterDisplacementPixels;
  final double? meanRadiusErrorPixels;
  final double? meanRingContrast;
  final double observedCoverage;
  final double confidenceScore;
  final Map<String, double> regionalMeanDisplacementPixels;
  final String? inconclusiveReason;
}

final class BubbleOutlineObservation {
  const BubbleOutlineObservation({
    required this.questionId,
    required this.targetLabel,
    required this.expectedCenterX,
    required this.expectedCenterY,
    required this.observedCenterX,
    required this.observedCenterY,
    required this.expectedRadiusPixels,
    required this.observedRadiusPixels,
    required this.centerDisplacementPixels,
    required this.ringContrast,
    required this.sampleCoverage,
    required this.confident,
  });

  final String questionId;
  final String targetLabel;
  final double expectedCenterX;
  final double expectedCenterY;
  final double observedCenterX;
  final double observedCenterY;
  final double expectedRadiusPixels;
  final double observedRadiusPixels;
  final double centerDisplacementPixels;
  final double ringContrast;
  final double sampleCoverage;
  final bool confident;
}

final class BubbleAlignmentEvidenceEvaluator {
  const BubbleAlignmentEvidenceEvaluator({
    this.maximumCenterSearchPixels = 4,
    this.minimumRingContrast = 8,
    this.minimumSampleCoverage = 0.8,
    this.minimumObservedFraction = 0.3,
    this.minimumObservedCount = 4,
  });

  final int maximumCenterSearchPixels;
  final double minimumRingContrast;
  final double minimumSampleCoverage;
  final double minimumObservedFraction;
  final int minimumObservedCount;

  BubbleAlignmentEvidence evaluate(CanonicalPageImage image, PageLayout page) {
    if (image.grayscaleBytes.length != image.size.area ||
        image.size.width != page.canonicalPageSpec.widthPixels ||
        image.size.height != page.canonicalPageSpec.heightPixels ||
        page.bubbleRegions.isEmpty) {
      return BubbleAlignmentEvidence(
        status: BubbleAlignmentEvidenceStatus.inconclusive,
        observations: const [],
        meanCenterDisplacementPixels: null,
        percentile95CenterDisplacementPixels: null,
        meanRadiusErrorPixels: null,
        meanRingContrast: null,
        observedCoverage: 0,
        confidenceScore: 0,
        regionalMeanDisplacementPixels: const {},
        inconclusiveReason:
            'CANONICAL_GRAYSCALE_OR_BUBBLE_GEOMETRY_UNAVAILABLE',
      );
    }
    final observations = [
      for (final bubble in page.bubbleRegions) _observe(image, page, bubble),
    ];
    final confident = observations.where((item) => item.confident).toList();
    final required = math.min(
      observations.length,
      math.max(
        minimumObservedCount,
        (observations.length * minimumObservedFraction).ceil(),
      ),
    );
    if (confident.length < required) {
      return BubbleAlignmentEvidence(
        status: BubbleAlignmentEvidenceStatus.inconclusive,
        observations: observations,
        meanCenterDisplacementPixels: null,
        percentile95CenterDisplacementPixels: null,
        meanRadiusErrorPixels: null,
        meanRingContrast: confident.isEmpty
            ? null
            : _mean(confident.map((item) => item.ringContrast)),
        observedCoverage: confident.length / observations.length,
        confidenceScore: confident.length / required,
        regionalMeanDisplacementPixels: const {},
        inconclusiveReason: 'INSUFFICIENT_PRINTED_OUTLINE_EVIDENCE',
      );
    }
    final displacements =
        confident.map((item) => item.centerDisplacementPixels).toList()..sort();
    return BubbleAlignmentEvidence(
      status: BubbleAlignmentEvidenceStatus.measured,
      observations: observations,
      meanCenterDisplacementPixels: _mean(displacements),
      percentile95CenterDisplacementPixels:
          displacements[((displacements.length * 0.95).ceil() - 1).clamp(
            0,
            displacements.length - 1,
          )],
      meanRadiusErrorPixels: _mean(
        confident.map(
          (item) =>
              (item.observedRadiusPixels - item.expectedRadiusPixels).abs(),
        ),
      ),
      meanRingContrast: _mean(confident.map((item) => item.ringContrast)),
      observedCoverage: confident.length / observations.length,
      confidenceScore: (_mean(confident.map((item) => item.ringContrast)) / 40)
          .clamp(0, 1),
      regionalMeanDisplacementPixels: _regional(confident, image.size.height),
    );
  }

  BubbleOutlineObservation _observe(
    CanonicalPageImage image,
    PageLayout page,
    BubbleRegion bubble,
  ) {
    final centerX = bubble.normalizedCenter.x.value * image.size.width;
    final centerY = bubble.normalizedCenter.y.value * image.size.height;
    final diameterX =
        bubble.physicalDiameter.millimeters /
        page.pageSpec.size.width.millimeters *
        image.size.width;
    final diameterY =
        bubble.physicalDiameter.millimeters /
        page.pageSpec.size.height.millimeters *
        image.size.height;
    final expectedRadius = (diameterX + diameterY) / 4;
    var best = (
      contrast: double.negativeInfinity,
      coverage: 0.0,
      x: centerX,
      y: centerY,
      radius: expectedRadius,
    );
    for (
      var dy = -maximumCenterSearchPixels;
      dy <= maximumCenterSearchPixels;
      dy++
    ) {
      for (
        var dx = -maximumCenterSearchPixels;
        dx <= maximumCenterSearchPixels;
        dx++
      ) {
        for (final scale in const [0.8, 0.9, 1.0, 1.1, 1.2]) {
          final radius = expectedRadius * scale;
          final sample = _ringContrast(
            image,
            centerX + dx,
            centerY + dy,
            radius,
          );
          final displacement = math.sqrt(dx * dx + dy * dy);
          final bestDisplacement = math.sqrt(
            math.pow(best.x - centerX, 2) + math.pow(best.y - centerY, 2),
          );
          if (sample.contrast > best.contrast ||
              (sample.contrast == best.contrast &&
                  displacement < bestDisplacement)) {
            best = (
              contrast: sample.contrast,
              coverage: sample.coverage,
              x: centerX + dx,
              y: centerY + dy,
              radius: radius,
            );
          }
        }
      }
    }
    final displacement = math.sqrt(
      math.pow(best.x - centerX, 2) + math.pow(best.y - centerY, 2),
    );
    return BubbleOutlineObservation(
      questionId: bubble.questionId.value,
      targetLabel:
          bubble.optionId?.value ??
          '${bubble.numericColumnIndex}:${bubble.numericDigitValue}',
      expectedCenterX: centerX,
      expectedCenterY: centerY,
      observedCenterX: best.x,
      observedCenterY: best.y,
      expectedRadiusPixels: expectedRadius,
      observedRadiusPixels: best.radius,
      centerDisplacementPixels: displacement,
      ringContrast: best.contrast.isFinite ? best.contrast : 0,
      sampleCoverage: best.coverage,
      confident:
          best.coverage >= minimumSampleCoverage &&
          best.contrast >= minimumRingContrast,
    );
  }

  ({double contrast, double coverage}) _ringContrast(
    CanonicalPageImage image,
    double x,
    double y,
    double radius,
  ) {
    const count = 48;
    var valid = 0;
    var ring = 0.0;
    var outside = 0.0;
    final outsideRadius = radius + math.max(2, radius * 0.28);
    for (var index = 0; index < count; index++) {
      final angle = 2 * math.pi * index / count;
      final ox = (x + math.cos(angle) * outsideRadius).round();
      final oy = (y + math.sin(angle) * outsideRadius).round();
      if (!_inside(image, ox, oy)) continue;
      var ringIntensity = 255;
      var ringFound = false;
      for (final radialOffset in const [-1.5, -0.75, 0.0, 0.75, 1.5]) {
        final sampleRadius = radius + radialOffset;
        final rx = (x + math.cos(angle) * sampleRadius).round();
        final ry = (y + math.sin(angle) * sampleRadius).round();
        if (!_inside(image, rx, ry)) continue;
        ringFound = true;
        ringIntensity = math.min(
          ringIntensity,
          image.grayscaleBytes[ry * image.size.width + rx],
        );
      }
      if (!ringFound) continue;
      valid++;
      ring += ringIntensity;
      outside += image.grayscaleBytes[oy * image.size.width + ox];
    }
    if (valid == 0) return (contrast: 0, coverage: 0);
    return (contrast: outside / valid - ring / valid, coverage: valid / count);
  }

  bool _inside(CanonicalPageImage image, int x, int y) =>
      x >= 0 && y >= 0 && x < image.size.width && y < image.size.height;

  static double _mean(Iterable<double> values) {
    final list = values.toList();
    return list.reduce((a, b) => a + b) / list.length;
  }

  static Map<String, double> _regional(
    List<BubbleOutlineObservation> values,
    int height,
  ) {
    final groups = <String, List<double>>{
      'top': [],
      'middle': [],
      'bottom': [],
    };
    for (final value in values) {
      final region = value.expectedCenterY < height / 3
          ? 'top'
          : value.expectedCenterY < height * 2 / 3
          ? 'middle'
          : 'bottom';
      groups[region]!.add(value.centerDisplacementPixels);
    }
    return {
      for (final entry in groups.entries)
        if (entry.value.isNotEmpty) entry.key: _mean(entry.value),
    };
  }
}
