import 'package:capstone_development/application/camera_scanner/domain/camera_scan_state.dart';
import 'package:capstone_development/debug/scanner_detection_overlay.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/camera/domain/camera_models.dart';
import 'package:capstone_development/engines/camera/domain/live_frame_analysis.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paper outline uses a high-contrast dual stroke', () {
    expect(scannerOverlayOuterStrokeWidth, 4);
    expect(scannerOverlayInnerStrokeWidth, 2);
  });

  test('overlay state maps real tracking and workflow phases', () {
    expect(
      scannerOverlayState(_state(markerIds: const [])),
      ScannerOverlayState.searching,
    );
    expect(
      scannerOverlayState(_state(markerIds: const [10, 11])),
      ScannerOverlayState.partial,
    );
    expect(
      scannerOverlayState(_state(markerIds: const [10, 11, 12, 13])),
      ScannerOverlayState.unstable,
    );
    expect(
      scannerOverlayState(
        _state(
          markerIds: const [10, 11, 12, 13],
          phase: CameraScanPhase.readyToCapture,
        ),
      ),
      ScannerOverlayState.ready,
    );
  });

  test('status gives actionable text without exposing metrics', () {
    expect(
      scannerStatusText(
        _state(markerIds: const [10]),
        pageNumber: 1,
        pageCount: 3,
      ),
      'Keep all 4 markers visible',
    );
    expect(
      scannerStatusText(
        _state(
          markerIds: const [10, 11, 12, 13],
          readiness: CaptureReadinessStatus.tooSmall,
        ),
        pageNumber: 1,
        pageCount: 3,
      ),
      'Move closer',
    );
  });

  testWidgets('overlay paints without a decorative fallback rectangle', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 300,
          height: 400,
          child: ScannerDetectionOverlay(
            points: [],
            state: ScannerOverlayState.searching,
          ),
        ),
      ),
    );

    expect(find.byType(ScannerDetectionOverlay), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('document polygon is preferred over marker quadrilateral', () {
    final state = _state(
      markerIds: const [10, 11, 12, 13],
      document: _document(),
    );
    final geometry = scannerOverlayGeometry(state.cameraState.analysis);

    expect(geometry.source, ScannerOverlayGeometrySource.document);
    expect(geometry.points, _document().geometry.corners);
  });

  test('marker registration does not impersonate physical paper geometry', () {
    final geometry = scannerOverlayGeometry(
      _state(markerIds: const [10, 11, 12, 13]).cameraState.analysis,
    );
    expect(geometry.source, ScannerOverlayGeometrySource.none);
    expect(geometry.points, isEmpty);
  });
}

CameraScanState _state({
  required List<int> markerIds,
  CameraScanPhase phase = CameraScanPhase.tracking,
  CaptureReadinessStatus readiness = CaptureReadinessStatus.unstable,
  DetectedDocument? document,
}) => CameraScanState(
  phase: phase,
  cameraState: CameraEngineState(
    lifecycle: CameraLifecycleState.analyzing,
    diagnostics: const CameraDiagnostics(),
    readiness: CaptureReadiness(
      status: readiness,
      stableFrameCount: 1,
      requiredStableFrameCount: 3,
    ),
    analysis: CameraAnalysisState(
      tracking: MarkerTrackingState(
        detectedMarkerIds: markerIds,
        registrationPoints: markerIds.length == 4
            ? [
                ImagePoint(10, 10),
                ImagePoint(90, 10),
                ImagePoint(90, 90),
                ImagePoint(10, 90),
              ]
            : const [],
      ),
      quality: const FrameQuality(
        brightness: 180,
        sharpness: 100,
        pageAreaRatio: 0.5,
        perspectiveRatio: 1,
      ),
      readiness: CaptureReadiness(
        status: readiness,
        stableFrameCount: 1,
        requiredStableFrameCount: 3,
      ),
      stabilityScore: 0.5,
      processingDuration: Duration.zero,
      sourceFrameSize: ImageSize(width: 100, height: 100),
      analysisFrameSize: ImageSize(width: 100, height: 100),
      analysisScaleX: 1,
      analysisScaleY: 1,
      timings: CameraAnalysisTimings.zero,
      document: document,
    ),
  ),
);

DetectedDocument _document() => DetectedDocument(
  geometry: DocumentGeometry(
    corners: [
      ImagePoint(15, 10),
      ImagePoint(85, 10),
      ImagePoint(90, 90),
      ImagePoint(10, 90),
    ],
    areaRatio: 0.6,
    centroid: ImagePoint(50, 50),
    perspectiveRatio: 1.2,
  ),
  confidence: 0.8,
);
