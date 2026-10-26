import 'dart:math' as math;

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../layout/domain/layout_regions.dart';
import '../../layout/domain/page_layout.dart';
import '../domain/aruco_alignment_config.dart';
import '../domain/detected_marker.dart';
import '../domain/image_geometry.dart';
import '../domain/marker_correspondence.dart';

/// Central P4.1 mapping from page role to detectable marker corner.
abstract final class DetectedRegistrationCorner {
  static MarkerCorner forRole(MarkerRole role) => switch (role) {
    MarkerRole.topLeft => MarkerCorner.bottomRight,
    MarkerRole.topRight => MarkerCorner.bottomLeft,
    MarkerRole.bottomLeft => MarkerCorner.topRight,
    MarkerRole.bottomRight => MarkerCorner.topLeft,
  };
}

/// Pure-Dart semantic matching and registration quality validation.
final class MarkerCorrespondenceService {
  const MarkerCorrespondenceService();

  static const _homographyOrder = [
    MarkerRole.topLeft,
    MarkerRole.topRight,
    MarkerRole.bottomRight,
    MarkerRole.bottomLeft,
  ];

  EngineResult<MarkerCorrespondenceSet> build({
    required ArucoDetection detection,
    required PageLayout page,
    required ArucoAlignmentConfig config,
  }) {
    final expectedById = <int, MarkerRegion>{};
    final expectedByRole = <MarkerRole, MarkerRegion>{};
    for (final region in page.markerRegions) {
      if (expectedById.containsKey(region.markerId) ||
          expectedByRole.containsKey(region.role)) {
        return _failure(
          'ARUCO_GEOMETRY_INVALID',
          'PageLayout marker IDs and roles must be unique.',
        );
      }
      expectedById[region.markerId] = region;
      expectedByRole[region.role] = region;
    }
    if (expectedByRole.length != _homographyOrder.length ||
        !_homographyOrder.every(expectedByRole.containsKey)) {
      return _failure(
        'ARUCO_GEOMETRY_INVALID',
        'PageLayout must define all four semantic marker roles.',
      );
    }

    final detectedById = <int, List<DetectedMarker>>{};
    for (final marker in detection.markers) {
      detectedById.putIfAbsent(marker.id, () => []).add(marker);
    }
    final missing = expectedById.keys
        .where((id) => !(detectedById[id]?.isNotEmpty ?? false))
        .toList(growable: false);
    if (missing.isNotEmpty) {
      return _failure(
        'ARUCO_REQUIRED_MARKER_MISSING',
        'One or more required markers were not detected.',
        {
          'expectedMarkerIds': expectedById.keys.toList(growable: false),
          'detectedMarkerIds': detection.markers
              .map((marker) => marker.id)
              .toList(growable: false),
          'missingMarkerIds': missing,
        },
      );
    }
    final duplicates = expectedById.keys
        .where((id) => detectedById[id]!.length > 1)
        .toList(growable: false);
    if (duplicates.isNotEmpty) {
      return _failure(
        'ARUCO_REQUIRED_MARKER_DUPLICATE',
        'A required marker ID was detected more than once.',
        {'duplicateMarkerIds': duplicates},
      );
    }
    final unexpected = detectedById.keys
        .where((id) => !expectedById.containsKey(id))
        .toList(growable: false);
    if (unexpected.isNotEmpty && !config.allowAdditionalUnrelatedMarkers) {
      return _failure(
        'ARUCO_DETECTION_FAILED',
        'Unexpected markers are not allowed by the alignment configuration.',
        {'unexpectedMarkerIds': unexpected},
      );
    }

    final observationsByRole = <MarkerRole, MarkerObservation>{};
    var minimumMarkerSide = double.infinity;
    for (final role in _homographyOrder) {
      final expected = expectedByRole[role]!;
      final detected = detectedById[expected.markerId]!.single;
      if (detected.corners.any(
        (point) => !detection.sourceSize.contains(point),
      )) {
        return _failure(
          'ARUCO_GEOMETRY_INVALID',
          'A required marker corner lies outside the source image.',
          {'markerId': detected.id},
        );
      }
      final markerArea = _signedArea(detected.corners);
      if (markerArea < 0) {
        return _failure(
          'ARUCO_REFLECTION_DETECTED',
          'A required marker has mirrored corner orientation.',
          {'markerId': detected.id},
        );
      }
      if (!_isStrictlyConvex(detected.corners) || markerArea == 0) {
        return _failure(
          'ARUCO_GEOMETRY_INVALID',
          'A required marker quadrilateral is invalid.',
          {'markerId': detected.id},
        );
      }
      minimumMarkerSide = math.min(
        minimumMarkerSide,
        detected.minimumSideLength,
      );
      if (detected.minimumSideLength < config.minimumMarkerSidePixels) {
        return _failure(
          'ARUCO_MARKER_TOO_SMALL',
          'A required marker is below the minimum reliable size.',
          {
            'markerId': detected.id,
            'minimumSidePixels': detected.minimumSideLength,
            'requiredMinimumPixels': config.minimumMarkerSidePixels,
          },
        );
      }
      observationsByRole[role] = MarkerObservation(
        expectedRegion: expected,
        detectedMarker: detected,
      );
    }

    final sourcePoints = [
      for (final role in _homographyOrder)
        observationsByRole[role]!.detectedMarker.corner(
          DetectedRegistrationCorner.forRole(role),
        ),
    ];
    final signedArea = _signedArea(sourcePoints);
    if (signedArea < 0) {
      return _failure(
        'ARUCO_REFLECTION_DETECTED',
        'Marker role topology indicates a mirrored page.',
      );
    }
    if (signedArea == 0 || !_isStrictlyConvex(sourcePoints)) {
      return _failure(
        'ARUCO_GEOMETRY_INVALID',
        'Registration points form a degenerate or self-crossing quadrilateral.',
      );
    }

    final areaRatio = signedArea / detection.sourceSize.area;
    if (areaRatio < config.minimumRegistrationAreaRatio) {
      return _failure(
        'ARUCO_GEOMETRY_INVALID',
        'Registration quadrilateral occupies too little of the source image.',
        {
          'areaRatio': areaRatio,
          'minimumAreaRatio': config.minimumRegistrationAreaRatio,
        },
      );
    }
    final outerSides = _sideLengths(sourcePoints);
    if (outerSides.any(
      (length) => length < config.minimumRegistrationSpacingPixels,
    )) {
      return _failure(
        'ARUCO_GEOMETRY_INVALID',
        'Required markers are implausibly close together.',
      );
    }
    final perspectiveRatio = registrationPerspectiveRatio(sourcePoints);
    if (!perspectiveRatio.isFinite ||
        perspectiveRatio > config.maximumExtremePerspectiveRatio) {
      return _failure(
        'ARUCO_GEOMETRY_INVALID',
        'Registration geometry has extreme perspective distortion.',
        {
          'perspectiveRatio': perspectiveRatio,
          'maximumPerspectiveRatio': config.maximumExtremePerspectiveRatio,
        },
      );
    }

    final observations = [
      for (final role in _homographyOrder) observationsByRole[role]!,
    ];
    final correspondences = [
      for (var index = 0; index < _homographyOrder.length; index++)
        MarkerCorrespondence(
          markerId: observations[index].expectedRegion.markerId,
          role: _homographyOrder[index],
          sourceCorner: DetectedRegistrationCorner.forRole(
            _homographyOrder[index],
          ),
          sourcePoint: sourcePoints[index],
          destinationPoint: physicalRegistrationToCanonical(
            observations[index].expectedRegion,
            page,
          ),
        ),
    ];

    return EngineResult.success(
      MarkerCorrespondenceSet(
        observations: observations,
        correspondences: correspondences,
        quality: RegistrationQuality(
          quadrilateralAreaRatio: areaRatio,
          minimumMarkerSidePixels: minimumMarkerSide,
          maximumPerspectiveRatio: perspectiveRatio,
        ),
      ),
    );
  }

