enum ArucoCornerRefinement { none, subpixel, contour, aprilTag }

/// Explicit OpenCV detector settings shared by live and final-still scanning.
///
/// The threshold range deliberately remains three passes, matching OpenCV's
/// default pass count, while covering a wider set of local illumination
/// scales. Subpixel refinement improves the registration corners used by the
/// homography without adding a second marker-detection pass.
final class ArucoDetectorProfile {
  const ArucoDetectorProfile({
    this.adaptiveThresholdWindowMin = 3,
    this.adaptiveThresholdWindowMax = 31,
    this.adaptiveThresholdWindowStep = 14,
    this.adaptiveThresholdConstant = 7,
    this.minimumMarkerPerimeterRate = 0.03,
    this.polygonApproximationAccuracyRate = 0.03,
    this.cornerRefinement = ArucoCornerRefinement.subpixel,
    this.cornerRefinementWindowSize = 3,
    this.cornerRefinementMaximumIterations = 15,
    this.cornerRefinementMinimumAccuracy = 0.05,
  });

  final int adaptiveThresholdWindowMin;
  final int adaptiveThresholdWindowMax;
  final int adaptiveThresholdWindowStep;
  final double adaptiveThresholdConstant;
  final double minimumMarkerPerimeterRate;
  final double polygonApproximationAccuracyRate;
  final ArucoCornerRefinement cornerRefinement;
  final int cornerRefinementWindowSize;
  final int cornerRefinementMaximumIterations;
  final double cornerRefinementMinimumAccuracy;

  int get adaptiveThresholdPassCount =>
      ((adaptiveThresholdWindowMax - adaptiveThresholdWindowMin) ~/
          adaptiveThresholdWindowStep) +
      1;

  void validate() {
    if (adaptiveThresholdWindowMin < 3 ||
        adaptiveThresholdWindowMin.isEven ||
        adaptiveThresholdWindowMax < adaptiveThresholdWindowMin ||
        adaptiveThresholdWindowMax.isEven ||
        adaptiveThresholdWindowStep <= 0 ||
        !adaptiveThresholdConstant.isFinite ||
        minimumMarkerPerimeterRate <= 0 ||
        !minimumMarkerPerimeterRate.isFinite ||
        polygonApproximationAccuracyRate <= 0 ||
        polygonApproximationAccuracyRate >= 1 ||
        !polygonApproximationAccuracyRate.isFinite ||
        cornerRefinementWindowSize <= 0 ||
        cornerRefinementMaximumIterations <= 0 ||
        cornerRefinementMinimumAccuracy <= 0 ||
        !cornerRefinementMinimumAccuracy.isFinite) {
      throw ArgumentError('ArUco detector profile is invalid.');
    }
  }
}
