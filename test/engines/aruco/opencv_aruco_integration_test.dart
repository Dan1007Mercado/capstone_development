import 'dart:math' as math;
import 'dart:typed_data';

import 'package:capstone_development/core/geometry/physical_geometry.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/engines/aruco/application/aruco_alignment_engine.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_alignment_config.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/aruco/infrastructure/opencv_aruco_vision_backend.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/pdf/infrastructure/opencv_4x4_50_marker_encoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../layout/layout_test_fixtures.dart';

void main() {
  late PageLayout page;
  late image.Image frontal;
  late bool backendAvailable;
  String? unavailableReason;

  setUpAll(() {
    page = buildLayout(fullTemplate()).pages.single;
    frontal = _renderSyntheticPage(page);
    final probe = const OpenCvArucoVisionBackend().open(
      Uint8List.fromList(image.encodePng(frontal)),
      ArucoAlignmentConfig(),
    );
    backendAvailable = probe.isSuccess;
    if (probe.isSuccess) {
      probe.value.dispose();
    } else {
      unavailableReason = '${probe.error.code}: ${probe.error.message}';
    }
  });

  test('clean frontal page detects and aligns all four markers', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final result = _align(frontal, page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(result.value.observations, hasLength(4));
    expect(result.value.diagnostics.expectedMarkerIds.toSet(), {
      10,
      11,
      12,
      13,
    });
    expect(result.value.diagnostics.maxReprojectionError, lessThan(0.01));
  });

  for (final angle in [90, 180, 270]) {
    test('page rotated $angle degrees aligns by semantic marker IDs', () {
      if (!backendAvailable) {
        markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
        return;
      }
      final result = _align(image.copyRotate(frontal, angle: angle), page);

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      expect(result.value.observations, hasLength(4));
    });
  }

  test('moderate perspective page aligns', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final perspective = _perspectiveWarp(frontal, [
      ImagePoint(45, 70),
      ImagePoint(frontal.width - 75, 25),
      ImagePoint(frontal.width - 25, frontal.height - 65),
      ImagePoint(70, frontal.height - 20),
    ]);
    final result = _align(perspective, page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(result.value.observations, hasLength(4));
  });

  test('translated complete page aligns inside a larger source image', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final canvas = image.Image(
      width: frontal.width + 160,
      height: frontal.height + 120,
      numChannels: 3,
    );
    image.fill(canvas, color: image.ColorRgb8(255, 255, 255));
    image.compositeImage(canvas, frontal, dstX: 70, dstY: 50);
    final result = _align(canvas, page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
  });

  test('moderate scale reduction aligns', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final scaled = image.copyResize(
      frontal,
      width: (frontal.width * 0.65).round(),
      interpolation: image.Interpolation.linear,
    );
    final result = _align(scaled, page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
  });

  test('one erased marker returns required-marker-missing', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final missing = image.Image.from(frontal);
    _eraseRegion(missing, page, page.markerRegions.first.physicalBounds);
    final result = _align(missing, page);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'ARUCO_REQUIRED_MARKER_MISSING');
  });

  test('duplicate required marker returns ambiguity failure', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final duplicate = image.Image.from(frontal);
    _drawMarker(
      duplicate,
      markerId: page.markerRegions.first.markerId,
      left: duplicate.width ~/ 2 - 50,
      top: duplicate.height ~/ 2 - 50,
      size: 100,
    );
    final result = _align(duplicate, page);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'ARUCO_REQUIRED_MARKER_DUPLICATE');
  });

  test('severe degenerate perspective fails safely', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final degenerate = _perspectiveWarp(frontal, [
      ImagePoint(200, 700),
      ImagePoint(frontal.width - 200, 705),
      ImagePoint(frontal.width - 180, 735),
      ImagePoint(180, 730),
    ]);
    final result = _align(degenerate, page);

    expect(result.isFailure, isTrue);
  });

  test('canonical output dimensions exactly match PageLayout', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final result = _align(frontal, page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(
      result.value.canonicalPage.size,
      ImageSize(
        width: page.canonicalPageSpec.widthPixels,
        height: page.canonicalPageSpec.heightPixels,
      ),
    );
    final decoded = image.decodePng(result.value.canonicalPage.pngBytes)!;
    expect(decoded.width, page.canonicalPageSpec.widthPixels);
    expect(decoded.height, page.canonicalPageSpec.heightPixels);
  });
}

