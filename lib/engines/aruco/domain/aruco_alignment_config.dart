import '../../../core/protocol/aruco_dictionary.dart';

enum HomographySelectionPolicy {
  /// Preserve the established four-point transform whenever it is safe.
  fourPointBaseline,

  /// Prefer a fully validated 16-point estimate when external ground-truth
  /// benchmarks have established that preference for the deployed backend.
  validatedMultiPointPreference,
}

/// Provisional deterministic thresholds for static-image registration.
final class ArucoAlignmentConfig {
  factory ArucoAlignmentConfig({
    ArucoDictionary dictionary = ArucoDictionary.openCv4x4_50,
    double minimumMarkerSidePixels = 12,
    double minimumRegistrationAreaRatio = 0.02,
    double minimumRegistrationSpacingPixels = 24,
    double maximumExtremePerspectiveRatio = 12,
    double maximumReprojectionErrorPixels = 1,
    double maximumRejectedCornerErrorPixels = 4,
    double maximumLocalizationScaleFactor = 4,
    double multipointRansacReprojectionThresholdPixels = 1.5,
    double minimumMultipointInlierRatio = 0.875,
    double maximumLocalScaleRatio = 20,
    double maximumLocalAnisotropyRatio = 12,
    double maximumPageBoundaryOvershootRatio = 0.15,
    int multipointMaximumIterations = 500,
    double multipointConfidence = 0.995,
    bool enableMultipointHomography = true,
    HomographySelectionPolicy selectionPolicy =
        HomographySelectionPolicy.validatedMultiPointPreference,
    bool allowAdditionalUnrelatedMarkers = true,
    int? finalMarkerDetectionMaxDimension = 1400,
  }) {
    final positive = [
      minimumMarkerSidePixels,
      minimumRegistrationAreaRatio,
      minimumRegistrationSpacingPixels,
      maximumExtremePerspectiveRatio,
      maximumReprojectionErrorPixels,
      maximumRejectedCornerErrorPixels,
      maximumLocalizationScaleFactor,
      multipointRansacReprojectionThresholdPixels,
      maximumLocalScaleRatio,
      maximumLocalAnisotropyRatio,
    ];
    if (positive.any((value) => !value.isFinite || value <= 0) ||
        minimumRegistrationAreaRatio >= 1 ||
        maximumExtremePerspectiveRatio < 1 ||
        maximumRejectedCornerErrorPixels < maximumReprojectionErrorPixels ||
        maximumLocalizationScaleFactor < 1 ||
        !minimumMultipointInlierRatio.isFinite ||
        minimumMultipointInlierRatio <= 0 ||
        minimumMultipointInlierRatio > 1 ||
        maximumLocalScaleRatio < 1 ||
        maximumLocalAnisotropyRatio < 1 ||
        !maximumPageBoundaryOvershootRatio.isFinite ||
        maximumPageBoundaryOvershootRatio < 0 ||
        maximumPageBoundaryOvershootRatio >= 1 ||
        multipointMaximumIterations < 1 ||
        !multipointConfidence.isFinite ||
        multipointConfidence <= 0 ||
        multipointConfidence >= 1) {
      throw ArgumentError('Alignment thresholds are outside valid ranges.');
    }
    if (finalMarkerDetectionMaxDimension != null &&
        finalMarkerDetectionMaxDimension < 1) {
      throw ArgumentError(
        'Final marker detection maximum dimension must be positive or null.',
      );
    }
    return ArucoAlignmentConfig._(
      dictionary: dictionary,
      minimumMarkerSidePixels: minimumMarkerSidePixels,
      minimumRegistrationAreaRatio: minimumRegistrationAreaRatio,
      minimumRegistrationSpacingPixels: minimumRegistrationSpacingPixels,
      maximumExtremePerspectiveRatio: maximumExtremePerspectiveRatio,
      maximumReprojectionErrorPixels: maximumReprojectionErrorPixels,
      maximumRejectedCornerErrorPixels: maximumRejectedCornerErrorPixels,
      maximumLocalizationScaleFactor: maximumLocalizationScaleFactor,
      multipointRansacReprojectionThresholdPixels:
          multipointRansacReprojectionThresholdPixels,
      minimumMultipointInlierRatio: minimumMultipointInlierRatio,
      maximumLocalScaleRatio: maximumLocalScaleRatio,
      maximumLocalAnisotropyRatio: maximumLocalAnisotropyRatio,
      maximumPageBoundaryOvershootRatio: maximumPageBoundaryOvershootRatio,
      multipointMaximumIterations: multipointMaximumIterations,
      multipointConfidence: multipointConfidence,
      enableMultipointHomography: enableMultipointHomography,
      selectionPolicy: selectionPolicy,
      allowAdditionalUnrelatedMarkers: allowAdditionalUnrelatedMarkers,
      finalMarkerDetectionMaxDimension: finalMarkerDetectionMaxDimension,
    );
  }

  const ArucoAlignmentConfig._({
    required this.dictionary,
    required this.minimumMarkerSidePixels,
    required this.minimumRegistrationAreaRatio,
    required this.minimumRegistrationSpacingPixels,
    required this.maximumExtremePerspectiveRatio,
    required this.maximumReprojectionErrorPixels,
    required this.maximumRejectedCornerErrorPixels,
    required this.maximumLocalizationScaleFactor,
    required this.multipointRansacReprojectionThresholdPixels,
    required this.minimumMultipointInlierRatio,
    required this.maximumLocalScaleRatio,
    required this.maximumLocalAnisotropyRatio,
    required this.maximumPageBoundaryOvershootRatio,
    required this.multipointMaximumIterations,
    required this.multipointConfidence,
    required this.enableMultipointHomography,
    required this.selectionPolicy,
    required this.allowAdditionalUnrelatedMarkers,
    required this.finalMarkerDetectionMaxDimension,
  });

  final ArucoDictionary dictionary;
  final double minimumMarkerSidePixels;
  final double minimumRegistrationAreaRatio;
  final double minimumRegistrationSpacingPixels;
  final double maximumExtremePerspectiveRatio;
  final double maximumReprojectionErrorPixels;

  /// Base bound for a corner rejected by the robust estimator at a
  /// one-canonical-pixel-per-detector-pixel localization scale. The engine
  /// scales it by the bounded localization conversion so RANSAC cannot hide a
  /// badly mismatched marker corner merely because detection was resized.
  final double maximumRejectedCornerErrorPixels;

  /// Maximum conversion from one detector-image pixel to canonical pixels.
  /// This bounds uncertainty propagation when final-still detection is
  /// performed on a reduced image.
  final double maximumLocalizationScaleFactor;
  final double multipointRansacReprojectionThresholdPixels;
  final double minimumMultipointInlierRatio;
  final double maximumLocalScaleRatio;
  final double maximumLocalAnisotropyRatio;
  final double maximumPageBoundaryOvershootRatio;
  final int multipointMaximumIterations;
  final double multipointConfidence;
  final bool enableMultipointHomography;
  final HomographySelectionPolicy selectionPolicy;
  final bool allowAdditionalUnrelatedMarkers;

  /// Maximum long edge used only for final-still ArUco detection.
  ///
  /// The original grayscale still remains the homography warp source. `null`
  /// keeps full-resolution detection for diagnostics.
  final int? finalMarkerDetectionMaxDimension;
}
