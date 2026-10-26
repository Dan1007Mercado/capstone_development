import 'dart:math' as math;
import 'dart:typed_data';

import 'package:capstone_development/debug/p5_native_validation_fixture.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/recognition/application/bubble_alignment_evidence.dart';
import 'package:capstone_development/engines/recognition/application/bubble_alignment_ground_truth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'printed bubble rings provide independent alignment evidence despite fills',
    () {
      final page = buildP5NativeValidationPage();
      final width = page.canonicalPageSpec.widthPixels;
      final height = page.canonicalPageSpec.heightPixels;
      final pixels = Uint8List(width * height)
        ..fillRange(0, width * height, 255);
      for (var index = 0; index < page.bubbleRegions.length; index++) {
        final bubble = page.bubbleRegions[index];
        final x = bubble.normalizedCenter.x.value * width;
        final y = bubble.normalizedCenter.y.value * height;
        final radius =
            bubble.physicalDiameter.millimeters /
            page.pageSpec.size.width.millimeters *
            width /
            2;
        final bound = radius.ceil() + 2;
        for (var dy = -bound; dy <= bound; dy++) {
          for (var dx = -bound; dx <= bound; dx++) {
            final distance = math.sqrt(dx * dx + dy * dy);
            if ((distance - radius).abs() <= 1.4 ||
                (index.isEven && distance < radius * 0.65)) {
              final px = (x + dx).round();
              final py = (y + dy).round();
              if (px >= 0 && py >= 0 && px < width && py < height) {
                pixels[py * width + px] = 0;
              }
            }
          }
        }
      }

      final evidence = const BubbleAlignmentEvidenceEvaluator().evaluate(
        CanonicalPageImage.ownedGrayscale(
          size: ImageSize(width: width, height: height),
          grayscaleBytes: pixels,
        ),
        page,
      );

      expect(evidence.status, BubbleAlignmentEvidenceStatus.measured);
      expect(evidence.observedCoverage, greaterThan(0.8));
      expect(evidence.meanCenterDisplacementPixels, lessThan(2));
      expect(evidence.meanRingContrast, greaterThan(20));
    },
  );

  test('blank image is explicitly inconclusive instead of passing', () {
    final page = buildP5NativeValidationPage();
    final size = ImageSize(
      width: page.canonicalPageSpec.widthPixels,
      height: page.canonicalPageSpec.heightPixels,
    );
    final evidence = const BubbleAlignmentEvidenceEvaluator().evaluate(
      CanonicalPageImage.ownedGrayscale(
        size: size,
        grayscaleBytes: Uint8List(size.area)..fillRange(0, size.area, 255),
      ),
      page,
    );

    expect(evidence.status, BubbleAlignmentEvidenceStatus.inconclusive);
    expect(
      evidence.inconclusiveReason,
      'INSUFFICIENT_PRINTED_OUTLINE_EVIDENCE',
    );
  });

  test('annotated source landmarks independently measure homography error', () {
    final page = buildP5NativeValidationPage();
    final annotations = [
      for (final bubble in page.bubbleRegions)
        BubbleGroundTruthAnnotation(
          questionId: bubble.questionId.value,
          targetLabel:
              bubble.optionId?.value ??
              '${bubble.numericColumnIndex}:${bubble.numericDigitValue}',
          sourceCenter: ImagePoint(
            bubble.normalizedCenter.x.value *
                page.canonicalPageSpec.widthPixels,
            bubble.normalizedCenter.y.value *
                page.canonicalPageSpec.heightPixels,
          ),
        ),
    ];

    final exact = const BubbleAlignmentGroundTruthEvaluator().evaluate(
      page: page,
      homography: HomographyMatrix([1, 0, 0, 0, 1, 0, 0, 0, 1]),
      annotations: annotations,
    );
    final shifted = const BubbleAlignmentGroundTruthEvaluator().evaluate(
      page: page,
      homography: HomographyMatrix([1, 0, 3, 0, 1, 4, 0, 0, 1]),
      annotations: annotations,
    );

    expect(exact.complete, isTrue);
    expect(exact.maximum, closeTo(0, 1e-9));
    expect(shifted.mean, closeTo(5, 1e-9));
    expect(shifted.median, closeTo(5, 1e-9));
    expect(shifted.percentile95, closeTo(5, 1e-9));
    expect(shifted.maximum, closeTo(5, 1e-9));
    expect(
      shifted.regionalMeanDisplacementPixels.values,
      everyElement(closeTo(5, 1e-9)),
    );
  });
}
