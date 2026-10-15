import 'dart:math' as math;

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../aruco/domain/image_geometry.dart';
import '../../layout/domain/layout_regions.dart';
import '../../layout/domain/page_layout.dart';
import '../../preprocessing/domain/preprocessed_page.dart';
import '../domain/bubble_measurement.dart';
import '../domain/bubble_measurement_config.dart';
import '../domain/canonical_bubble_roi.dart';
import 'canonical_bubble_mapper.dart';
import 'grayscale_sample_histogram.dart';

final class BubbleMeasurementEngine {
  const BubbleMeasurementEngine({this.mapper = const CanonicalBubbleMapper()});

  final CanonicalBubbleMapper mapper;

  EngineResult<BubbleMeasurementSet> measure(
    PageLayout layout,
    PreprocessedPage page, [
    BubbleMeasurementConfig config = const BubbleMeasurementConfig(),
  ]) {
    final configError = config.validationMessage();
    if (configError != null) {
      return _failure('BUBBLE_MEASUREMENT_INVALID_CONFIG', configError);
    }
    final expectedSize = ImageSize(
      width: layout.canonicalPageSpec.widthPixels,
      height: layout.canonicalPageSpec.heightPixels,
    );
    if (page.size != expectedSize ||
        page.grayscale.size != expectedSize ||
        page.normalizedGrayscale.size != expectedSize ||
        page.binary.size != expectedSize) {
      return _failure(
        'BUBBLE_MEASUREMENT_SIZE_MISMATCH',
        'Preprocessed buffers must match the PageLayout canonical size.',
        {
          'pageId': layout.pageId.value,
          'expectedWidth': expectedSize.width,
          'expectedHeight': expectedSize.height,
          'actualWidth': page.size.width,
          'actualHeight': page.size.height,
        },
      );
    }

    try {
      final rois = <CanonicalBubbleRoi>[];
      for (final bubble in layout.bubbleRegions) {
        final identityValid =
            bubble.isOptionTarget != bubble.isNumericCellTarget;
        if (bubble.pageId != layout.pageId || !identityValid) {
          return _bubbleFailure(
            'BUBBLE_MEASUREMENT_INVALID_LAYOUT',
            'Bubble identity is inconsistent with its PageLayout.',
            bubble,
          );
        }
        final roi = mapper.map(bubble, layout, config);
        if (!_validRoi(roi, expectedSize)) {
          return _bubbleFailure(
            'BUBBLE_MEASUREMENT_ROI_INVALID',
            'Bubble geometry did not map to a valid canonical ROI.',
            bubble,
          );
        }
        rois.add(roi);
      }

      final baselineNeighbors = _baselineNeighbors(rois);
      final measurements = <BubbleMeasurement>[];
      for (var index = 0; index < layout.bubbleRegions.length; index++) {
        final result = _measureBubble(
          bubble: layout.bubbleRegions[index],
          roi: rois[index],
          baselineNeighbors: baselineNeighbors[index],
          page: page,
          config: config,
        );
        if (result.isFailure) return EngineResult.failure(result.error);
        measurements.add(result.value);
      }
      return EngineResult.success(
        BubbleMeasurementSet(pageId: layout.pageId, measurements: measurements),
      );
    } on Object catch (error) {
      return _failure(
        'BUBBLE_MEASUREMENT_FAILED',
        'Bubble measurement failed unexpectedly.',
        {'pageId': layout.pageId.value, 'cause': error.toString()},
      );
    }
  }

