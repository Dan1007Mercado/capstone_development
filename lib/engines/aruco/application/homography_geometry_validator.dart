import 'dart:math' as math;

import '../../layout/domain/page_layout.dart';
import '../domain/aruco_alignment_config.dart';
import '../domain/image_geometry.dart';
import '../domain/page_alignment_result.dart';

/// Validates a source-to-canonical transform over the actual published page,
/// including representative bubble locations rather than only fitted points.
final class HomographyGeometryValidator {
  const HomographyGeometryValidator();

  String? validationFailure({
    required HomographyMatrix matrix,
    required PageLayout page,
    required ImageSize sourceSize,
    required ArucoAlignmentConfig config,
  }) {
    final h = matrix.values;
    final scale = h.map((value) => value.abs()).reduce(math.max);
    if (!scale.isFinite || scale == 0) return 'NUMERICALLY_DEGENERATE';
    final determinant =
        h[0] * (h[4] * h[8] - h[5] * h[7]) -
        h[1] * (h[3] * h[8] - h[5] * h[6]) +
        h[2] * (h[3] * h[7] - h[4] * h[6]);
    if (!determinant.isFinite ||
        determinant.abs() / (scale * scale * scale) <= 1e-12) {
      return 'NUMERICALLY_DEGENERATE';
    }
    HomographyMatrix inverse;
    try {
      inverse = matrix.inverse();
    } on Object {
      return 'INVERSE_UNAVAILABLE';
    }
    final width = page.canonicalPageSpec.widthPixels.toDouble() - 1;
    final height = page.canonicalPageSpec.heightPixels.toDouble() - 1;
    final canonicalCorners = [
      ImagePoint(0, 0),
      ImagePoint(width, 0),
      ImagePoint(width, height),
      ImagePoint(0, height),
    ];
    late final List<ImagePoint> sourceCorners;
    try {
      sourceCorners = canonicalCorners.map(inverse.project).toList();
      for (var index = 0; index < canonicalCorners.length; index++) {
        if (matrix
                .project(sourceCorners[index])
                .distanceTo(canonicalCorners[index]) >
            0.01) {
          return 'INVERSE_ROUND_TRIP_FAILED';
        }
      }
    } on Object {
      return 'PAGE_PROJECTION_FAILED';
    }
    if (_signedArea(sourceCorners) <= 1 || !_isStrictlyConvex(sourceCorners)) {
      return 'PAGE_ORIENTATION_INVALID';
    }
    final overshootX =
        sourceSize.width * config.maximumPageBoundaryOvershootRatio;
    final overshootY =
        sourceSize.height * config.maximumPageBoundaryOvershootRatio;
    if (sourceCorners.any(
      (point) =>
          point.x < -overshootX ||
          point.y < -overshootY ||
          point.x > sourceSize.width - 1 + overshootX ||
          point.y > sourceSize.height - 1 + overshootY,
    )) {
      return 'PAGE_BOUNDS_IMPLAUSIBLE';
    }
    final samples = <ImagePoint>[
      for (final x in [0.2, 0.5, 0.8])
        for (final y in [0.2, 0.5, 0.8]) ImagePoint(width * x, height * y),
    ];
    if (page.bubbleRegions.isNotEmpty) {
      final stride = math.max(1, (page.bubbleRegions.length / 12).ceil());
      for (var index = 0; index < page.bubbleRegions.length; index += stride) {
        final center = page.bubbleRegions[index].physicalCenter;
        samples.add(
          ImagePoint(
            center.x.millimeters /
                page.pageSpec.size.width.millimeters *
                page.canonicalPageSpec.widthPixels,
            center.y.millimeters /
                page.pageSpec.size.height.millimeters *
                page.canonicalPageSpec.heightPixels,
          ),
        );
      }
    }
    final stepX = math.max(1.0, width * 0.005);
    final stepY = math.max(1.0, height * 0.005);
    final localScales = <double>[];
    try {
      for (final sample in samples) {
        final origin = inverse.project(sample);
        final alongX = inverse.project(ImagePoint(sample.x + stepX, sample.y));
        final alongY = inverse.project(ImagePoint(sample.x, sample.y + stepY));
        final scaleX = origin.distanceTo(alongX) / stepX;
        final scaleY = origin.distanceTo(alongY) / stepY;
        if (scaleX <= 0 ||
            scaleY <= 0 ||
            !scaleX.isFinite ||
            !scaleY.isFinite) {
          return 'LOCAL_SCALE_INVALID';
        }
        final anisotropy = math.max(scaleX, scaleY) / math.min(scaleX, scaleY);
        if (anisotropy > config.maximumLocalAnisotropyRatio) {
          return 'LOCAL_ANISOTROPY_EXCEEDED';
        }
        final cross =
            (alongX.x - origin.x) * (alongY.y - origin.y) -
            (alongX.y - origin.y) * (alongY.x - origin.x);
        if (!cross.isFinite || cross <= 0) return 'LOCAL_ORIENTATION_INVALID';
        localScales.add(math.sqrt(scaleX * scaleY));
      }
    } on Object {
      return 'CONTENT_PROJECTION_FAILED';
    }
    final minimumScale = localScales.reduce(math.min);
    final maximumScale = localScales.reduce(math.max);
    if (maximumScale / minimumScale > config.maximumLocalScaleRatio) {
      return 'LOCAL_SCALE_VARIATION_EXCEEDED';
    }
    return null;
  }

  double _signedArea(List<ImagePoint> points) {
    var twiceArea = 0.0;
    for (var index = 0; index < points.length; index++) {
      final current = points[index];
      final next = points[(index + 1) % points.length];
      twiceArea += current.x * next.y - next.x * current.y;
    }
    return twiceArea / 2;
  }

  bool _isStrictlyConvex(List<ImagePoint> points) {
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
      sign ??= cross.sign;
      if (cross.sign != sign) return false;
    }
    return true;
  }
}
