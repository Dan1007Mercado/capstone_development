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

enum ScannerOverlayGeometrySource { none, document, markerRegistration }

const scannerOverlayOuterStrokeWidth = 4.0;
const scannerOverlayInnerStrokeWidth = 2.0;

final class ScannerOverlayGeometry {
  const ScannerOverlayGeometry({required this.points, required this.source});

  const ScannerOverlayGeometry.none()
    : points = const [],
      source = ScannerOverlayGeometrySource.none;

  final List<ImagePoint> points;
  final ScannerOverlayGeometrySource source;
}

ScannerOverlayGeometry scannerOverlayGeometry(CameraAnalysisState? analysis) {
  final documentCorners = analysis?.document?.geometry.corners;
  if (documentCorners?.length == 4) {
    return ScannerOverlayGeometry(
      points: documentCorners!,
      source: ScannerOverlayGeometrySource.document,
    );
  }
  final registrationPoints = analysis?.tracking.registrationPoints;
  if (registrationPoints?.length == 4) {
    return ScannerOverlayGeometry(
      points: registrationPoints!,
      source: ScannerOverlayGeometrySource.markerRegistration,
    );
  }
  return const ScannerOverlayGeometry.none();
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
      final document = state.cameraState.analysis?.document;
      final count =
          state.cameraState.analysis?.tracking.detectedMarkerIds.length ?? 0;
      if (count == 0 && document == null) {
        return ScannerOverlayState.searching;
      }
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
  final analysis = state.cameraState.analysis;
  if (analysis?.gateResult.fallbackProbe == true &&
      readiness != CaptureReadinessStatus.ready &&
      analysis?.document == null) {
    return 'Verifying sheet...';
  }
  return switch (scannerOverlayState(state)) {
    ScannerOverlayState.searching => 'Searching for sheet...',
    ScannerOverlayState.partial =>
      analysis?.document != null
          ? 'Hold the full sheet in view'
          : 'Keep all 4 markers visible',
    ScannerOverlayState.unstable => switch (readiness) {
      CaptureReadinessStatus.tooSmall => 'Move closer',
      CaptureReadinessStatus.tooSkewed => 'Reduce page tilt',
      CaptureReadinessStatus.tooBlurry => 'Hold steady',
      CaptureReadinessStatus.tooDark => 'Find brighter light',
      CaptureReadinessStatus.tooBright => 'Reduce glare',
      CaptureReadinessStatus.verifyingMarkers ||
      CaptureReadinessStatus.documentFound => 'Verifying sheet...',
      CaptureReadinessStatus.unknownSheet =>
        'Sheet does not belong to selected template',
      CaptureReadinessStatus.searching => 'Searching for sheet...',
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
    this.geometrySource = ScannerOverlayGeometrySource.none,
    super.key,
  });

  final List<ImagePoint> points;
  final ScannerOverlayState state;
  final ScannerOverlayGeometrySource geometrySource;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<List<ImagePoint>>(
    tween: _QuadrilateralTween(end: points),
    duration: const Duration(milliseconds: 120),
    curve: Curves.easeOut,
    builder: (context, value, _) => CustomPaint(
      painter: _ScannerDetectionPainter(
        points: value,
        state: state,
        geometrySource: geometrySource,
      ),
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
  const _ScannerDetectionPainter({
    required this.points,
    required this.state,
    required this.geometrySource,
  });

  final List<ImagePoint> points;
  final ScannerOverlayState state;
  final ScannerOverlayGeometrySource geometrySource;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length != 4) return;
    final color = switch (state) {
      ScannerOverlayState.ready ||
      ScannerOverlayState.success => Colors.greenAccent,
      ScannerOverlayState.failure => Colors.redAccent,
      ScannerOverlayState.partial || ScannerOverlayState.unstable =>
        geometrySource == ScannerOverlayGeometrySource.document
            ? Colors.white
            : Colors.amberAccent,
      _ => Colors.white,
    };
    final path = Path()..moveTo(points.first.x, points.first.y);
    for (final point in points.skip(1)) {
      path.lineTo(point.x, point.y);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = scannerOverlayOuterStrokeWidth,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = scannerOverlayInnerStrokeWidth,
    );
  }

  @override
  bool shouldRepaint(_ScannerDetectionPainter oldDelegate) =>
      oldDelegate.state != state ||
      oldDelegate.geometrySource != geometrySource ||
      !_samePoints(oldDelegate.points, points);

  bool _samePoints(List<ImagePoint> left, List<ImagePoint> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
