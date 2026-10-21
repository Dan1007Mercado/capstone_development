import 'dart:typed_data';

import '../../../core/ids/identifiers.dart';
import '../../aruco/domain/image_geometry.dart';
import '../../aruco/domain/page_alignment_result.dart';
import '../../preprocessing/domain/preprocessing_config.dart';
import '../../recognition/domain/bubble_measurement.dart';
import '../../recognition/domain/bubble_measurement_config.dart';
import '../../recognition/domain/mark_classification.dart';
import '../../recognition/domain/mark_classification_config.dart';
import 'scan_result.dart';

enum ScannerDiagnosticImageFormat { grayscale8, png }

typedef ScannerDiagnosticSink = void Function(ScannerDiagnosticSnapshot value);

/// Debug-only evidence captured from the exact production scanner stages.
///
/// This is created only when explicitly requested. Normal [ScanResult]
/// instances never retain canonical image buffers.
final class ScannerDiagnosticSnapshot {
  ScannerDiagnosticSnapshot({
    required this.templateId,
    required this.templateVersion,
    required this.pageId,
    required this.canonicalSize,
    required this.canonicalImageFormat,
    required Uint8List canonicalImageBytes,
    required this.homography,
    required this.measurements,
    required this.classification,
    required this.result,
    required this.preprocessingConfig,
    required this.measurementConfig,
    required this.classificationConfig,
    this.scanSequenceIndex = 0,
  }) : canonicalImageBytes = canonicalImageBytes.asUnmodifiableView();

  final TemplateId templateId;
  final TemplateVersion templateVersion;
  final PageId pageId;
  final ImageSize canonicalSize;
  final ScannerDiagnosticImageFormat canonicalImageFormat;
  final Uint8List canonicalImageBytes;
  final HomographyMatrix homography;
  final BubbleMeasurementSet measurements;
  final PageClassificationResult classification;
  final ScanResult result;
  final PreprocessingConfig preprocessingConfig;
  final BubbleMeasurementConfig measurementConfig;
  final MarkClassificationConfig classificationConfig;
  final int scanSequenceIndex;

  ScannerDiagnosticSnapshot withScanSequenceIndex(int value) =>
      ScannerDiagnosticSnapshot(
        templateId: templateId,
        templateVersion: templateVersion,
        pageId: pageId,
        canonicalSize: canonicalSize,
        canonicalImageFormat: canonicalImageFormat,
        canonicalImageBytes: canonicalImageBytes,
        homography: homography,
        measurements: measurements,
        classification: classification,
        result: result,
        preprocessingConfig: preprocessingConfig,
        measurementConfig: measurementConfig,
        classificationConfig: classificationConfig,
        scanSequenceIndex: value,
      );

