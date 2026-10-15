import '../../../engines/aruco/application/marker_correspondence_service.dart';
import '../../../engines/aruco/domain/image_geometry.dart';
import '../../../engines/layout/domain/layout_regions.dart';
import '../../../engines/layout/domain/page_layout.dart';

const _outlineRoleOrder = [
  MarkerRole.topLeft,
  MarkerRole.topRight,
  MarkerRole.bottomRight,
  MarkerRole.bottomLeft,
];

/// Extrapolates the physical page boundary from the four tracked marker
/// registration corners using the authoritative PageLayout correspondences.
/// Returns no outline when the projective solution is degenerate.
List<ImagePoint> projectDetectedPageOutline({
  required PageLayout page,
  required List<ImagePoint> sourceRegistrationPoints,
}) {
  if (sourceRegistrationPoints.length != 4) return const [];
  final regions = {
    for (final marker in page.markerRegions) marker.role: marker,
  };
  if (!_outlineRoleOrder.every(regions.containsKey)) return const [];
  const correspondence = MarkerCorrespondenceService();
  final canonicalRegistrationPoints = [
    for (final role in _outlineRoleOrder)
      correspondence.physicalRegistrationToCanonical(regions[role]!, page),
  ];
  final transform = _solveProjectiveTransform(
    canonicalRegistrationPoints,
    sourceRegistrationPoints,
  );
  if (transform == null) return const [];
  final width = page.canonicalPageSpec.widthPixels.toDouble();
  final height = page.canonicalPageSpec.heightPixels.toDouble();
  try {
    return [
      transform.project(ImagePoint(0, 0)),
      transform.project(ImagePoint(width, 0)),
      transform.project(ImagePoint(width, height)),
      transform.project(ImagePoint(0, height)),
    ];
  } on StateError {
    return const [];
  }
}

_ProjectiveTransform? _solveProjectiveTransform(
  List<ImagePoint> from,
  List<ImagePoint> to,
) {
  final matrix = List.generate(8, (_) => List<double>.filled(9, 0));
  for (var index = 0; index < 4; index++) {
    final x = from[index].x;
    final y = from[index].y;
    final u = to[index].x;
    final v = to[index].y;
    matrix[index * 2]
      ..[0] = x
      ..[1] = y
      ..[2] = 1
      ..[6] = -u * x
      ..[7] = -u * y
      ..[8] = u;
    matrix[index * 2 + 1]
      ..[3] = x
      ..[4] = y
      ..[5] = 1
      ..[6] = -v * x
      ..[7] = -v * y
      ..[8] = v;
  }
  for (var pivot = 0; pivot < 8; pivot++) {
    var best = pivot;
    for (var row = pivot + 1; row < 8; row++) {
      if (matrix[row][pivot].abs() > matrix[best][pivot].abs()) best = row;
    }
    if (matrix[best][pivot].abs() < 1e-10) return null;
    final swap = matrix[pivot];
    matrix[pivot] = matrix[best];
    matrix[best] = swap;
    final divisor = matrix[pivot][pivot];
    for (var column = pivot; column < 9; column++) {
      matrix[pivot][column] /= divisor;
    }
    for (var row = 0; row < 8; row++) {
      if (row == pivot) continue;
      final factor = matrix[row][pivot];
      for (var column = pivot; column < 9; column++) {
        matrix[row][column] -= factor * matrix[pivot][column];
      }
    }
  }
  return _ProjectiveTransform([
    for (var row = 0; row < 8; row++) matrix[row][8],
    1,
  ]);
}

final class _ProjectiveTransform {
  const _ProjectiveTransform(this.values);

  final List<double> values;

  ImagePoint project(ImagePoint point) {
    final denominator = values[6] * point.x + values[7] * point.y + values[8];
    if (!denominator.isFinite || denominator.abs() < 1e-10) {
      throw StateError('Projective page outline is degenerate.');
    }
    return ImagePoint(
      (values[0] * point.x + values[1] * point.y + values[2]) / denominator,
      (values[3] * point.x + values[4] * point.y + values[5]) / denominator,
    );
  }
}
