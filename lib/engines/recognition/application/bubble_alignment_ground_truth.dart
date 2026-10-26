import 'dart:collection';
import 'dart:math' as math;

import '../../aruco/domain/image_geometry.dart';
import '../../aruco/domain/page_alignment_result.dart';
import '../../layout/domain/layout_regions.dart';
import '../../layout/domain/page_layout.dart';

final class BubbleGroundTruthAnnotation {
  const BubbleGroundTruthAnnotation({
    required this.questionId,
    required this.targetLabel,
    required this.sourceCenter,
  });

  final String questionId;
  final String targetLabel;
  final ImagePoint sourceCenter;

  factory BubbleGroundTruthAnnotation.fromJson(Map<String, Object?> value) =>
      BubbleGroundTruthAnnotation(
        questionId: value['questionId'] as String,
        targetLabel: value['targetLabel'] as String,
        sourceCenter: ImagePoint(
          (value['sourceX'] as num).toDouble(),
          (value['sourceY'] as num).toDouble(),
        ),
      );

  Map<String, Object?> toJson() => {
    'questionId': questionId,
    'targetLabel': targetLabel,
    'sourceX': sourceCenter.x,
    'sourceY': sourceCenter.y,
  };
}

final class BubbleGroundTruthEvidence {
  BubbleGroundTruthEvidence({
    required this.complete,
    required Iterable<double> displacementPixels,
    required this.missingTargets,
    required Map<String, double> regionalMeanDisplacementPixels,
  }) : displacementPixels = UnmodifiableListView(List.of(displacementPixels)),
       regionalMeanDisplacementPixels = UnmodifiableMapView(
         Map.of(regionalMeanDisplacementPixels),
       );

  final bool complete;
  final List<double> displacementPixels;
  final int missingTargets;
  final Map<String, double> regionalMeanDisplacementPixels;

  double? get mean => displacementPixels.isEmpty
      ? null
      : displacementPixels.reduce((a, b) => a + b) / displacementPixels.length;
  double? get maximum =>
      displacementPixels.isEmpty ? null : displacementPixels.reduce(math.max);

  double? get median => _percentile(0.50);
  double? get percentile95 => _percentile(0.95);

  double? _percentile(double fraction) {
    if (displacementPixels.isEmpty) return null;
    final sorted = List<double>.of(displacementPixels)..sort();
    final index = ((sorted.length * fraction).ceil() - 1).clamp(
      0,
      sorted.length - 1,
    );
    return sorted[index];
  }
}

/// Evaluates manually annotated source-image bubble centers after a candidate
/// transform. These landmarks are independent of ArUco fitting observations.
final class BubbleAlignmentGroundTruthEvaluator {
  const BubbleAlignmentGroundTruthEvaluator();

  BubbleGroundTruthEvidence evaluate({
    required PageLayout page,
    required HomographyMatrix homography,
    required Iterable<BubbleGroundTruthAnnotation> annotations,
  }) {
    final byKey = {
      for (final annotation in annotations)
        '${annotation.questionId}/${annotation.targetLabel}': annotation,
    };
    final errors = <double>[];
    final regionalErrors = <String, List<double>>{
      'top': [],
      'middle': [],
      'bottom': [],
    };
    var missing = 0;
    for (final bubble in page.bubbleRegions) {
      final label = _label(bubble);
      final annotation = byKey['${bubble.questionId.value}/$label'];
      if (annotation == null) {
        missing++;
        continue;
      }
      final expected = ImagePoint(
        bubble.normalizedCenter.x.value * page.canonicalPageSpec.widthPixels,
        bubble.normalizedCenter.y.value * page.canonicalPageSpec.heightPixels,
      );
      try {
        final error = homography
            .project(annotation.sourceCenter)
            .distanceTo(expected);
        errors.add(error);
        final y = bubble.normalizedCenter.y.value;
        regionalErrors[y < 1 / 3
                ? 'top'
                : y < 2 / 3
                ? 'middle'
                : 'bottom']!
            .add(error);
      } on Object {
        errors.add(double.infinity);
      }
    }
    return BubbleGroundTruthEvidence(
      complete:
          missing == 0 && errors.isNotEmpty && errors.every((e) => e.isFinite),
      displacementPixels: errors,
      missingTargets: missing,
      regionalMeanDisplacementPixels: {
        for (final entry in regionalErrors.entries)
          if (entry.value.isNotEmpty)
            entry.key: entry.value.reduce((a, b) => a + b) / entry.value.length,
      },
    );
  }

  static String _label(BubbleRegion bubble) =>
      bubble.optionId?.value ??
      '${bubble.numericColumnIndex}:${bubble.numericDigitValue}';
}
