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

      final measurements = <BubbleMeasurement>[];
      for (var index = 0; index < layout.bubbleRegions.length; index++) {
        final result = _measureBubble(
          bubble: layout.bubbleRegions[index],
          roi: rois[index],
          allRois: rois,
          ownIndex: index,
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
    required List<CanonicalBubbleRoi> allRois,
    required int ownIndex,
    required PreprocessedPage page,
    required BubbleMeasurementConfig config,
  }) {
    final width = page.size.width;
    final height = page.size.height;
    final grayscale = page.normalizedGrayscale.pixels;
    final binary = page.binary.pixels;
    final interiorValues = <int>[];
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
        interiorValues.add(grayscale[pixelIndex]);
        foregroundCount += binary[pixelIndex];
      }
    }
    final interiorRatio = interiorExpected == 0
        ? 0.0
        : interiorValues.length / interiorExpected;
    if (interiorValues.length < config.minimumInteriorPixels ||
        interiorRatio < config.minimumValidSampleRatio ||
        (!config.allowPartialClipping && interiorRatio < 1)) {
      return _bubbleFailure(
        'BUBBLE_MEASUREMENT_INSUFFICIENT_PIXELS',
        'Bubble interior does not contain enough valid canonical pixels.',
        bubble,
        {
          'sampleCount': interiorValues.length,
          'expectedCount': interiorExpected,
          'validSampleRatio': interiorRatio,
        },
      );
    }

    final baselineValues = <int>[];
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
            _insideOtherBubble(x, y, allRois, ownIndex)) {
          neighborMasked++;
          continue;
        }
        final pixelIndex = y * width + x;
        final isForeground = binary[pixelIndex] == 1;
        if (isForeground) baselineForeground++;
        if (config.excludeBaselineForeground && isForeground) continue;
        baselineValues.add(grayscale[pixelIndex]);
      }
    }
    final baselineValidRatio = baselineExpected == 0
        ? 0.0
        : baselineValid / baselineExpected;
    if (baselineValues.length < config.minimumBaselinePixels ||
        baselineValidRatio < config.minimumValidSampleRatio ||
        (!config.allowPartialClipping && baselineValidRatio < 1)) {
      return _bubbleFailure(
        'BUBBLE_MEASUREMENT_BASELINE_INVALID',
        'Bubble baseline does not contain enough valid paper samples.',
        bubble,
        {
          'sampleCount': baselineValues.length,
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
    final interiorMean = _mean(interiorValues);
    final interiorMedian = _percentile(interiorValues, 0.5);
    final baseline = _percentile(baselineValues, config.baselinePercentile);
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
        sampledInteriorPixelCount: interiorValues.length,
        sampledBaselinePixelCount: baselineValues.length,
        interiorMeanIntensity: interiorMean,
        interiorMedianIntensity: interiorMedian,
        localBaselineIntensity: baseline,
        darknessContrast: darkness,
        normalizedDarkness: normalizedDarkness,
        foregroundPixelCount: foregroundCount,
        fillRatio: foregroundCount / interiorValues.length,
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

  bool _insideOtherBubble(
    int x,
    int y,
    List<CanonicalBubbleRoi> rois,
    int ownIndex,
  ) {
    for (var index = 0; index < rois.length; index++) {
      if (index != ownIndex && rois[index].containsPrintedPixel(x, y)) {
        return true;
      }
    }
    return false;
  }

  bool _insideImage(int x, int y, int width, int height) =>
      x >= 0 && x < width && y >= 0 && y < height;

  double _mean(List<int> values) =>
      values.fold<int>(0, (sum, value) => sum + value) / values.length;

  double _percentile(List<int> values, double percentile) {
    final sorted = List<int>.of(values)..sort();
    final position = percentile * (sorted.length - 1);
    final lower = position.floor();
    final upper = position.ceil();
    if (lower == upper) return sorted[lower].toDouble();
    final fraction = position - lower;
    return sorted[lower] * (1 - fraction) + sorted[upper] * fraction;
  }

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