EngineResult<PageAlignmentResult> _align(image.Image source, PageLayout page) =>
    ArucoAlignmentEngine(
      backend: const OpenCvArucoVisionBackend(),
    ).align(Uint8List.fromList(image.encodePng(source)), page);

image.Image _renderSyntheticPage(PageLayout page) {
  final output = image.Image(
    width: page.canonicalPageSpec.widthPixels,
    height: page.canonicalPageSpec.heightPixels,
    numChannels: 3,
  );
  image.fill(output, color: image.ColorRgb8(255, 255, 255));
  for (final marker in page.markerRegions) {
    final bounds = marker.physicalBounds;
    final left = _physicalX(bounds.left.millimeters, page);
    final top = _physicalY(bounds.top.millimeters, page);
    final right = _physicalX(bounds.right.millimeters, page);
    final bottom = _physicalY(bounds.bottom.millimeters, page);
    _drawMarker(
      output,
      markerId: marker.markerId,
      left: left,
      top: top,
      size: math.min(right - left, bottom - top),
    );
  }
  return output;
}

void _drawMarker(
  image.Image target, {
  required int markerId,
  required int left,
  required int top,
  required int size,
}) {
  final matrix = const OpenCvDictionary4x4MarkerEncoder().encode(markerId);
  image.fillRect(
    target,
    x1: left,
    y1: top,
    x2: left + size - 1,
    y2: top + size - 1,
    color: image.ColorRgb8(255, 255, 255),
  );
  for (var row = 0; row < matrix.totalModules; row++) {
    for (var column = 0; column < matrix.totalModules; column++) {
      if (!matrix.modules[row][column]) continue;
      final x1 = left + (column * size / matrix.totalModules).round();
      final y1 = top + (row * size / matrix.totalModules).round();
      final x2 = left + ((column + 1) * size / matrix.totalModules).round() - 1;
      final y2 = top + ((row + 1) * size / matrix.totalModules).round() - 1;
      image.fillRect(
        target,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        color: image.ColorRgb8(0, 0, 0),
      );
    }
  }
}

void _eraseRegion(
  image.Image target,
  PageLayout page,
  PhysicalRect physicalBounds,
) {
  image.fillRect(
    target,
    x1: _physicalX(physicalBounds.left.millimeters, page) - 2,
    y1: _physicalY(physicalBounds.top.millimeters, page) - 2,
    x2: _physicalX(physicalBounds.right.millimeters, page) + 2,
    y2: _physicalY(physicalBounds.bottom.millimeters, page) + 2,
    color: image.ColorRgb8(255, 255, 255),
  );
}

image.Image _perspectiveWarp(image.Image source, List<ImagePoint> destination) {
  final sourceMat = cv.Mat.fromList(
    source.height,
    source.width,
    cv.MatType.CV_8UC3,
    source.getBytes(order: image.ChannelOrder.bgr),
  );
  final sourceVector = cv.VecPoint2f.generate(4, (index) {
    final points = [
      ImagePoint(0, 0),
      ImagePoint(source.width - 1, 0),
      ImagePoint(source.width - 1, source.height - 1),
      ImagePoint(0, source.height - 1),
    ];
    return cv.Point2f(points[index].x, points[index].y);
  });
  final destinationVector = cv.VecPoint2f.generate(
    4,
    (index) => cv.Point2f(destination[index].x, destination[index].y),
  );
  final homography = cv.getPerspectiveTransform2f(
    sourceVector,
    destinationVector,
  );
  final border = cv.Scalar.all(255);
  final warped = cv.warpPerspective(sourceMat, homography, (
    source.width,
    source.height,
  ), borderValue: border);
  try {
    final (success, bytes) = cv.imencode('.png', warped);
    if (!success) throw StateError('Synthetic perspective encoding failed.');
    return image.decodePng(bytes)!;
  } finally {
    warped.dispose();
    border.dispose();
    homography.dispose();
    destinationVector.dispose();
    sourceVector.dispose();
    sourceMat.dispose();
  }
}

int _physicalX(double millimeters, PageLayout page) =>
    (millimeters /
            page.pageSpec.size.width.millimeters *
            page.canonicalPageSpec.widthPixels)
        .round();

int _physicalY(double millimeters, PageLayout page) =>
    (millimeters /
            page.pageSpec.size.height.millimeters *
            page.canonicalPageSpec.heightPixels)
        .round();
