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
    bool allowAdditionalUnrelatedMarkers = true,
    int? finalMarkerDetectionMaxDimension = 1400,
  }) {
    final positive = [
      minimumMarkerSidePixels,
      minimumRegistrationAreaRatio,
      minimumRegistrationSpacingPixels,
      maximumExtremePerspectiveRatio,
      maximumReprojectionErrorPixels,
    ];
    if (positive.any((value) => !value.isFinite || value <= 0) ||
        minimumRegistrationAreaRatio >= 1 ||
        maximumExtremePerspectiveRatio < 1) {
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
    required this.allowAdditionalUnrelatedMarkers,
    required this.finalMarkerDetectionMaxDimension,
  });

  final ArucoDictionary dictionary;
  final double minimumMarkerSidePixels;
  final double minimumRegistrationAreaRatio;
  final double minimumRegistrationSpacingPixels;
  final double maximumExtremePerspectiveRatio;
  final double maximumReprojectionErrorPixels;
  final bool allowAdditionalUnrelatedMarkers;

  /// Maximum long edge used only for final-still ArUco detection.
  ///
  /// The original grayscale still remains the homography warp source. `null`
  /// keeps full-resolution detection for diagnostics.
  final int? finalMarkerDetectionMaxDimension;
}