  EngineResult<BubbleMeasurement> _measureBubble({
    required BubbleRegion bubble,
    required CanonicalBubbleRoi roi,
    required List<CanonicalBubbleRoi> baselineNeighbors,
    required PreprocessedPage page,
    required BubbleMeasurementConfig config,
  }) {
    final width = page.size.width;
    final height = page.size.height;
    final grayscale = page.normalizedGrayscale.pixels;
    final binary = page.binary.pixels;
    final interiorSamples = GrayscaleSampleHistogram();
    var interiorExpected = 0;
    var foregroundCount = 0;
    final interiorRadius = roi.interiorRadius;
    final interiorLeft = (roi.center.x - interiorRadius - 1).floor();
    final interiorRight = (roi.center.x + interiorRadius + 1).ceil();
    final interiorTop = (roi.center.y - interiorRadius - 1).floor();
    final interiorBottom = (roi.center.y + interiorRadius + 1).ceil();
    for (var y = interiorTop; y <= interiorBottom; y++) {
      for (var x = interiorLeft; x <= interiorRight; x++) {
        if (!roi.containsInteriorPixel(x, y)) continue;
        interiorExpected++;
        if (!_insideImage(x, y, width, height)) continue;
        final pixelIndex = y * width + x;
        interiorSamples.add(grayscale[pixelIndex]);
        foregroundCount += binary[pixelIndex];
      }
    }
    final interiorRatio = interiorExpected == 0
        ? 0.0
        : interiorSamples.count / interiorExpected;
    if (interiorSamples.count < config.minimumInteriorPixels ||
        interiorRatio < config.minimumValidSampleRatio ||
        (!config.allowPartialClipping && interiorRatio < 1)) {
      return _bubbleFailure(
        'BUBBLE_MEASUREMENT_INSUFFICIENT_PIXELS',
        'Bubble interior does not contain enough valid canonical pixels.',
        bubble,
        {
          'sampleCount': interiorSamples.count,
          'expectedCount': interiorExpected,
          'validSampleRatio': interiorRatio,
        },
      );
    }

    final baselineSamples = GrayscaleSampleHistogram();
    var baselineExpected = 0;
    var baselineValid = 0;
    var baselineForeground = 0;
    var neighborMasked = 0;
    final outer = roi.baselineOuterRadius;
    final baselineLeft = (roi.center.x - outer - 1).floor();
    final baselineRight = (roi.center.x + outer + 1).ceil();
    final baselineTop = (roi.center.y - outer - 1).floor();
    final baselineBottom = (roi.center.y + outer + 1).ceil();
    for (var y = baselineTop; y <= baselineBottom; y++) {
      for (var x = baselineLeft; x <= baselineRight; x++) {
        if (!roi.containsBaselinePixel(x, y)) continue;
        baselineExpected++;
        if (!_insideImage(x, y, width, height)) continue;
        baselineValid++;
        if (config.excludeNeighborBubbles &&
            _insideNeighborBubble(x, y, baselineNeighbors)) {
          neighborMasked++;
          continue;
        }
        final pixelIndex = y * width + x;
        final isForeground = binary[pixelIndex] == 1;
        if (isForeground) baselineForeground++;
        if (config.excludeBaselineForeground && isForeground) continue;
        baselineSamples.add(grayscale[pixelIndex]);
      }
    }
    final baselineValidRatio = baselineExpected == 0
        ? 0.0
        : baselineValid / baselineExpected;
    if (baselineSamples.count < config.minimumBaselinePixels ||
        baselineValidRatio < config.minimumValidSampleRatio ||
        (!config.allowPartialClipping && baselineValidRatio < 1)) {
      return _bubbleFailure(
        'BUBBLE_MEASUREMENT_BASELINE_INVALID',
        'Bubble baseline does not contain enough valid paper samples.',
        bubble,
        {
          'sampleCount': baselineSamples.count,
          'expectedCount': baselineExpected,
          'validSampleRatio': baselineValidRatio,
          'neighborMaskedPixelCount': neighborMasked,
        },
      );
    }

    final baselineCandidateCount = baselineValid - neighborMasked;
    final baselineForegroundRatio = baselineCandidateCount == 0
        ? 1.0
        : baselineForeground / baselineCandidateCount;
    final interiorMean = interiorSamples.mean;
    final interiorMedian = interiorSamples.percentile(0.5);
    final baseline = baselineSamples.percentile(config.baselinePercentile);
    final darkness = baseline - interiorMean;
    final normalizedDarkness = darkness / math.max(baseline, config.epsilon);
    final clipped = interiorRatio < 1 || baselineValidRatio < 1;
    return EngineResult.success(
      BubbleMeasurement(
        pageId: bubble.pageId,
        questionId: bubble.questionId,
        optionId: bubble.optionId,
        numericColumnIndex: bubble.numericColumnIndex,
        numericDigitValue: bubble.numericDigitValue,
        roi: roi,
        sampledInteriorPixelCount: interiorSamples.count,
        sampledBaselinePixelCount: baselineSamples.count,
        interiorMeanIntensity: interiorMean,
        interiorMedianIntensity: interiorMedian,
        localBaselineIntensity: baseline,
        darknessContrast: darkness,
        normalizedDarkness: normalizedDarkness,
        foregroundPixelCount: foregroundCount,
        fillRatio: foregroundCount / interiorSamples.count,
        quality: BubbleMeasurementQuality(
          interiorValidSampleRatio: interiorRatio,
          baselineValidSampleRatio: baselineValidRatio,
          clipping: clipped
              ? BubbleRoiClipping.partial
              : BubbleRoiClipping.none,
          baselineForegroundRatio: baselineForegroundRatio,
          localBaselineReliable:
              baselineForegroundRatio <= config.maximumBaselineForegroundRatio,
          neighborMaskedPixelCount: neighborMasked,
        ),
      ),
    );
  }