  ImagePoint physicalRegistrationToCanonical(
    MarkerRegion marker,
    PageLayout page,
  ) => ImagePoint(
    marker.physicalRegistrationPoint.x.millimeters /
        page.pageSpec.size.width.millimeters *
        page.canonicalPageSpec.widthPixels,
    marker.physicalRegistrationPoint.y.millimeters /
        page.pageSpec.size.height.millimeters *
        page.canonicalPageSpec.heightPixels,
  );

  static List<double> _sideLengths(List<ImagePoint> points) => [
    for (var index = 0; index < points.length; index++)
      points[index].distanceTo(points[(index + 1) % points.length]),
  ];

  static double _signedArea(List<ImagePoint> points) {
    var twiceArea = 0.0;
    for (var index = 0; index < points.length; index++) {
      final current = points[index];
      final next = points[(index + 1) % points.length];
      twiceArea += current.x * next.y - next.x * current.y;
    }
    return twiceArea / 2;
  }

  static bool _isStrictlyConvex(List<ImagePoint> points) {
    if (points.length != 4) return false;
    double? sign;
    for (var index = 0; index < points.length; index++) {
      final first = points[index];
      final second = points[(index + 1) % points.length];
      final third = points[(index + 2) % points.length];
      final cross =
          (second.x - first.x) * (third.y - second.y) -
          (second.y - first.y) * (third.x - second.x);
      if (cross.abs() < 1e-9) return false;
      final currentSign = cross.sign;
      sign ??= currentSign;
      if (currentSign != sign) return false;
    }
    return true;
  }

  EngineResult<MarkerCorrespondenceSet> _failure(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );
}
