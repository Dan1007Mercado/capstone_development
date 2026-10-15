import 'dart:typed_data';

import 'package:image/image.dart' as image;

import '../engines/aruco/domain/image_geometry.dart';
import '../engines/aruco/domain/page_alignment_result.dart';
import '../engines/layout/domain/layout_regions.dart';
import '../engines/layout/domain/page_layout.dart';

const p11KnownOptionAnswers = <String, Set<String>>{
  'q1': {'q1-4'},
  'q2': {'q2-2'},
  'q3': {},
  'q4': {'q4-2'},
  'q5': {'q5-1', 'q5-3'},
  'q6': {'q6-1', 'q6-3', 'q6-5'},
  'q7': {},
  'q8': {'q8-yes'},
  'q9': {'q9-no'},
};

const p11KnownNumericAnswers = <String, Map<int, int>>{
  'q10': {0: 4, 1: 2, 2: 7},
};

CanonicalPageImage renderP11KnownAnswerPage(PageLayout page) {
  final width = page.canonicalPageSpec.widthPixels;
  final height = page.canonicalPageSpec.heightPixels;
  final canvas = image.Image(width: width, height: height, numChannels: 1);
  final paper = image.ColorUint8.fromList(const [245]);
  final ink = image.ColorUint8.fromList(const [20]);
  image.fill(canvas, color: paper);
  for (final bubble in page.bubbleRegions) {
    final centerX = (bubble.normalizedCenter.x.value * width).round();
    final centerY = (bubble.normalizedCenter.y.value * height).round();
    final radius = (bubble.normalizedBounds.width.value * width / 2).round();
    image.fillCircle(
      canvas,
      x: centerX,
      y: centerY,
      radius: radius,
      color: ink,
    );
    image.fillCircle(
      canvas,
      x: centerX,
      y: centerY,
      radius: radius - 1,
      color: paper,
    );
    if (_isFilled(bubble)) {
      image.fillCircle(
        canvas,
        x: centerX,
        y: centerY,
        radius: (radius * 0.65).round(),
        color: ink,
      );
    }
  }
  return CanonicalPageImage.ownedGrayscale(
    size: ImageSize(width: width, height: height),
    grayscaleBytes: Uint8List.fromList(canvas.getBytes()),
  );
}

bool _isFilled(BubbleRegion bubble) {
  final optionId = bubble.optionId?.value;
  if (optionId != null) {
    return p11KnownOptionAnswers[bubble.questionId.value]?.contains(optionId) ??
        false;
  }
  final digits = p11KnownNumericAnswers[bubble.questionId.value];
  return digits?[bubble.numericColumnIndex] == bubble.numericDigitValue;
}
