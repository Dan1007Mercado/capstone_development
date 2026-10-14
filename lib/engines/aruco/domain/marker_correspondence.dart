import 'dart:collection';

import '../../layout/domain/layout_regions.dart';
import 'detected_marker.dart';
import 'image_geometry.dart';

final class MarkerObservation {
  const MarkerObservation({
    required this.expectedRegion,
    required this.detectedMarker,
  });

  final MarkerRegion expectedRegion;
  final DetectedMarker detectedMarker;
}

final class MarkerCorrespondence {
  const MarkerCorrespondence({
    required this.markerId,
    required this.role,
    required this.sourceCorner,
    required this.sourcePoint,
    required this.destinationPoint,
  });

  final int markerId;
  final MarkerRole role;
  final MarkerCorner sourceCorner;
  final ImagePoint sourcePoint;
  final ImagePoint destinationPoint;
}

final class RegistrationQuality {
  const RegistrationQuality({
    required this.quadrilateralAreaRatio,
    required this.minimumMarkerSidePixels,
    required this.maximumPerspectiveRatio,
  });

  final double quadrilateralAreaRatio;
  final double minimumMarkerSidePixels;
  final double maximumPerspectiveRatio;
}

final class MarkerCorrespondenceSet {
  MarkerCorrespondenceSet({
    required Iterable<MarkerObservation> observations,
    required Iterable<MarkerCorrespondence> correspondences,
    required this.quality,
  }) : observations = UnmodifiableListView(List.of(observations)),
       correspondences = UnmodifiableListView(List.of(correspondences));

  final List<MarkerObservation> observations;
  final List<MarkerCorrespondence> correspondences;
  final RegistrationQuality quality;

  List<ImagePoint> get sourcePoints =>
      correspondences.map((item) => item.sourcePoint).toList(growable: false);

  List<ImagePoint> get destinationPoints => correspondences
      .map((item) => item.destinationPoint)
      .toList(growable: false);
}
