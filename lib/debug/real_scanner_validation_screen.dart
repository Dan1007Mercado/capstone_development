import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../application/camera_scanner/domain/camera_scan_state.dart';
import '../application/camera_scanner/domain/detected_page_geometry.dart';
import '../application/camera_scanner/domain/preview_coordinate_mapper.dart';
import '../application/real_scanner/published_scanner_resolver.dart';
import '../application/real_scanner/real_scanner_runtime.dart';
import '../application/real_scanner/scanner_validation_flow.dart';
import '../application/real_scanner/scanner_validation_session.dart';
import '../core/errors/engine_error.dart';
import '../engines/aruco/domain/image_geometry.dart';
import '../engines/camera/domain/camera_engine_config.dart';
import '../engines/recognition/domain/mark_classification.dart';
import '../engines/scanner/domain/scan_result.dart';
import '../engines/template/application/template_publication_service.dart';
import '../engines/template/domain/template_question.dart';
import 'p11_camera_scanner_screen.dart';
import 'scanner_detection_overlay.dart';

class RealScannerSelectionScreen extends StatefulWidget {
  const RealScannerSelectionScreen({
    required this.publicationService,
    super.key,
  });

  final TemplatePublicationService publicationService;

  @override
  State<RealScannerSelectionScreen> createState() =>
      _RealScannerSelectionScreenState();
}

class _RealScannerSelectionScreenState
    extends State<RealScannerSelectionScreen> {
  late final PublishedScannerResolver _resolver;
  List<PublishedScannerArtifact> _artifacts = const [];
  PublishedScannerArtifact? _selected;
  EngineError? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _resolver = PublishedScannerResolver(
      publicationService: widget.publicationService,
    );
    unawaited(_load());
  }

  Future<void> _load() async {
    final result = await _resolver.listAvailable();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _artifacts = result.valueOrNull ?? const [];
      _selected = _artifacts.isEmpty ? null : _artifacts.first;
      _error = result.errorOrNull;
    });
  }

  void _start() {
    final selected = _selected;
    if (selected == null) {
      setState(() {
        _error = EngineError(
          code: 'PUBLISHED_TEMPLATE_NOT_SELECTED',
          message:
              'Select an exact published template version before scanning.',
        );
      });
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RealScannerCameraScreen(
          session: ScannerValidationSession.start(artifact: selected),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('Real Scanner Validation')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Choose the exact published template and version.'),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_artifacts.isEmpty)
              const Text(
                'No published templates are available. Publish a template in '
                'the template builder first.',
              )
            else
              DropdownButtonFormField<PublishedScannerArtifact>(
                key: const Key('published-template-version-selector'),
                initialValue: selected,
                decoration: const InputDecoration(
                  labelText: 'Published template / version',
                ),
                items: [
                  for (final artifact in _artifacts)
                    DropdownMenuItem(
                      value: artifact,
                      child: Text(
                        '${artifact.template.name} · v${artifact.templateVersion.value}',
                      ),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _selected = value;
                  _error = null;
                }),
              ),
            if (selected != null) ...[
              const SizedBox(height: 12),
              Text('Template ID: ${selected.templateId.value}'),
              Text('Version: ${selected.templateVersion.value}'),
              Text('Pages: ${selected.layout.pages.length}'),
              for (final page in selected.layout.pages)
                Text('Page ${page.pageIndex + 1}: ${page.pageId.value}'),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              SelectableText('${error.code}: ${error.message}'),
            ],
            const Spacer(),
            FilledButton.icon(
              key: const Key('start-real-scanner'),
              onPressed: selected == null ? null : _start,
              icon: const Icon(Icons.document_scanner),
              label: const Text('Start Scanner'),
            ),
          ],
        ),
      ),
    );
  }
}

class RealScannerCameraScreen extends StatefulWidget {
  const RealScannerCameraScreen({required this.session, super.key});

  final ScannerValidationSession session;

  @override
  State<RealScannerCameraScreen> createState() =>
      _RealScannerCameraScreenState();
}

