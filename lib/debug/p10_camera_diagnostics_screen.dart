import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../engines/camera/application/camera_engine.dart';
import '../engines/camera/domain/camera_models.dart';
import '../engines/camera/infrastructure/flutter_camera_backend.dart';
import '../engines/camera/infrastructure/isolate_camera_analysis_worker.dart';

class P10CameraDiagnosticsScreen extends StatefulWidget {
  const P10CameraDiagnosticsScreen({super.key});

  @override
  State<P10CameraDiagnosticsScreen> createState() =>
      _P10CameraDiagnosticsScreenState();
}

class _P10CameraDiagnosticsScreenState extends State<P10CameraDiagnosticsScreen>
    with WidgetsBindingObserver {
  late final FlutterCameraBackend _backend;
  late final CameraEngine _engine;
  StreamSubscription<CameraEngineState>? _subscription;
  CameraEngineState _state = const CameraEngineState.uninitialized();
  String? _captureMessage;

  @override
  void initState() {
    super.initState();
    assert(kDebugMode, 'P10 camera diagnostics are debug-only.');
    WidgetsBinding.instance.addObserver(this);
    _backend = FlutterCameraBackend();
    _engine = CameraEngine(
      backend: _backend,
      analyzer: IsolateCameraAnalysisWorker(),
    );
    _subscription = _engine.states.listen((state) {
      if (!mounted) return;
      setState(() => _state = state);
    });
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final initialized = await _engine.initialize();
    if (initialized.isSuccess) await _engine.startAnalysis();
  }

  Future<void> _capture() async {
    setState(() => _captureMessage = 'Capturing high-quality still...');
    final result = await _engine.capture();
    if (!mounted) return;
    setState(() {
      _captureMessage = result.isSuccess
          ? 'Captured ${result.value.encodedBytes.length} bytes via still API.'
          : '${result.error.code}: ${result.error.message}';
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_resume());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_engine.suspend());
    }
  }

  Future<void> _resume() async {
    final resumed = await _engine.resume();
    if (resumed.isSuccess) await _engine.startAnalysis();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    unawaited(_engine.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _backend.controller;
    final analysis = _state.analysis;
    final preview = _state.previewInfo;
    final diagnostics = _state.diagnostics;
    final timings = analysis?.timings;
    return Scaffold(
      appBar: AppBar(title: const Text('P10 Camera Diagnostics')),
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
          ElevatedButton(
            onPressed:
                _state.lifecycle == CameraLifecycleState.ready ||
                    _state.lifecycle == CameraLifecycleState.analyzing
                ? _capture
                : null,
            child: const Text('Capture High-Quality Still'),
          ),
          if (_captureMessage != null) Text(_captureMessage!),
          const SizedBox(height: 12),
          Text('Lifecycle: ${_state.lifecycle.name}'),
          Text(
            'Preview: ${preview == null ? 'unavailable' : '${preview.width}x${preview.height}'}',
          ),
          Text(
            'Analysis FPS: ${diagnostics.estimatedAnalysisFps.toStringAsFixed(1)}',
          ),
          Text(
            'Source frame: ${analysis == null ? 'unavailable' : '${analysis.sourceFrameSize.width}x${analysis.sourceFrameSize.height}'}',
          ),
          Text(
            'Analysis image: ${analysis == null ? 'unavailable' : '${analysis.analysisFrameSize.width}x${analysis.analysisFrameSize.height}'}',
          ),
          Text(
            'Resize scale: ${analysis == null ? 'unavailable' : '${analysis.analysisScaleX.toStringAsFixed(3)}x${analysis.analysisScaleY.toStringAsFixed(3)}'}',
          ),
          Text(
            'Total processing: ${_milliseconds(analysis?.processingDuration)} ms '
            '(average ${_milliseconds(diagnostics.averageAnalysisDuration)} ms)',
          ),
          Text(
            'Materialization: ${_milliseconds(timings?.materializationDuration)} ms',
          ),
          Text(
            'Isolate transfer/start wait: ${_milliseconds(timings?.isolateOverheadDuration)} ms',
          ),
          Text(
            'Preparation/downscale: ${_milliseconds(timings?.preparationDuration)} ms',
          ),
          Text('Sharpness: ${_milliseconds(timings?.sharpnessDuration)} ms'),
          Text(
            'ArUco detection: ${_milliseconds(timings?.arucoDetectionDuration)} ms',
          ),
          Text(
            'Geometry/remap: ${_milliseconds(timings?.geometryDuration)} ms',
          ),
          Text('Worker total: ${_milliseconds(timings?.workerDuration)} ms'),
          Text('Received frames: ${diagnostics.receivedFrameCount}'),
          Text('Accepted frames: ${diagnostics.acceptedFrameCount}'),
          Text('Processed frames: ${diagnostics.processedFrameCount}'),
          Text('Dropped frames: ${diagnostics.droppedFrameCount}'),
          Text(
            'Paper-edge acquisitions/losses: '
            '${diagnostics.paperEdgeAcquisitionCount}/'
            '${diagnostics.paperEdgeLossCount}',
          ),
          Text(
            'ArUco opportunity ratio: '
            '${(diagnostics.arucoAttemptRatio * 100).toStringAsFixed(1)}%',
          ),
          Text(
            'First marker/identity/ready: '
            '${_milliseconds(diagnostics.timeToFirstMarker)}/'
            '${_milliseconds(diagnostics.timeToFirstIdentity)}/'
            '${_milliseconds(diagnostics.timeToReady)} ms',
          ),
          Text(
            'Marker IDs: ${analysis?.tracking.detectedMarkerIds ?? const <int>[]}',
          ),
          Text('Readiness: ${_state.readiness.status.name}'),
          Text(
            'Stable frames: ${_state.readiness.stableFrameCount}/'
            '${_state.readiness.requiredStableFrameCount}',
          ),
          Text(
            'Brightness: ${analysis?.quality.brightness.toStringAsFixed(1) ?? 'unavailable'}',
          ),
          Text(
            'Sharpness: ${analysis?.quality.sharpness.toStringAsFixed(1) ?? 'unavailable'}',
          ),
          Text(
            'Stability: ${analysis?.stabilityScore.toStringAsFixed(2) ?? 'unavailable'}',
          ),
          Text('Auto-capture request: ${_state.autoCaptureRequested}'),
          if (_state.error != null) ...[
            const SizedBox(height: 8),
            SelectableText(
              '${_state.error!.code}: ${_state.error!.message}\n'
              '${_state.error!.details}',
            ),
          ],
        ],
      ),
    );
  }
}

String _milliseconds(Duration? duration) =>
    ((duration?.inMicroseconds ?? 0) / 1000).toStringAsFixed(1);
