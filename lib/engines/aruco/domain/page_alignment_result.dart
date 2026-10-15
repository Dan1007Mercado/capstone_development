import 'dart:collection';
import 'dart:typed_data';

import 'image_geometry.dart';
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

  ImagePoint project(ImagePoint point) {
    final denominator = values[6] * point.x + values[7] * point.y + values[8];
    if (!denominator.isFinite || denominator.abs() < 1e-12) {
      throw StateError('Homography projection is degenerate.');
    }
    return ImagePoint(
      (values[0] * point.x + values[1] * point.y + values[2]) / denominator,
      (values[3] * point.x + values[4] * point.y + values[5]) / denominator,
    );
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
    this.detectionDuration = Duration.zero,
    this.correspondenceDuration = Duration.zero,
    this.homographyDuration = Duration.zero,
    this.warpDuration = Duration.zero,
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
  final Duration detectionDuration;
  final Duration correspondenceDuration;
  final Duration homographyDuration;
  final Duration warpDuration;
}

final class PageAlignmentResult {
  PageAlignmentResult({
    required this.canonicalPage,
    required this.homography,
    required Iterable<MarkerObservation> observations,
    required Iterable<MarkerCorrespondence> correspondences,
    required this.diagnostics,
  }) : observations = UnmodifiableListView(List.of(observations)),
       correspondences = UnmodifiableListView(List.of(correspondences));

  final CanonicalPageImage canonicalPage;
  final HomographyMatrix homography;
  final List<MarkerObservation> observations;
  final List<MarkerCorrespondence> correspondences;
  final PageAlignmentDiagnostics diagnostics;
}