class _RealScannerCameraScreenState extends State<RealScannerCameraScreen>
    with WidgetsBindingObserver {
  static const _coordinateMapper = PreviewCoordinateMapper();

  late final RealScannerRuntime _runtime;
  late final ScannerValidationFlowController _flow;
  late final StreamSubscription<CameraScanState> _subscription;
  bool _showDiagnostics = false;
  bool _disposing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runtime = createRealScannerRuntime(widget.session);
    _flow = ScannerValidationFlowController(
      session: widget.session,
      initialCameraState: _runtime.coordinator.state,
    );
    _subscription = _runtime.coordinator.states.listen(_onCoordinatorState);
    unawaited(_runtime.coordinator.initialize());
  }

  void _onCoordinatorState(CameraScanState state) {
    if (!mounted || _disposing) return;
    final action = _flow.handleCoordinatorState(state);
    setState(() {});
    switch (action) {
      case ScannerValidationFlowAction.resultRecorded:
        _runtime.coordinator.updateCompletedPages(_flow.completedPageIds);
        break;
      case ScannerValidationFlowAction.resultRejected:
        _runtime.coordinator.reset();
        break;
      case ScannerValidationFlowAction.stateUpdated:
      case ScannerValidationFlowAction.completionIgnored:
        break;
    }
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

  void _continue() {
    final advanced = _flow.continueAfterReview();
    if (advanced.isFailure) {
      setState(() {});
      return;
    }
    final next = advanced.value;
    if (next.state == ScannerValidationSessionState.complete) {
      setState(() {});
      return;
    }
    _runtime.coordinator.reset();
    setState(() {});
  }

  @override
  void dispose() {
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription.cancel());
    unawaited(_runtime.coordinator.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _flow.session;
    final state = _flow.latestCameraState;
    if (session.state == ScannerValidationSessionState.reviewing) {
      return ScannerReviewStateView(
        session: session,
        reviewResult: _flow.reviewResult,
        onContinue: _continue,
      );
    }
    if (session.state == ScannerValidationSessionState.complete) {
      return _ScannerCompleteScreen(session: session);
    }
    final controller = _runtime.backend.controller;
    final detectedPageId = state.cameraState.analysis?.tracking.resolvedPageId;
    final detectedPage = detectedPageId == null
        ? null
        : session.pages
              .where((page) => page.pageId == detectedPageId)
              .firstOrNull;
    final pageNumber =
        (detectedPage?.pageIndex ?? session.currentPageIndex) + 1;
    final pageCount = session.pages.length;
    final displayedError = _flow.sessionError ?? state.error;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Scan ${session.artifact.template.name}'),
        actions: [
          IconButton(
            tooltip: 'Show diagnostics',
            onPressed: () =>
                setState(() => _showDiagnostics = !_showDiagnostics),
            icon: const Icon(Icons.bug_report_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: controller != null && controller.value.isInitialized
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      final points = _mappedPoints(constraints.biggest, state);
                      final previewAspect = 1 / controller.value.aspectRatio;
                      return ClipRect(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width: previewAspect * 1000,
                                height: 1000,
                                child: CameraPreview(controller),
                              ),
                            ),
                            IgnorePointer(
                              child: ScannerDetectionOverlay(
                                points: points,
                                state: scannerOverlayState(state),
                              ),
                            ),
                            Align(
                              alignment: Alignment.topCenter,
                              child: ScannerStatusBanner(
                                text: scannerStatusText(
                                  state,
                                  pageNumber: pageNumber,
                                  pageCount: pageCount,
                                  pageDetected: detectedPage != null,
                                  pageAlreadyCompleted:
                                      detectedPageId != null &&
                                      session.isPageCompleted(detectedPageId),
                                ),
                                progress:
                                    '${session.completedPageCount} of $pageCount completed',
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  )
                : const Center(child: CircularProgressIndicator()),
          ),
          if (displayedError != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade900,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${displayedError.code}: ${displayedError.message}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  if (state.phase == CameraScanPhase.scanFailed)
                    TextButton(
                      onPressed: () {
                        _runtime.coordinator.reset();
                        _flow.clearSessionError();
                        setState(() {});
                      },
                      child: const Text(
                        'Retry',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          if (_showDiagnostics)
            Container(
              constraints: const BoxConstraints(maxHeight: 280),
              color: Theme.of(context).colorScheme.surface,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: P11CameraScannerDiagnosticsPanel(
                  state: state,
                  expectedPage:
                      detectedPage ??
                      _runtime.coordinator.activeContext.pageLayout,
                  onCapture: () =>
                      unawaited(_runtime.coordinator.captureAndScan()),
                  onReset: () => _runtime.coordinator.reset(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<ImagePoint> _mappedPoints(Size viewport, CameraScanState state) {
    final analysis = state.cameraState.analysis;
    if (analysis == null || analysis.tracking.registrationPoints.length != 4) {
      return const [];
    }
    return _coordinateMapper.mapQuadrilateral(
      sourcePoints: projectDetectedPageOutline(
        page: _runtime.coordinator.activeContext.pageLayout,
        sourceRegistrationPoints: analysis.tracking.registrationPoints,
      ),
      sourceSize: analysis.sourceFrameSize,
      viewportSize: PreviewSize(viewport.width, viewport.height),
      sensorOrientationDegrees: analysis.sensorOrientationDegrees,
      deviceOrientation: analysis.deviceOrientation,
      mirrored:
          state.cameraState.previewInfo?.lens == CameraLensPreference.front,
    );
  }
}

class ScannerReviewStateView extends StatelessWidget {
  const ScannerReviewStateView({
    required this.session,
    required this.reviewResult,
    required this.onContinue,
    super.key,
  });

  final ScannerValidationSession session;
  final ScanResult? reviewResult;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final result = reviewResult;
    if (result == null) {
      final error = scannerReviewResultMissingError();
      return Scaffold(
        key: const Key('scanner-review-result-missing'),
        appBar: AppBar(title: const Text('Scanner state error')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SelectableText('${error.code}: ${error.message}'),
          ),
        ),
      );
    }
    return ScannerPageResultScreen(
      session: session,
      result: result,
      onContinue: onContinue,
    );
  }
}

class ScannerStatusBanner extends StatelessWidget {
  const ScannerStatusBanner({
    required this.text,
    required this.progress,
    super.key,
  });

  final String text;
  final String progress;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 17)),
          Text(progress, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    ),
  );
}

class ScannerPageResultScreen extends StatelessWidget {
  const ScannerPageResultScreen({
    required this.session,
    required this.result,
    required this.onContinue,
    super.key,
  });

  final ScannerValidationSession session;
  final ScanResult result;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final questions = {
      for (final section in session.artifact.template.sections)
        for (final question in section.questions) question.id: question,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Page scan result')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            session.artifact.template.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('Version ${session.artifact.templateVersion.value}'),
          Text(
            'Page ${session.currentPageIndex + 1} of ${session.pages.length}',
          ),
          Text('PageId: ${result.pageId.value}'),
          const Divider(),
          for (final classification in result.questions)
            _QuestionResultTile(
              classification: classification,
              question: questions[classification.questionId],
            ),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('continue-after-page-review'),
            onPressed: onContinue,
            child: Text(session.isComplete ? 'Done' : 'Continue'),
          ),
          ExpansionTile(
            title: const Text('Show diagnostics'),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Page state: ${result.pageState.name}\n'
                  'Markers: ${result.diagnostics.alignment.detectedMarkerIds}\n'
                  'Processing: ${result.diagnostics.totalProcessingDuration.inMilliseconds} ms\n'
                  'Review reasons: ${result.reviewReasons.map((item) => item.name).join(', ')}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuestionResultTile extends StatelessWidget {
  const _QuestionResultTile({required this.classification, this.question});

  final QuestionClassification classification;
  final TemplateQuestion? question;

  @override
  Widget build(BuildContext context) {
    final numeric = classification.numericSelection?.completeDigitString;
    final labels = {
      for (final option in question?.options ?? const [])
        option.id: option.label,
    };
    final selected = classification.selectedOptionIds
        .map((id) => labels[id] ?? id.value)
        .join(' + ');
    final answer = numeric ?? (selected.isEmpty ? '—' : selected);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(question?.prompt ?? classification.questionId.value),
      subtitle: Text(answer),
      trailing: Text(classification.state.name.toUpperCase()),
    );
  }
}

class _ScannerCompleteScreen extends StatelessWidget {
  const _ScannerCompleteScreen({required this.session});

  final ScannerValidationSession session;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan complete')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 64),
            const SizedBox(height: 12),
            Text('${session.completedPageCount} pages scanned'),
            Text(
              '${session.artifact.template.name} · v${session.artifact.templateVersion.value}',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Finish'),
            ),
          ],
        ),
      ),
    ),
  );
}