  bool _validRoi(CanonicalBubbleRoi roi, ImageSize size) =>
      roi.center.x >= 0 &&
      roi.center.x < size.width &&
      roi.center.y >= 0 &&
      roi.center.y < size.height &&
      roi.printedRadius.isFinite &&
      roi.printedRadius > 0 &&
      roi.interiorRadius.isFinite &&
      roi.interiorRadius > 0 &&
      roi.baselineOuterRadius.isFinite;

  List<List<CanonicalBubbleRoi>> _baselineNeighbors(
    List<CanonicalBubbleRoi> rois,
  ) {
    final neighbors = List.generate(rois.length, (_) => <CanonicalBubbleRoi>[]);
    for (var ownIndex = 0; ownIndex < rois.length; ownIndex++) {
      final own = rois[ownIndex];
      for (
        var candidateIndex = 0;
        candidateIndex < rois.length;
        candidateIndex++
      ) {
        if (candidateIndex == ownIndex) continue;
        final candidate = rois[candidateIndex];
        if (own.center.distanceTo(candidate.center) <=
            own.baselineOuterRadius + candidate.printedRadius) {
          neighbors[ownIndex].add(candidate);
        }
      }
    }
    return neighbors;
  }

  bool _insideNeighborBubble(int x, int y, List<CanonicalBubbleRoi> neighbors) {
    for (final roi in neighbors) {
      if (roi.containsPrintedPixel(x, y)) return true;
    }
    return false;
  }

  bool _insideImage(int x, int y, int width, int height) =>
      x >= 0 && x < width && y >= 0 && y < height;

  EngineResult<T> _bubbleFailure<T>(
    String code,
    String message,
    BubbleRegion bubble, [
    Map<String, Object?> extra = const {},
  ]) => EngineResult.failure(
    EngineError(
      code: code,
      message: message,
      details: {
        'pageId': bubble.pageId.value,
        'questionId': bubble.questionId.value,
        if (bubble.optionId != null) 'optionId': bubble.optionId!.value,
        if (bubble.numericColumnIndex != null)
          'numericColumnIndex': bubble.numericColumnIndex,
        if (bubble.numericDigitValue != null)
          'numericDigitValue': bubble.numericDigitValue,
        'bubbleBounds': bubble.physicalBounds.toString(),
        ...extra,
      },
    ),
  );

  EngineResult<T> _failure<T>(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );
}
