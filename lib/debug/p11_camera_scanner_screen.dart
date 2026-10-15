import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../application/camera_scanner/domain/camera_scan_state.dart';
import 'p11_camera_scanner_composition.dart';

class P11CameraScannerScreen extends StatefulWidget {
  const P11CameraScannerScreen({super.key});

  @override
  State<P11CameraScannerScreen> createState() => _P11CameraScannerScreenState();
}

class _P11CameraScannerScreenState extends State<P11CameraScannerScreen>
    with WidgetsBindingObserver {
  late final P11CameraScannerRuntime _runtime;
  late final StreamSubscription<CameraScanState> _subscription;
  late CameraScanState _state;

  @override
  void initState() {
    super.initState();
    assert(kDebugMode, 'P11 camera scanner diagnostics are debug-only.');
    WidgetsBinding.instance.addObserver(this);
    _runtime = createP11CameraScannerRuntime();
    _state = _runtime.coordinator.state;
    _subscription = _runtime.coordinator.states.listen((state) {
      if (!mounted) return;
      setState(() => _state = state);
    });
    unawaited(_runtime.coordinator.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_runtime.coordinator.resume());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_runtime.coordinator.suspend());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription.cancel());
    unawaited(_runtime.coordinator.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _runtime.backend.controller;
    return Scaffold(
      appBar: AppBar(title: const Text('P11 Camera Scanner Diagnostics')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (controller != null && controller.value.isInitialized)
            AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: CameraPreview(controller),
            )
          else
            const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 12),
          P11CameraScannerDiagnosticsPanel(
            state: _state,
            onCapture: () => unawaited(_runtime.coordinator.captureAndScan()),
            onReset: () => _runtime.coordinator.reset(),
          ),
        ],
      ),
    );
  }
}

class P11CameraScannerDiagnosticsPanel extends StatelessWidget {
  const P11CameraScannerDiagnosticsPanel({
    required this.state,
    required this.onCapture,
    required this.onReset,
    super.key,
  });

  final CameraScanState state;
  final VoidCallback onCapture;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final camera = state.cameraState;
    final analysis = camera.analysis;
    final preview = camera.previewInfo;
    final result = state.result;
    final summary = result?.summary;
    final timings = state.finalScanTimings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Workflow: ${state.phase.name}'),
        Text('Camera lifecycle: ${camera.lifecycle.name}'),
        Text(
          'Preview: ${preview == null ? 'unavailable' : '${preview.width}x${preview.height}'}',
        ),
        Text(
          'Analysis: ${analysis == null ? 'unavailable' : '${analysis.analysisFrameSize.width}x${analysis.analysisFrameSize.height}'}',
        ),
        Text(
          'Analysis FPS: ${camera.diagnostics.estimatedAnalysisFps.toStringAsFixed(1)}',
        ),
        Text(
          'Marker IDs: ${analysis?.tracking.detectedMarkerIds ?? const <int>[]}',
        ),
        Text('Readiness: ${camera.readiness.status.name}'),
        Text(
          'Stable frames: ${camera.readiness.stableFrameCount}/'
          '${camera.readiness.requiredStableFrameCount}',
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: state.canCapture ? onCapture : null,
          child: const Text('Capture & Scan'),
        ),
        if (state.phase == CameraScanPhase.scanCompleted ||
            state.phase == CameraScanPhase.scanFailed)
          OutlinedButton(
            onPressed: onReset,
            child: const Text('Retry / Scan Another'),
          ),
        const SizedBox(height: 8),
        Text('Scan status: ${result?.pageState.name ?? state.phase.name}'),
        if (result != null) ...[
          Text('Template ID: ${result.templateId.value}'),
          Text('Template version: ${result.templateVersion.value}'),
          Text('Page ID: ${result.pageId.value}'),
          const Text('Alignment status: aligned'),
          Text('Question count: ${summary!.totalQuestions}'),
          Text('MARKED: ${summary.marked}'),
          Text('BLANK: ${summary.blank}'),
          Text('MULTIPLE: ${summary.multiple}'),
          Text('AMBIGUOUS: ${summary.ambiguous}'),
          Text('INVALID: ${summary.invalid}'),
          Text(
            'Review required: ${result.pageState.name != 'accepted' ? 'yes' : 'no'}',
          ),
          for (final question in result.questions)
            Text('${question.questionId.value}: ${question.state.name}'),
        ],
        Text('Capture: ${_milliseconds(timings.captureDuration)} ms'),
        Text('Byte load: ${_milliseconds(timings.byteLoadDuration)} ms'),
        Text('P9 scanner: ${_milliseconds(timings.scannerDuration)} ms'),
        Text('Capture-to-result: ${_milliseconds(timings.totalDuration)} ms'),
        if (state.error != null)
          SelectableText(
            '${state.error!.code}: ${state.error!.message}\n'
            '${state.error!.details}',
          ),
      ],
    );
  }
}

String _milliseconds(Duration duration) =>
    (duration.inMicroseconds / 1000).toStringAsFixed(1);
