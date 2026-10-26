import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../application/camera_scanner/domain/camera_scan_state.dart';
import '../engines/camera/domain/camera_models.dart';
import '../engines/layout/domain/page_layout.dart';
import 'omr_camera_preview.dart';
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
  int _selectedPageIndex = 0;

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
            OmrCameraPreview(
              controller: controller,
              pageLayout: _runtime.layout.pages[_selectedPageIndex],
              isReady: _state.cameraState.readiness.isReady,
            )
          else
            const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            ),
          const SizedBox(height: 12),
          _ExpectedPageSelector(
            pages: _runtime.layout.pages,
            selectedIndex: _selectedPageIndex,
            enabled: !_state.operationInProgress,
            onChanged: (index) {
              final updated = _runtime.coordinator.updateContext(
                _runtime.contextForPage(index),
              );
              if (updated.isSuccess) {
                setState(() => _selectedPageIndex = index);
              }
            },
          ),
          const SizedBox(height: 12),
          P11CameraScannerDiagnosticsPanel(
            state: _state,
            expectedPage: _runtime.layout.pages[_selectedPageIndex],
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
    this.expectedPage,
    super.key,
  });

  final CameraScanState state;
  final VoidCallback onCapture;
  final VoidCallback onReset;
  final PageLayout? expectedPage;

  @override
  Widget build(BuildContext context) {
    final camera = state.cameraState;
    final analysis = camera.analysis;
    final preview = camera.previewInfo;
    final result = state.result;
    final summary = result?.summary;
    final timings = state.finalScanTimings;
    final scanDiagnostics = result?.diagnostics;
    final alignment = scanDiagnostics?.alignment;
    final stages = scanDiagnostics?.stageDurations;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Workflow: ${state.phase.name}'),
        Text('Camera lifecycle: ${camera.lifecycle.name}'),
        Text(
          'Source preview: ${preview == null ? 'unavailable' : '${preview.width}x${preview.height}'}',
        ),
        const Text('Display viewport: portrait 3:4 (center crop)'),
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
        Text(
          'Frames received/accepted/processed/dropped: '
          '${camera.diagnostics.receivedFrameCount}/'
          '${camera.diagnostics.acceptedFrameCount}/'
          '${camera.diagnostics.processedFrameCount}/'
          '${camera.diagnostics.droppedFrameCount}',
        ),
        Text(
          'Paper-edge detections: '
          '${camera.diagnostics.paperEdgeDetectionCount}',
        ),
        Text(
          'Paper-edge detector failures: '
          '${camera.diagnostics.paperEdgeDetectionFailureCount}',
        ),
        Text(
          'Paper-edge temporary losses: '
          '${camera.diagnostics.paperEdgeTemporaryLossCount}',
        ),
        Text(
          'Paper-edge acquisitions/losses: '
          '${camera.diagnostics.paperEdgeAcquisitionCount}/'
          '${camera.diagnostics.paperEdgeLossCount}',
        ),
        if (camera.diagnostics.lastPaperEdgeDetectionError case final error?)
          Text('Latest paper-edge detector diagnostic: $error'),
        Text(
          'Recoverable analysis failures: '
          '${camera.diagnostics.recoverableAnalysisFailureCount}',
        ),
        if (camera.diagnostics.lastRecoverableAnalysisError case final error?)
          Text('Latest recoverable analysis diagnostic: $error'),
        if (camera.diagnostics.lastErrorCode case final code?)
          Text(
            'Latest camera error: $code '
            '[${camera.diagnostics.lastErrorStage}] '
            '${camera.diagnostics.lastErrorRootCause}',
          ),
        Text(
          'Lifecycle transitions: '
          '${camera.diagnostics.lifecycleTransitionCount} '
          '(${camera.diagnostics.previousLifecycle?.name ?? 'none'} -> '
          '${camera.diagnostics.currentLifecycle.name})',
        ),
        Text(
          'ArUco opportunities: '
          '${camera.diagnostics.arucoAttemptedFrameCount}',
        ),
        Text(
          'ArUco opportunity ratio: '
          '${(camera.diagnostics.arucoAttemptRatio * 100).toStringAsFixed(1)}%',
        ),
        Text(
          'Average live/paper edge/ArUco: '
          '${_milliseconds(camera.diagnostics.averageAnalysisDuration)}/'
          '${_milliseconds(camera.diagnostics.averagePaperEdgeDetectionDuration)}/'
          '${_milliseconds(camera.diagnostics.averageArucoDuration)} ms',
        ),
        Text(
          'First recognition to ready: '
          '${_milliseconds(camera.diagnostics.firstRecognitionToReadyDuration)} ms',
        ),
        Text(
          'First marker/identity/ready: '
          '${_milliseconds(camera.diagnostics.timeToFirstMarker)}/'
          '${_milliseconds(camera.diagnostics.timeToFirstIdentity)}/'
          '${_milliseconds(camera.diagnostics.timeToReady)} ms',
        ),
        for (final status in CaptureReadinessStatus.values)
          Text(
            'Readiness ${status.name}: '
            '${_milliseconds(camera.diagnostics.readinessDurations[status])} ms',
          ),
        Text('Scan status: ${result?.pageState.name ?? state.phase.name}'),
        Text(
          'Final scanner worker: '
          '${state.phase == CameraScanPhase.scanning
              ? 'running'
              : state.phase == CameraScanPhase.scanCompleted
              ? 'completed'
              : state.phase == CameraScanPhase.scanFailed
              ? 'failed'
              : 'idle'}',
        ),
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
            ExpansionTile(
              title: Text(
                '${question.questionId.value}: ${question.state.name}',
              ),
              subtitle: Text(
                'selected=${question.selectedOptionIds.map((id) => id.value).toList()} '
                'top=${question.diagnostics.topScore.toStringAsFixed(3)} '
                'second=${question.diagnostics.secondScore.toStringAsFixed(3)} '
                'gap=${question.diagnostics.scoreGap.toStringAsFixed(3)} '
                'reason=${question.diagnostics.reason.name}',
              ),
              children: [
                if (question.numericSelection != null)
                  for (final column in question.numericSelection!.columns)
                    ListTile(
                      dense: true,
                      title: Text(
                        'Column ${column.columnIndex + 1}: '
                        '${column.state.name}, digit=${column.selectedDigit ?? '-'}',
                      ),
                    ),
                for (final bubble in question.bubbleDecisions)
                  ListTile(
                    dense: true,
                    title: Text(
                      '${bubble.optionId?.value ?? 'column ${bubble.numericColumnIndex! + 1} / digit ${bubble.numericDigitValue}'} '
                      '${bubble.state.name}',
                    ),
                    subtitle: Text(
                      'fill=${bubble.fillRatio.toStringAsFixed(3)} '
                      'darkness=${bubble.normalizedDarkness.toStringAsFixed(3)} '
                      'contrast=${bubble.darknessContrast.toStringAsFixed(2)}\n'
                      'mean=${bubble.interiorMeanIntensity.toStringAsFixed(1)} '
                      'median=${bubble.interiorMedianIntensity.toStringAsFixed(1)} '
                      'baseline=${bubble.localBaselineIntensity.toStringAsFixed(1)} '
                      'foreground=${bubble.foregroundPixelCount}\n'
                      'category=${bubble.category.name} '
                      'score=${bubble.combinedScore.toStringAsFixed(3)} '
                      'usable=${bubble.qualityUsable} '
                      'clipping=${bubble.quality.clipping.name} '
                      'baselineForeground=${bubble.quality.baselineForegroundRatio.toStringAsFixed(3)}',
                    ),
                  ),
              ],
            ),
        ],
        Text(
          'Stop analysis: ${_milliseconds(timings.stopAnalysisDuration)} ms',
        ),
        Text('Capture: ${_milliseconds(timings.captureDuration)} ms'),
        Text('Transfer/load: ${_milliseconds(timings.byteLoadDuration)} ms'),
        Text('Decode: ${_milliseconds(alignment?.decodeDuration)} ms'),
        Text(
          'Detection resize/preparation: '
          '${_milliseconds(alignment?.detectionPreparationDuration)} ms',
        ),
        Text('ArUco detect: ${_milliseconds(alignment?.detectionDuration)} ms'),
        Text(
          'Page resolution: '
          '${_milliseconds(alignment?.pageResolutionDuration)} ms',
        ),
        Text(
          'Coordinate remap: '
          '${_milliseconds(alignment?.coordinateRemapDuration)} ms',
        ),
        Text(
          'Marker correspondence: '
          '${_milliseconds(alignment?.correspondenceDuration)} ms',
        ),
        Text('Homography: ${_milliseconds(alignment?.homographyDuration)} ms'),
        Text(
          'Warp/canonicalization: ${_milliseconds(alignment?.warpDuration)} ms',
        ),
        Text('Preprocessing: ${_milliseconds(stages?.preprocessing)} ms'),
        Text(
          '  Denoise: ${_milliseconds(scanDiagnostics?.preprocessing.stageDurations.denoise)} ms',
        ),
        Text(
          '  Illumination: ${_milliseconds(scanDiagnostics?.preprocessing.stageDurations.illuminationNormalization)} ms',
        ),
        Text(
          '  Threshold: ${_milliseconds(scanDiagnostics?.preprocessing.stageDurations.thresholding)} ms',
        ),
        Text(
          '  Statistics: ${_milliseconds(scanDiagnostics?.preprocessing.stageDurations.statistics)} ms',
        ),
        Text('Bubble measurement: ${_milliseconds(stages?.measurement)} ms'),
        Text('Classification: ${_milliseconds(stages?.classification)} ms'),
        Text('Validation/result: ${_milliseconds(stages?.validation)} ms'),
        Text('Worker total: ${_milliseconds(timings.workerDuration)} ms'),
        Text(
          'Worker startup: ${_milliseconds(timings.workerStartupDuration)} ms',
        ),
        Text('Isolate overhead: ${_milliseconds(timings.isolateOverhead)} ms'),
        Text(
          'Worker status: ${timings.workerReused ? 'reused' : 'newly started'}',
        ),
        Text(
          'Source still: ${alignment?.sourceSize == null ? 'unavailable' : '${alignment!.sourceSize!.width}x${alignment.sourceSize!.height}'}',
        ),
        Text(
          'Detection image: ${alignment?.detectionSize == null ? 'unavailable' : '${alignment!.detectionSize!.width}x${alignment.detectionSize!.height}'}',
        ),
        Text(
          'Detection scale: ${alignment == null ? 'unavailable' : '${alignment.detectionScaleX.toStringAsFixed(3)} x ${alignment.detectionScaleY.toStringAsFixed(3)}'}',
        ),
        Text(
          'Canonical page: ${alignment?.canonicalSize == null ? 'unavailable' : '${alignment!.canonicalSize!.width}x${alignment.canonicalSize!.height}'}',
        ),
        Text('Scanner request: ${_milliseconds(timings.scannerDuration)} ms'),
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

class _ExpectedPageSelector extends StatelessWidget {
  const _ExpectedPageSelector({
    required this.pages,
    required this.selectedIndex,
    required this.enabled,
    required this.onChanged,
  });

  final List<PageLayout> pages;
  final int selectedIndex;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final page = pages[selectedIndex];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<int>(
          initialValue: selectedIndex,
          decoration: const InputDecoration(labelText: 'Expected page'),
          items: [
            for (var index = 0; index < pages.length; index++)
              DropdownMenuItem(value: index, child: Text('Page ${index + 1}')),
          ],
          onChanged: enabled
              ? (value) {
                  if (value != null) onChanged(value);
                }
              : null,
        ),
        Text('Expected page: ${selectedIndex + 1} / ${pages.length}'),
        Text('PageId: ${page.pageId.value}'),
        Text(
          'Questions on page: '
          '${page.questionRegions.map((region) => region.questionId.value).join(', ')}',
        ),
      ],
    );
  }
}

String _milliseconds(Duration? duration) =>
    ((duration ?? Duration.zero).inMicroseconds / 1000).toStringAsFixed(1);
