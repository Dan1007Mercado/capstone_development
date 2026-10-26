import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'image_geometry.dart';
import 'detected_marker.dart';
import 'marker_correspondence.dart';

final class HomographyMatrix {
  HomographyMatrix(Iterable<double> values)
    : values = UnmodifiableListView(List.of(values)) {
    if (this.values.length != 9 ||
        this.values.any((value) => !value.isFinite)) {
      throw ArgumentError('Homography must contain nine finite values.');
    }
  }

  final List<double> values;

  double projectionDenominator(ImagePoint point) =>
      values[6] * point.x + values[7] * point.y + values[8];

  ImagePoint project(ImagePoint point) {
    final denominator = projectionDenominator(point);
    if (!denominator.isFinite || denominator.abs() < 1e-12) {
      throw StateError('Homography projection is degenerate.');
    }
    return ImagePoint(
      (values[0] * point.x + values[1] * point.y + values[2]) / denominator,
      (values[3] * point.x + values[4] * point.y + values[5]) / denominator,
    );
  }

  HomographyMatrix inverse() {
    final h = values;
    final scale = h.map((value) => value.abs()).reduce(math.max);
    final determinant =
        h[0] * (h[4] * h[8] - h[5] * h[7]) -
        h[1] * (h[3] * h[8] - h[5] * h[6]) +
        h[2] * (h[3] * h[7] - h[4] * h[6]);
    if (scale == 0 ||
        !determinant.isFinite ||
        determinant.abs() / (scale * scale * scale) <= 1e-12) {
      throw StateError('Homography is not invertible.');
    }
    return HomographyMatrix([
      (h[4] * h[8] - h[5] * h[7]) / determinant,
      (h[2] * h[7] - h[1] * h[8]) / determinant,
      (h[1] * h[5] - h[2] * h[4]) / determinant,
      (h[5] * h[6] - h[3] * h[8]) / determinant,
      (h[0] * h[8] - h[2] * h[6]) / determinant,
      (h[2] * h[3] - h[0] * h[5]) / determinant,
      (h[3] * h[7] - h[4] * h[6]) / determinant,
      (h[1] * h[6] - h[0] * h[7]) / determinant,
      (h[0] * h[4] - h[1] * h[3]) / determinant,
    ]);
  }
}

/// Canonical page represented by either PNG bytes or owned 8-bit grayscale.
final class CanonicalPageImage {
  CanonicalPageImage({
    required this.size,
    List<int> pngBytes = const [],
    List<int> grayscaleBytes = const [],
  }) : pngBytes = Uint8List.fromList(pngBytes),
       grayscaleBytes = Uint8List.fromList(grayscaleBytes) {
    if (this.grayscaleBytes.isNotEmpty &&
        this.grayscaleBytes.length != size.area) {
      throw ArgumentError('Canonical grayscale bytes must match image area.');
    }
  }

  /// Takes ownership of an already detached canonical grayscale buffer.
  /// Intended for native backends after copying pixels out of a native Mat.
  CanonicalPageImage.ownedGrayscale({
    required this.size,
    required this.grayscaleBytes,
  }) : pngBytes = Uint8List(0) {
    if (grayscaleBytes.length != size.area) {
      throw ArgumentError('Canonical grayscale bytes must match image area.');
    }
  }

  final ImageSize size;
  final Uint8List pngBytes;
  final Uint8List grayscaleBytes;
}

enum AlignmentHomographyMethod { fourPoint, multiPoint }

enum HomographyValidationMethod { unusedFittingCorners, leaveOneMarkerOut }

final class ReprojectionStatistics {
  ReprojectionStatistics(Iterable<double> values)
    : errors = UnmodifiableListView(List.of(values)) {
    if (errors.isEmpty) {
      throw ArgumentError('Reprojection statistics require observations.');
    }
  }

  final List<double> errors;

  double get mean =>
      errors.reduce((first, second) => first + second) / errors.length;

  double get median {
    final sorted = List<double>.of(errors)..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  double get maximum =>
      errors.reduce((first, second) => first > second ? first : second);

  double get percentile95 {
    final sorted = List<double>.of(errors)..sort();
    final index = ((sorted.length * 0.95).ceil() - 1).clamp(
      0,
      sorted.length - 1,
    );
    return sorted[index];
  }

  double get score => median + mean * 0.25 + maximum * 0.1;
}

final class HomographyCandidateDiagnostics {
  HomographyCandidateDiagnostics({
    required this.method,
    required Iterable<double> commonReprojectionErrors,
    required this.meanCommonReprojectionError,
    required this.medianCommonReprojectionError,
    required this.maxCommonReprojectionError,
    required this.inlierCount,
    required this.totalPointCount,
    required this.accepted,
    required this.duration,
    this.fittingResiduals,
    this.heldOutValidationResiduals,
    this.heldOutValidationMethod,
    Iterable<int> inliersPerMarker = const [],
    this.rejectionReason,
  }) : commonReprojectionErrors = UnmodifiableListView(
         List.of(commonReprojectionErrors),
       ),
       inliersPerMarker = UnmodifiableListView(List.of(inliersPerMarker));

