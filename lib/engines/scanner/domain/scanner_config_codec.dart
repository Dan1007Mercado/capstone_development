import '../../aruco/domain/aruco_alignment_config.dart';
import '../../../core/protocol/aruco_dictionary.dart';
import '../../preprocessing/domain/preprocessing_config.dart';
import '../../recognition/domain/bubble_measurement_config.dart';
import '../../recognition/domain/mark_classification_config.dart';
import 'scanner_config.dart';

/// Lossless, versioned serialization for the tunable scanner configuration.
final class ScannerConfigCodec {
  const ScannerConfigCodec();

  static const int schemaVersion = 1;

  Map<String, Object?> encode(ScannerConfig value) => {
    'schemaVersion': schemaVersion,
    'alignment': _alignment(value.alignment),
    'preprocessing': _preprocessing(value.preprocessing),
    'measurement': _measurement(value.measurement),
    'classification': _classification(value.classification),
    'requiredQuestionPolicy': value.requiredQuestionPolicy.name,
  };

  ScannerConfig decode(Map<String, Object?> value) {
    if (value['schemaVersion'] != schemaVersion) {
      throw FormatException(
        'Unsupported scanner config schema: ${value['schemaVersion']}',
      );
    }
    final a = _map(value, 'alignment');
    final p = _map(value, 'preprocessing');
    final m = _map(value, 'measurement');
    final c = _map(value, 'classification');
    return ScannerConfig(
      alignment: ArucoAlignmentConfig(
        dictionary: ArucoDictionary.values.byName(_string(a, 'dictionary')),
        minimumMarkerSidePixels: _double(a, 'minimumMarkerSidePixels'),
        minimumRegistrationAreaRatio: _double(a, 'minimumRegistrationAreaRatio'),
        minimumRegistrationSpacingPixels: _double(a, 'minimumRegistrationSpacingPixels'),
        maximumExtremePerspectiveRatio: _double(a, 'maximumExtremePerspectiveRatio'),
        maximumReprojectionErrorPixels: _double(a, 'maximumReprojectionErrorPixels'),
        maximumRejectedCornerErrorPixels: _double(a, 'maximumRejectedCornerErrorPixels'),
        maximumLocalizationScaleFactor: _double(a, 'maximumLocalizationScaleFactor'),
        multipointRansacReprojectionThresholdPixels: _double(a, 'multipointRansacReprojectionThresholdPixels'),
        minimumMultipointInlierRatio: _double(a, 'minimumMultipointInlierRatio'),
        maximumLocalScaleRatio: _double(a, 'maximumLocalScaleRatio'),
        maximumLocalAnisotropyRatio: _double(a, 'maximumLocalAnisotropyRatio'),
        maximumPageBoundaryOvershootRatio: _double(a, 'maximumPageBoundaryOvershootRatio'),
        multipointMaximumIterations: _int(a, 'multipointMaximumIterations'),
        multipointConfidence: _double(a, 'multipointConfidence'),
        enableMultipointHomography: _bool(a, 'enableMultipointHomography'),
        selectionPolicy: HomographySelectionPolicy.values.byName(_string(a, 'selectionPolicy')),
        allowAdditionalUnrelatedMarkers: _bool(a, 'allowAdditionalUnrelatedMarkers'),
        finalMarkerDetectionMaxDimension: (a['finalMarkerDetectionMaxDimension'] as num?)?.toInt(),
      ),
      preprocessing: PreprocessingConfig(
        enableIlluminationNormalization: _bool(p, 'enableIlluminationNormalization'),
        backgroundKernelSize: _int(p, 'backgroundKernelSize'),
        enableDenoise: _bool(p, 'enableDenoise'),
        denoiseKernelSize: _int(p, 'denoiseKernelSize'),
        adaptiveThresholdBlockSize: _int(p, 'adaptiveThresholdBlockSize'),
        adaptiveThresholdC: _double(p, 'adaptiveThresholdC'),
        minimumIntensityStdDev: _double(p, 'minimumIntensityStdDev'),
        darkPixelThreshold: _int(p, 'darkPixelThreshold'),
        brightPixelThreshold: _int(p, 'brightPixelThreshold'),
      ),
      measurement: BubbleMeasurementConfig(
        interiorRadiusRatio: _double(m, 'interiorRadiusRatio'),
        baselineInnerRadiusRatio: _double(m, 'baselineInnerRadiusRatio'),
        baselineOuterRadiusRatio: _double(m, 'baselineOuterRadiusRatio'),
        minimumInteriorPixels: _int(m, 'minimumInteriorPixels'),
        minimumBaselinePixels: _int(m, 'minimumBaselinePixels'),
        minimumValidSampleRatio: _double(m, 'minimumValidSampleRatio'),
        allowPartialClipping: _bool(m, 'allowPartialClipping'),
        excludeBaselineForeground: _bool(m, 'excludeBaselineForeground'),
        excludeNeighborBubbles: _bool(m, 'excludeNeighborBubbles'),
        baselinePercentile: _double(m, 'baselinePercentile'),
        maximumBaselineForegroundRatio: _double(m, 'maximumBaselineForegroundRatio'),
        distributionGridSize: _int(m, 'distributionGridSize'),
        distributionCellMinimumFillRatio: _double(m, 'distributionCellMinimumFillRatio'),
        epsilon: _double(m, 'epsilon'),
      ),
      classification: MarkClassificationConfig(
        minimumMarkCoverage: _double(c, 'minimumMarkCoverage'),
        strongMarkCoverage: _double(c, 'strongMarkCoverage'),
        blankMaximumCoverage: _double(c, 'blankMaximumCoverage'),
        minimumNormalizedDarkness: _double(c, 'minimumNormalizedDarkness'),
        strongNormalizedDarkness: _double(c, 'strongNormalizedDarkness'),
        minimumDarknessContrast: _double(c, 'minimumDarknessContrast'),
        strongDarknessContrast: _double(c, 'strongDarknessContrast'),
        minimumDarknessEvidence: _double(c, 'minimumDarknessEvidence'),
        normalizedDarknessShare: _double(c, 'normalizedDarknessShare'),
        coverageWeight: _double(c, 'coverageWeight'),
        darknessWeight: _double(c, 'darknessWeight'),
        distributionWeight: _double(c, 'distributionWeight'),
        minimumDistributedMarkScore: _double(c, 'minimumDistributedMarkScore'),
        minimumCombinedMarkScore: _double(c, 'minimumCombinedMarkScore'),
        strongCombinedMarkScore: _double(c, 'strongCombinedMarkScore'),
        minimumTopSecondScoreGap: _double(c, 'minimumTopSecondScoreGap'),
        coverageDominanceRatio: _double(c, 'coverageDominanceRatio'),
        coverageDominanceGap: _double(c, 'coverageDominanceGap'),
        multipleMarkMinimumCoverage: _double(c, 'multipleMarkMinimumCoverage'),
        multipleMarkMinimumConfidence: _double(c, 'multipleMarkMinimumConfidence'),
        maximumBaselineForegroundRatio: _double(c, 'maximumBaselineForegroundRatio'),
        severeBaselineForegroundRatio: _double(c, 'severeBaselineForegroundRatio'),
        requireReliableBaseline: _bool(c, 'requireReliableBaseline'),
        minimumValidSampleRatio: _double(c, 'minimumValidSampleRatio'),
        severeMinimumValidSampleRatio: _double(c, 'severeMinimumValidSampleRatio'),
        epsilon: _double(c, 'epsilon'),
      ),
      requiredQuestionPolicy: RequiredQuestionPolicy.values.byName(
        _string(value, 'requiredQuestionPolicy'),
      ),
    );
  }

