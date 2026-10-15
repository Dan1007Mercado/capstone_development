import 'package:capstone_development/application/camera_scanner/domain/camera_scan_state.dart';
import 'package:capstone_development/debug/p11_camera_scanner_screen.dart';
import 'package:capstone_development/engines/camera/domain/camera_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('diagnostics panel consumes typed coordinator state', (
    tester,
  ) async {
    var captures = 0;
    var resets = 0;
    final state = CameraScanState(
      phase: CameraScanPhase.readyToCapture,
      cameraState: CameraEngineState(
        lifecycle: CameraLifecycleState.analyzing,
        diagnostics: const CameraDiagnostics(estimatedAnalysisFps: 8.2),
        readiness: const CaptureReadiness(
          status: CaptureReadinessStatus.ready,
          stableFrameCount: 3,
          requiredStableFrameCount: 3,
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: P11CameraScannerDiagnosticsPanel(
              state: state,
              onCapture: () => captures++,
              onReset: () => resets++,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Workflow: readyToCapture'), findsOneWidget);
    expect(find.text('Readiness: ready'), findsOneWidget);
    expect(find.text('Analysis FPS: 8.2'), findsOneWidget);
    await tester.tap(find.text('Capture & Scan'));
    expect(captures, 1);
    expect(resets, 0);
  });
}