  final AlignmentHomographyMethod method;
  final List<double> commonReprojectionErrors;
  final double meanCommonReprojectionError;
  final double medianCommonReprojectionError;
  final double maxCommonReprojectionError;
  final int inlierCount;
  final int totalPointCount;
  final bool accepted;
  final Duration duration;
  final ReprojectionStatistics? fittingResiduals;

  /// Out-of-sample geometric consistency. For multi-point this is produced by
  /// leave-one-marker-out estimates, never by the production fit itself.
  final ReprojectionStatistics? heldOutValidationResiduals;
  final HomographyValidationMethod? heldOutValidationMethod;
  final List<int> inliersPerMarker;
  final String? rejectionReason;

  double get inlierRatio =>
      totalPointCount == 0 ? 0 : inlierCount / totalPointCount;

  /// Shared score used only between candidates evaluated on the same 16
  /// published marker corners. It intentionally includes tail error.
  double get commonScore =>
      medianCommonReprojectionError +
      meanCommonReprojectionError * 0.25 +
      maxCommonReprojectionError * 0.1;

  double? get heldOutValidationScore => heldOutValidationResiduals?.score;
}

final class PageAlignmentDiagnostics {
  PageAlignmentDiagnostics({
    required Iterable<int> expectedMarkerIds,
    required Iterable<int> detectedMarkerIds,
    required Iterable<double> sourceMarkerSideLengths,
    required Iterable<ImagePoint> sourceRegistrationPoints,
    required Iterable<ImagePoint> destinationRegistrationPoints,
    required this.registrationQuality,
    required Iterable<double> reprojectionErrors,
    required this.meanReprojectionError,
    required this.maxReprojectionError,
    required this.processingDuration,
    this.sourceSize,
    this.canonicalSize,
    this.decodeDuration = Duration.zero,
    this.detectionPreparationDuration = Duration.zero,
    this.detectionDuration = Duration.zero,
    this.coordinateRemapDuration = Duration.zero,
    this.pageResolutionDuration = Duration.zero,
    this.correspondenceDuration = Duration.zero,
    this.homographyDuration = Duration.zero,
    this.warpDuration = Duration.zero,
    this.detectionSize,
    this.detectionScaleX = 1,
    this.detectionScaleY = 1,
    this.selectedHomographyMethod = AlignmentHomographyMethod.fourPoint,
    this.fourPointCandidate,
    this.multiPointCandidate,
    this.fourPointHomographyDuration = Duration.zero,
    this.multiPointHomographyDuration = Duration.zero,
    this.candidateValidationDuration = Duration.zero,
    this.selectionReason,
    this.fallbackReason,
  }) : expectedMarkerIds = UnmodifiableListView(List.of(expectedMarkerIds)),
       detectedMarkerIds = UnmodifiableListView(List.of(detectedMarkerIds)),
       sourceMarkerSideLengths = UnmodifiableListView(
         List.of(sourceMarkerSideLengths),
       ),
       sourceRegistrationPoints = UnmodifiableListView(
         List.of(sourceRegistrationPoints),
       ),
       destinationRegistrationPoints = UnmodifiableListView(
         List.of(destinationRegistrationPoints),
       ),
       reprojectionErrors = UnmodifiableListView(List.of(reprojectionErrors));

  final List<int> expectedMarkerIds;
  final List<int> detectedMarkerIds;
  final List<double> sourceMarkerSideLengths;
  final List<ImagePoint> sourceRegistrationPoints;
  final List<ImagePoint> destinationRegistrationPoints;
  final RegistrationQuality registrationQuality;
  final List<double> reprojectionErrors;
  final double meanReprojectionError;
  final double maxReprojectionError;
  final Duration processingDuration;
  final ImageSize? sourceSize;
  final ImageSize? canonicalSize;
  final Duration decodeDuration;
  final Duration detectionPreparationDuration;
  final Duration detectionDuration;
  final Duration coordinateRemapDuration;
  final Duration pageResolutionDuration;
  final Duration correspondenceDuration;
  final Duration homographyDuration;
  final Duration warpDuration;
  final ImageSize? detectionSize;
  final double detectionScaleX;
  final double detectionScaleY;
  final AlignmentHomographyMethod selectedHomographyMethod;
  final HomographyCandidateDiagnostics? fourPointCandidate;
  final HomographyCandidateDiagnostics? multiPointCandidate;
  final Duration fourPointHomographyDuration;
  final Duration multiPointHomographyDuration;
  final Duration candidateValidationDuration;
  final String? selectionReason;
  final String? fallbackReason;
}

final class PageAlignmentResult {
  PageAlignmentResult({
    required this.canonicalPage,
    required this.homography,
    required Iterable<MarkerObservation> observations,
    required Iterable<MarkerCorrespondence> correspondences,
    required this.diagnostics,
    Iterable<DetectedMarker> detectedMarkers = const [],
  }) : observations = UnmodifiableListView(List.of(observations)),
       correspondences = UnmodifiableListView(List.of(correspondences)),
       detectedMarkers = UnmodifiableListView(List.of(detectedMarkers));

  final CanonicalPageImage canonicalPage;
  final HomographyMatrix homography;
  final List<MarkerObservation> observations;
  final List<MarkerCorrespondence> correspondences;
  final List<DetectedMarker> detectedMarkers;
  final PageAlignmentDiagnostics diagnostics;
}
