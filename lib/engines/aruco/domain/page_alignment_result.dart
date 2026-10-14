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

/// PNG-encoded canonical page. The byte list is defensively copied.
final class CanonicalPageImage {
  CanonicalPageImage({required this.size, required List<int> pngBytes})
    : pngBytes = Uint8List.fromList(pngBytes);

  final ImageSize size;
  final Uint8List pngBytes;
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