  static Map<String, Object?> _alignment(ArucoAlignmentConfig v) => {
    'dictionary': v.dictionary.name,
    'minimumMarkerSidePixels': v.minimumMarkerSidePixels,
    'minimumRegistrationAreaRatio': v.minimumRegistrationAreaRatio,
    'minimumRegistrationSpacingPixels': v.minimumRegistrationSpacingPixels,
    'maximumExtremePerspectiveRatio': v.maximumExtremePerspectiveRatio,
    'maximumReprojectionErrorPixels': v.maximumReprojectionErrorPixels,
    'maximumRejectedCornerErrorPixels': v.maximumRejectedCornerErrorPixels,
    'maximumLocalizationScaleFactor': v.maximumLocalizationScaleFactor,
    'multipointRansacReprojectionThresholdPixels': v.multipointRansacReprojectionThresholdPixels,
    'minimumMultipointInlierRatio': v.minimumMultipointInlierRatio,
    'maximumLocalScaleRatio': v.maximumLocalScaleRatio,
    'maximumLocalAnisotropyRatio': v.maximumLocalAnisotropyRatio,
    'maximumPageBoundaryOvershootRatio': v.maximumPageBoundaryOvershootRatio,
    'multipointMaximumIterations': v.multipointMaximumIterations,
    'multipointConfidence': v.multipointConfidence,
    'enableMultipointHomography': v.enableMultipointHomography,
    'selectionPolicy': v.selectionPolicy.name,
    'allowAdditionalUnrelatedMarkers': v.allowAdditionalUnrelatedMarkers,
    'finalMarkerDetectionMaxDimension': v.finalMarkerDetectionMaxDimension,
  };

