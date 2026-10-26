import '../../../core/protocol/aruco_dictionary.dart';

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
    double multipointRansacReprojectionThresholdPixels = 1.5,
    double minimumMultipointInlierRatio = 0.875,
    double minimumMultipointScoreImprovementPixels = 0.05,
    double maximumHeldOutReprojectionErrorPixels = 4,
    double maximumLocalScaleRatio = 20,
    double maximumLocalAnisotropyRatio = 12,
    double maximumPageBoundaryOvershootRatio = 0.15,
    int multipointMaximumIterations = 500,
    double multipointConfidence = 0.995,
    bool enableMultipointHomography = true,
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
      multipointRansacReprojectionThresholdPixels,
      maximumHeldOutReprojectionErrorPixels,
      maximumLocalScaleRatio,
      maximumLocalAnisotropyRatio,
    ];
    if (positive.any((value) => !value.isFinite || value <= 0) ||
        minimumRegistrationAreaRatio >= 1 ||
        maximumExtremePerspectiveRatio < 1 ||
        maximumRejectedCornerErrorPixels < maximumReprojectionErrorPixels ||
        !minimumMultipointInlierRatio.isFinite ||
        minimumMultipointInlierRatio <= 0 ||
        minimumMultipointInlierRatio > 1 ||
        !minimumMultipointScoreImprovementPixels.isFinite ||
        minimumMultipointScoreImprovementPixels < 0 ||
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
      multipointRansacReprojectionThresholdPixels:
          multipointRansacReprojectionThresholdPixels,
      minimumMultipointInlierRatio: minimumMultipointInlierRatio,
      minimumMultipointScoreImprovementPixels:
          minimumMultipointScoreImprovementPixels,
      maximumHeldOutReprojectionErrorPixels:
          maximumHeldOutReprojectionErrorPixels,
      maximumLocalScaleRatio: maximumLocalScaleRatio,
      maximumLocalAnisotropyRatio: maximumLocalAnisotropyRatio,
      maximumPageBoundaryOvershootRatio: maximumPageBoundaryOvershootRatio,
      multipointMaximumIterations: multipointMaximumIterations,
      multipointConfidence: multipointConfidence,
      enableMultipointHomography: enableMultipointHomography,
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
    required this.multipointRansacReprojectionThresholdPixels,
    required this.minimumMultipointInlierRatio,
    required this.minimumMultipointScoreImprovementPixels,
    required this.maximumHeldOutReprojectionErrorPixels,
    required this.maximumLocalScaleRatio,
    required this.maximumLocalAnisotropyRatio,
    required this.maximumPageBoundaryOvershootRatio,
    required this.multipointMaximumIterations,
    required this.multipointConfidence,
    required this.enableMultipointHomography,
    required this.allowAdditionalUnrelatedMarkers,
    required this.finalMarkerDetectionMaxDimension,
  });

  final ArucoDictionary dictionary;
  final double minimumMarkerSidePixels;
  final double minimumRegistrationAreaRatio;
  final double minimumRegistrationSpacingPixels;
  final double maximumExtremePerspectiveRatio;
  final double maximumReprojectionErrorPixels;

  /// Bound for a corner rejected by the robust estimator. This remains finite
  /// so RANSAC cannot hide a badly mismatched marker corner.
  final double maximumRejectedCornerErrorPixels;
  final double multipointRansacReprojectionThresholdPixels;
  final double minimumMultipointInlierRatio;
  final double minimumMultipointScoreImprovementPixels;
  final double maximumHeldOutReprojectionErrorPixels;
  final double maximumLocalScaleRatio;
  final double maximumLocalAnisotropyRatio;
  final double maximumPageBoundaryOvershootRatio;
  final int multipointMaximumIterations;
  final double multipointConfidence;
  final bool enableMultipointHomography;
  final bool allowAdditionalUnrelatedMarkers;

  /// Maximum long edge used only for final-still ArUco detection.
  ///
  /// The original grayscale still remains the homography warp source. `null`
  /// keeps full-resolution detection for diagnostics.
  final int? finalMarkerDetectionMaxDimension;
}