  Map<String, Object?> toJson() {
    final decisions = {
      for (final question in classification.questions)
        for (final decision in question.bubbleDecisions)
          _identity(
            decision.questionId,
            decision.optionId,
            decision.numericColumnIndex,
            decision.numericDigitValue,
          ): (
            question,
            decision,
          ),
    };
    return {
      'templateId': templateId.value,
      'templateVersion': templateVersion.value,
      'pageId': pageId.value,
      'scanSequenceIndex': scanSequenceIndex,
      'detectedMarkerIds': result.diagnostics.alignment.detectedMarkerIds,
      'canonicalImage': {
        'width': canonicalSize.width,
        'height': canonicalSize.height,
        'format': canonicalImageFormat.name,
        'byteCount': canonicalImageBytes.length,
      },
      'homography': homography.values,
      'alignment': {
        'meanReprojectionError':
            result.diagnostics.alignment.meanReprojectionError,
        'maxReprojectionError':
            result.diagnostics.alignment.maxReprojectionError,
        'reprojectionErrors': result.diagnostics.alignment.reprojectionErrors,
      },
      'timingsMs': {
        'total': _milliseconds(result.diagnostics.totalProcessingDuration),
        'alignment': _milliseconds(result.diagnostics.stageDurations.alignment),
        'preprocessing': _milliseconds(
          result.diagnostics.stageDurations.preprocessing,
        ),
        'measurement': _milliseconds(
          result.diagnostics.stageDurations.measurement,
        ),
        'classification': _milliseconds(
          result.diagnostics.stageDurations.classification,
        ),
        'validation': _milliseconds(
          result.diagnostics.stageDurations.validation,
        ),
      },
      'preprocessingConfig': {
        'enableIlluminationNormalization':
            preprocessingConfig.enableIlluminationNormalization,
        'backgroundKernelSize': preprocessingConfig.backgroundKernelSize,
        'enableDenoise': preprocessingConfig.enableDenoise,
        'denoiseKernelSize': preprocessingConfig.denoiseKernelSize,
        'adaptiveThresholdBlockSize':
            preprocessingConfig.adaptiveThresholdBlockSize,
        'adaptiveThresholdC': preprocessingConfig.adaptiveThresholdC,
        'minimumIntensityStdDev': preprocessingConfig.minimumIntensityStdDev,
        'darkPixelThreshold': preprocessingConfig.darkPixelThreshold,
        'brightPixelThreshold': preprocessingConfig.brightPixelThreshold,
      },
      'measurementConfig': {
        'interiorRadiusRatio': measurementConfig.interiorRadiusRatio,
        'baselineInnerRadiusRatio':
            measurementConfig.baselineInnerRadiusRatio,
        'baselineOuterRadiusRatio':
            measurementConfig.baselineOuterRadiusRatio,
        'minimumInteriorPixels': measurementConfig.minimumInteriorPixels,
        'minimumBaselinePixels': measurementConfig.minimumBaselinePixels,
        'minimumValidSampleRatio': measurementConfig.minimumValidSampleRatio,
        'allowPartialClipping': measurementConfig.allowPartialClipping,
        'excludeBaselineForeground':
            measurementConfig.excludeBaselineForeground,
        'excludeNeighborBubbles': measurementConfig.excludeNeighborBubbles,
        'baselinePercentile': measurementConfig.baselinePercentile,
        'maximumBaselineForegroundRatio':
            measurementConfig.maximumBaselineForegroundRatio,
      },
      'classificationConfig': {
        'minimumFillRatio': classificationConfig.minimumFillRatio,
        'strongFillRatio': classificationConfig.strongFillRatio,
        'minimumNormalizedDarkness':
            classificationConfig.minimumNormalizedDarkness,
        'strongNormalizedDarkness':
            classificationConfig.strongNormalizedDarkness,
        'minimumDarknessContrast':
            classificationConfig.minimumDarknessContrast,
        'strongDarknessContrast':
            classificationConfig.strongDarknessContrast,
        'fillWeight': classificationConfig.fillWeight,
        'normalizedDarknessWeight':
            classificationConfig.normalizedDarknessWeight,
        'darknessContrastWeight':
            classificationConfig.darknessContrastWeight,
        'minimumCombinedScore': classificationConfig.minimumCombinedScore,
        'strongCombinedScore': classificationConfig.strongCombinedScore,
        'minimumTopSecondGap': classificationConfig.minimumTopSecondGap,
        'maximumBaselineForegroundRatio':
            classificationConfig.maximumBaselineForegroundRatio,
        'severeBaselineForegroundRatio':
            classificationConfig.severeBaselineForegroundRatio,
        'requireReliableBaseline':
            classificationConfig.requireReliableBaseline,
        'minimumValidSampleRatio':
            classificationConfig.minimumValidSampleRatio,
        'severeMinimumValidSampleRatio':
            classificationConfig.severeMinimumValidSampleRatio,
      },
      'bubbles': [
        for (final measurement in measurements.measurements)
          _measurementJson(measurement, decisions),
      ],
    };
  }

  Map<String, Object?> _measurementJson(
    BubbleMeasurement measurement,
    Map<String, (QuestionClassification, BubbleMarkDecision)> decisions,
  ) {
    final classified =
        decisions[_identity(
          measurement.questionId,
          measurement.optionId,
          measurement.numericColumnIndex,
          measurement.numericDigitValue,
        )];
    return {
      'questionId': measurement.questionId.value,
      'optionId': measurement.optionId?.value,
      'numericColumnIndex': measurement.numericColumnIndex,
      'numericDigitValue': measurement.numericDigitValue,
      'canonicalCenter': {
        'x': measurement.roi.center.x,
        'y': measurement.roi.center.y,
      },
      'printedRadius': measurement.roi.printedRadius,
      'interiorRadius': measurement.roi.interiorRadius,
      'baselineInnerRadius': measurement.roi.baselineInnerRadius,
      'baselineOuterRadius': measurement.roi.baselineOuterRadius,
      'fillRatio': measurement.fillRatio,
      'normalizedDarkness': measurement.normalizedDarkness,
      'darknessContrast': measurement.darknessContrast,
      'combinedScore': classified?.$2.combinedScore,
      'evidenceCategory': classified?.$2.category.name,
      'decisionState': classified?.$2.state.name,
      'questionState': classified?.$1.state.name,
      'interiorMeanIntensity': measurement.interiorMeanIntensity,
      'interiorMedianIntensity': measurement.interiorMedianIntensity,
      'localBaselineIntensity': measurement.localBaselineIntensity,
      'sampledInteriorPixelCount': measurement.sampledInteriorPixelCount,
      'sampledBaselinePixelCount': measurement.sampledBaselinePixelCount,
      'foregroundPixelCount': measurement.foregroundPixelCount,
      'clipping': measurement.quality.clipping.name,
      'baselineForegroundRatio': measurement.quality.baselineForegroundRatio,
      'localBaselineReliable': measurement.quality.localBaselineReliable,
      'interiorValidSampleRatio': measurement.quality.interiorValidSampleRatio,
      'baselineValidSampleRatio': measurement.quality.baselineValidSampleRatio,
      'neighborMaskedPixelCount': measurement.quality.neighborMaskedPixelCount,
    };
  }

  static String _identity(
    QuestionId questionId,
    OptionId? optionId,
    int? column,
    int? digit,
  ) => '${questionId.value}|${optionId?.value}|$column|$digit';

  static double _milliseconds(Duration duration) =>
      duration.inMicroseconds / Duration.microsecondsPerMillisecond;
}