  static Map<String, Object?> _preprocessing(PreprocessingConfig v) => {
    'enableIlluminationNormalization': v.enableIlluminationNormalization,
    'backgroundKernelSize': v.backgroundKernelSize,
    'enableDenoise': v.enableDenoise,
    'denoiseKernelSize': v.denoiseKernelSize,
    'adaptiveThresholdBlockSize': v.adaptiveThresholdBlockSize,
    'adaptiveThresholdC': v.adaptiveThresholdC,
    'minimumIntensityStdDev': v.minimumIntensityStdDev,
    'darkPixelThreshold': v.darkPixelThreshold,
    'brightPixelThreshold': v.brightPixelThreshold,
  };

  static Map<String, Object?> _measurement(BubbleMeasurementConfig v) => {
    'interiorRadiusRatio': v.interiorRadiusRatio,
    'baselineInnerRadiusRatio': v.baselineInnerRadiusRatio,
    'baselineOuterRadiusRatio': v.baselineOuterRadiusRatio,
    'minimumInteriorPixels': v.minimumInteriorPixels,
    'minimumBaselinePixels': v.minimumBaselinePixels,
    'minimumValidSampleRatio': v.minimumValidSampleRatio,
    'allowPartialClipping': v.allowPartialClipping,
    'excludeBaselineForeground': v.excludeBaselineForeground,
    'excludeNeighborBubbles': v.excludeNeighborBubbles,
    'baselinePercentile': v.baselinePercentile,
    'maximumBaselineForegroundRatio': v.maximumBaselineForegroundRatio,
    'distributionGridSize': v.distributionGridSize,
    'distributionCellMinimumFillRatio': v.distributionCellMinimumFillRatio,
    'epsilon': v.epsilon,
  };

  static Map<String, Object?> _classification(MarkClassificationConfig v) => {
    'minimumMarkCoverage': v.minimumMarkCoverage,
    'strongMarkCoverage': v.strongMarkCoverage,
    'blankMaximumCoverage': v.blankMaximumCoverage,
    'minimumNormalizedDarkness': v.minimumNormalizedDarkness,
    'strongNormalizedDarkness': v.strongNormalizedDarkness,
    'minimumDarknessContrast': v.minimumDarknessContrast,
    'strongDarknessContrast': v.strongDarknessContrast,
    'minimumDarknessEvidence': v.minimumDarknessEvidence,
    'normalizedDarknessShare': v.normalizedDarknessShare,
    'coverageWeight': v.coverageWeight,
    'darknessWeight': v.darknessWeight,
    'distributionWeight': v.distributionWeight,
    'minimumDistributedMarkScore': v.minimumDistributedMarkScore,
    'minimumCombinedMarkScore': v.minimumCombinedMarkScore,
    'strongCombinedMarkScore': v.strongCombinedMarkScore,
    'minimumTopSecondScoreGap': v.minimumTopSecondScoreGap,
    'coverageDominanceRatio': v.coverageDominanceRatio,
    'coverageDominanceGap': v.coverageDominanceGap,
    'multipleMarkMinimumCoverage': v.multipleMarkMinimumCoverage,
    'multipleMarkMinimumConfidence': v.multipleMarkMinimumConfidence,
    'maximumBaselineForegroundRatio': v.maximumBaselineForegroundRatio,
    'severeBaselineForegroundRatio': v.severeBaselineForegroundRatio,
    'requireReliableBaseline': v.requireReliableBaseline,
    'minimumValidSampleRatio': v.minimumValidSampleRatio,
    'severeMinimumValidSampleRatio': v.severeMinimumValidSampleRatio,
    'epsilon': v.epsilon,
  };

  static Map<String, Object?> _map(Map<String, Object?> v, String key) =>
      (v[key] as Map).cast<String, Object?>();
  static String _string(Map<String, Object?> v, String key) => v[key] as String;
  static bool _bool(Map<String, Object?> v, String key) => v[key] as bool;
  static int _int(Map<String, Object?> v, String key) => (v[key] as num).toInt();
  static double _double(Map<String, Object?> v, String key) => (v[key] as num).toDouble();
}
