import 'package:capstone_development/application/camera_scanner/domain/camera_scan_state.dart';
import 'package:capstone_development/application/camera_scanner/domain/detected_page_geometry.dart';
import 'package:capstone_development/debug/scanner_detection_overlay.dart';
import 'package:capstone_development/debug/p5_native_validation_fixture.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/camera/domain/camera_models.dart';
import 'package:capstone_development/engines/camera/domain/live_frame_analysis.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('page outline uses a high-contrast dual stroke', () {
    expect(scannerOverlayOuterStrokeWidth, 4);
    expect(scannerOverlayInnerStrokeWidth, 2);
  });

  test('polygon colors follow search, adjust, ready, and rejection states', () {
    expect(scannerOverlayColor(ScannerOverlayState.searching), Colors.white);
    expect(
      scannerOverlayColor(ScannerOverlayState.partial),
      Colors.amberAccent,
    );
    expect(
      scannerOverlayColor(ScannerOverlayState.unstable),
      Colors.amberAccent,
    );
    expect(scannerOverlayColor(ScannerOverlayState.ready), Colors.greenAccent);
    expect(scannerOverlayColor(ScannerOverlayState.processing), Colors.white);
    expect(scannerOverlayColor(ScannerOverlayState.failure), Colors.redAccent);
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
        _state(markerIds: const []),
        pageNumber: 1,
        pageCount: 3,
      ),
      'Looking for answer sheet...',
    );
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

  test('four valid markers project the authoritative page outline', () {
    final state = _state(
      markerIds: const [10, 11, 12, 13],
      document: _document(),
    );
    final page = buildP5NativeValidationPage();
    final analysis = state.cameraState.analysis!;
    final geometry = scannerOverlayGeometry(analysis, page: page);

    expect(geometry.source, ScannerOverlayGeometrySource.markerProjection);
    expect(
      geometry.points,
      projectDetectedPageOutline(
        page: page,
        sourceRegistrationPoints: analysis.tracking.registrationPoints,
      ),
    );
  });

  test('marker polygon remains available without a paper detection', () {
    final geometry = scannerOverlayGeometry(
      _state(markerIds: const [10, 11, 12, 13]).cameraState.analysis,
      page: buildP5NativeValidationPage(),
    );
    expect(geometry.source, ScannerOverlayGeometrySource.markerProjection);
    expect(geometry.points, hasLength(4));
  });

  test(
    'paper edge is only a fallback when marker projection is unavailable',
    () {
      final geometry = scannerOverlayGeometry(
        _state(markerIds: const [], document: _document()).cameraState.analysis,
        page: buildP5NativeValidationPage(),
        allowPaperEdgeVisualization: true,
      );
      expect(geometry.source, ScannerOverlayGeometrySource.paperEdge);
      expect(geometry.points, _document().geometry.corners);
    },
  );

  test('paper edges do not create authoritative geometry by default', () {
    final geometry = scannerOverlayGeometry(
      _state(markerIds: const [], document: _document()).cameraState.analysis,
      page: buildP5NativeValidationPage(),
    );

    expect(geometry.source, ScannerOverlayGeometrySource.none);
    expect(geometry.points, isEmpty);
  });

  test('processing and success text describe the durable workflow stage', () {
    expect(
      scannerStatusText(
        _state(markerIds: const [], phase: CameraScanPhase.scanning),
        pageNumber: 1,
        pageCount: 2,
      ),
      'Reading your answers...',
    );
    expect(
      scannerStatusText(
        _state(markerIds: const [], phase: CameraScanPhase.scanCompleted),
        pageNumber: 1,
        pageCount: 2,
      ),
      'Sheet successfully recorded',
    );
  });

  test('missing markers do not retain a prior marker outline', () {
    final page = buildP5NativeValidationPage();
    final detected = scannerOverlayGeometry(
      _state(markerIds: const [10, 11, 12, 13]).cameraState.analysis,
      page: page,
    );
    final missing = scannerOverlayGeometry(
      _state(markerIds: const []).cameraState.analysis,
      page: page,
    );

    expect(detected.points, hasLength(4));
    expect(missing.source, ScannerOverlayGeometrySource.none);
    expect(missing.points, isEmpty);
  });

  test('resolved page identity rejects a mismatched page layout', () {
    final geometry = scannerOverlayGeometry(
      _state(
        markerIds: const [10, 11, 12, 13],
        resolvedPageId: PageId('another-page'),
      ).cameraState.analysis,
      page: buildP5NativeValidationPage(),
    );

    expect(geometry.source, ScannerOverlayGeometrySource.none);
  });
}

CameraScanState _state({
  required List<int> markerIds,
  CameraScanPhase phase = CameraScanPhase.tracking,
  CaptureReadinessStatus readiness = CaptureReadinessStatus.unstable,
  DetectedDocument? document,
  PageId? resolvedPageId,
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
        resolvedPageId: resolvedPageId,
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
