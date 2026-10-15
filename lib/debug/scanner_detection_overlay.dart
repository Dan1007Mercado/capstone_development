import 'package:flutter/material.dart';

import '../application/camera_scanner/domain/camera_scan_state.dart';
import '../engines/aruco/domain/image_geometry.dart';
import '../engines/camera/domain/camera_models.dart';

enum ScannerOverlayState {
  searching,
  partial,
  unstable,
  ready,
  capturing,
  processing,
  success,
  failure,
}

ScannerOverlayState scannerOverlayState(CameraScanState state) {
  switch (state.phase) {
    case CameraScanPhase.capturing:
      return ScannerOverlayState.capturing;
    case CameraScanPhase.scanning:
      return ScannerOverlayState.processing;
    case CameraScanPhase.scanCompleted:
      return ScannerOverlayState.success;
    case CameraScanPhase.scanFailed:
      return ScannerOverlayState.failure;
    case CameraScanPhase.readyToCapture:
      return ScannerOverlayState.ready;
    case CameraScanPhase.idle:
    case CameraScanPhase.cameraInitializing:
    case CameraScanPhase.cameraReady:
      return ScannerOverlayState.searching;
    case CameraScanPhase.tracking:
      final count =
          state.cameraState.analysis?.tracking.detectedMarkerIds.length ?? 0;
      if (count == 0) return ScannerOverlayState.searching;
      if (count < 4) return ScannerOverlayState.partial;
      return ScannerOverlayState.unstable;
    case CameraScanPhase.disposed:
      return ScannerOverlayState.failure;
  }
}

String scannerStatusText(
  CameraScanState state, {
  required int pageNumber,
  required int pageCount,
  bool pageDetected = false,
  bool pageAlreadyCompleted = false,
}) {
  if (pageAlreadyCompleted) return 'Page $pageNumber already scanned.';
  final resolutionCode =
      state.cameraState.analysis?.tracking.pageResolutionErrorCode;
  if (resolutionCode == 'SCAN_UNKNOWN_PAGE_MARKERS' ||
      resolutionCode == 'SCAN_DUPLICATE_PAGE_MARKERS') {
    return 'Sheet does not belong to selected template';
  }
  final readiness = state.cameraState.readiness.status;
  return switch (scannerOverlayState(state)) {
    ScannerOverlayState.searching => 'Searching for sheet...',
    ScannerOverlayState.partial => 'Keep all 4 markers visible',
    ScannerOverlayState.unstable => switch (readiness) {
      CaptureReadinessStatus.tooSmall => 'Move closer',
      CaptureReadinessStatus.tooSkewed => 'Reduce page tilt',
      CaptureReadinessStatus.tooBlurry => 'Hold steady',
      CaptureReadinessStatus.tooDark => 'Find brighter light',
      CaptureReadinessStatus.tooBright => 'Reduce glare',
      _ =>
        pageDetected
            ? 'Page $pageNumber detected · Hold steady'
            : 'Hold steady',
    },
    ScannerOverlayState.ready => 'Page $pageNumber detected · Ready',
    ScannerOverlayState.capturing => 'Capturing Page $pageNumber...',
    ScannerOverlayState.processing =>
      'Processing page $pageNumber of $pageCount',
    ScannerOverlayState.success => 'Page $pageNumber scanned',
    ScannerOverlayState.failure =>
      state.error?.message ?? 'Scanner unavailable',
  };
}

/// Draws only the real tracked page quadrilateral supplied by CameraEngine.
class ScannerDetectionOverlay extends StatelessWidget {
  const ScannerDetectionOverlay({
    required this.points,
    required this.state,
    super.key,
  });

  final List<ImagePoint> points;
  final ScannerOverlayState state;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<List<ImagePoint>>(
    tween: _QuadrilateralTween(end: points),
    duration: const Duration(milliseconds: 120),
    curve: Curves.easeOut,
    builder: (context, value, _) => CustomPaint(
      painter: _ScannerDetectionPainter(points: value, state: state),
    ),
  );
}

final class _QuadrilateralTween extends Tween<List<ImagePoint>> {
  _QuadrilateralTween({required super.end}) : super(begin: const []);

  @override
  List<ImagePoint> lerp(double t) {
    final start = begin ?? const [];
    final finish = end ?? const [];
    if (start.length != 4 || finish.length != 4) return finish;
    return [
      for (var index = 0; index < 4; index++)
        ImagePoint(
          start[index].x + (finish[index].x - start[index].x) * t,
          start[index].y + (finish[index].y - start[index].y) * t,
        ),
    ];
  }
}

final class _ScannerDetectionPainter extends CustomPainter {
  const _ScannerDetectionPainter({required this.points, required this.state});

  final List<ImagePoint> points;
  final ScannerOverlayState state;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length != 4) return;
    final color = switch (state) {
      ScannerOverlayState.ready ||
      ScannerOverlayState.success => Colors.greenAccent,
      ScannerOverlayState.failure => Colors.redAccent,
      _ => Colors.amberAccent,
    };
    final path = Path()..moveTo(points.first.x, points.first.y);
    for (final point in points.skip(1)) {
      path.lineTo(point.x, point.y);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final cornerPaint = Paint()..color = color;
    for (final point in points) {
      canvas.drawCircle(Offset(point.x, point.y), 5, cornerPaint);
    }
  }

  @override
  bool shouldRepaint(_ScannerDetectionPainter oldDelegate) =>
      oldDelegate.state != state || !_samePoints(oldDelegate.points, points);

  bool _samePoints(List<ImagePoint> left, List<ImagePoint> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
