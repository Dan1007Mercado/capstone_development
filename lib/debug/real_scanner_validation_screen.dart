import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../application/camera_scanner/domain/camera_scan_state.dart';
import '../application/camera_scanner/domain/detected_page_geometry.dart';
import '../application/camera_scanner/domain/preview_coordinate_mapper.dart';
import '../application/real_scanner/published_scanner_resolver.dart';
import '../application/real_scanner/multi_page_validation_recorder.dart';
import '../application/real_scanner/physical_validation_recorder.dart';
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
import 'real_scanner_roi_diagnostics_screen.dart';
import 'scanner_detection_overlay.dart';

class RealScannerSelectionScreen extends StatefulWidget {
  const RealScannerSelectionScreen({
    this.publicationService,
    this.resolver,
    super.key,
  }) : assert(
         publicationService != null || resolver != null,
         'A scanner resolver or legacy publication service is required.',
       );

  final TemplatePublicationService? publicationService;
  final PublishedScannerResolver? resolver;

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
    _resolver =
        widget.resolver ??
        PublishedScannerResolver(
          publicationService: widget.publicationService!,
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
          session: ScannerValidationSession.start(
            artifact: selected,
            validationPlan: buildP13_8DenseKnownAnswerPlan(selected.template),
            multiPageValidationPlan: buildP13_9MultiPageValidationPlan(
              selected,
            ),
          ),
        ),
      ),
    );
  }

  void _openRoiDiagnostics() {
    final selected = _selected;
    if (selected == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RealScannerRoiDiagnosticsScreen(artifact: selected),
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
                'No durable published artifacts are available. Publish a '
                'validation template in the template builder first.',
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
                        '${artifact.template.name} - v${artifact.templateVersion.value}',
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
                Text(
                  'Page ${page.pageIndex + 1}: ${page.pageId.value} '
                  '[${markerIdsForPage(page).join('/')}]',
                ),
              if (buildP13_8DenseKnownAnswerPlan(selected.template) != null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'P13.8 known answer: mark Q01 = B and Q21 = C; leave '
                    'all other bubbles untouched.',
                  ),
                ),
              if (buildP13_9MultiPageValidationPlan(selected) != null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'P13.9 scan order: Page 2 -> Page 1 -> Page 3 -> Page 2 '
                    'again. The final Page 2 attempt must be rejected as a '
                    'duplicate without overwriting its first result.',
                  ),
                ),
            ],
            if (error != null) ...[
              const SizedBox(height: 12),
              SelectableText('${error.code}: ${error.message}'),
            ],
            const Spacer(),
            OutlinedButton.icon(
              key: const Key('open-roi-diagnostics'),
              onPressed: selected == null ? null : _openRoiDiagnostics,
              icon: const Icon(Icons.center_focus_strong),
              label: const Text('ROI Diagnostics'),
            ),
            const SizedBox(height: 8),
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
    final current = _flow.session;
    final advanced =
        current.isComplete &&
            current.multiPageValidationPlan != null &&
            current.multiPageAttempts.every((attempt) => !attempt.duplicate)
        ? _flow.beginDuplicateCheck()
        : _flow.continueAfterReview();
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

  void _captureDuplicate() {
    unawaited(_runtime.coordinator.captureAndScan(force: true));
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
    final duplicateChecking =
        session.state == ScannerValidationSessionState.duplicateChecking;
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
                                    '${session.completedPageCount} of $pageCount completed · '
                                    'Missing: ${session.remainingPageIds.isEmpty ? 'none' : session.remainingPageIds.map((id) => id.value).join(', ')}',
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
          if (duplicateChecking)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surface,
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  const Text(
                    'Duplicate check: align Page 2, then capture it again. '
                    'The original Page 2 result must remain unchanged.',
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('capture-duplicate-page-2'),
                    onPressed: state.operationInProgress
                        ? null
                        : _captureDuplicate,
                    child: const Text('Capture duplicate Page 2'),
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
    final validation = session.validationReport;
    final multiPageValidation = session.multiPageValidationReport;
    final validationByQuestion = {
      for (final record in validation?.questions ?? const [])
        record.expected.questionId: record,
    };
    final orderedClassifications =
        List<QuestionClassification>.of(result.questions)..sort(
          (left, right) => left.questionNumber.compareTo(right.questionNumber),
        );
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
          for (final classification in orderedClassifications)
            _QuestionResultTile(
              classification: classification,
              question: questions[classification.questionId],
              validation: validationByQuestion[classification.questionId],
            ),
          if (validation != null) ...[
            const Divider(),
            _PhysicalValidationSummaryPanel(report: validation),
          ],
          if (multiPageValidation != null) ...[
            const Divider(),
            _MultiPageValidationSummaryPanel(report: multiPageValidation),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('continue-after-page-review'),
            onPressed: onContinue,
            child: Text(
              session.isComplete && session.multiPageValidationPlan != null
                  ? 'Check duplicate Page 2'
                  : session.isComplete
                  ? 'Done'
                  : 'Continue',
            ),
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
  const _QuestionResultTile({
    required this.classification,
    this.question,
    this.validation,
  });

  final QuestionClassification classification;
  final TemplateQuestion? question;
  final PhysicalValidationQuestionRecord? validation;

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
    final diagnostics = classification.diagnostics;
    final expected = validation?.expected;
    final expectedAnswer =
        expected?.numericAnswer ??
        expected?.optionIds.map((id) => labels[id] ?? id.value).join(' + ');
    return ExpansionTile(
      key: Key('scanner-result-question-${classification.questionNumber}'),
      tilePadding: EdgeInsets.zero,
      title: Text(
        'Q${classification.questionNumber}  '
        '${question?.prompt ?? classification.questionId.value}',
      ),
      subtitle: Text(
        expected == null
            ? answer
            : 'Expected: ${expected.state.name.toUpperCase()} '
                  '${expectedAnswer?.isNotEmpty == true ? expectedAnswer : '—'}\n'
                  'Detected: ${classification.state.name.toUpperCase()} '
                  '$answer\n'
                  'top ${diagnostics.topScore.toStringAsFixed(3)} · '
                  'second ${diagnostics.secondScore.toStringAsFixed(3)} · '
                  'gap ${diagnostics.scoreGap.toStringAsFixed(3)}',
      ),
      trailing: Text(classification.state.name.toUpperCase()),
      children: [
        ListTile(
          dense: true,
          title: const Text('Question mapping'),
          subtitle: Text(
            'questionNumber=${classification.questionNumber} '
            'questionId=${classification.questionId.value}',
          ),
        ),
        for (final decision in classification.bubbleDecisions)
          ListTile(
            dense: true,
            title: Text(
              decision.optionId?.value ??
                  'column ${decision.numericColumnIndex}, '
                      'digit ${decision.numericDigitValue}',
            ),
            subtitle: Text(
              '${decision.category.name} · score '
              '${decision.combinedScore.toStringAsFixed(3)} · fill '
              '${decision.fillRatio.toStringAsFixed(3)} · normalized '
              '${decision.normalizedDarkness.toStringAsFixed(3)} · contrast '
              '${decision.darknessContrast.toStringAsFixed(1)}',
            ),
          ),
      ],
    );
  }
}

class _PhysicalValidationSummaryPanel extends StatelessWidget {
  const _PhysicalValidationSummaryPanel({required this.report});

  final PhysicalValidationReport report;

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;
    String percent(double value) => '${(value * 100).toStringAsFixed(1)}%';
    return ExpansionTile(
      key: const Key('p13-8-validation-summary'),
      title: const Text('P13.8 validation summary'),
      subtitle: Text(
        '${summary.correct}/${summary.totalQuestions} correct · '
        '${summary.wrongConfidentCount} wrong-confident',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            'Accuracy: ${summary.accuracyPercentage.toStringAsFixed(1)}%\n'
            'Ambiguous: ${summary.ambiguous} '
            '(${summary.ambiguousPercentage.toStringAsFixed(1)}%)\n'
            'Blank accuracy: ${percent(summary.blankAccuracy)}\n'
            'Marked accuracy: ${percent(summary.markedAccuracy)}\n'
            'Multiple accuracy: ${percent(summary.multipleAccuracy)}\n'
            'False positive marks: ${summary.falsePositiveMarks}\n'
            'False blank: ${summary.falseBlank}\n'
            'Average processing: '
            '${summary.averageProcessingDuration.inMilliseconds} ms',
          ),
        ),
        ExpansionTile(
          title: const Text('Structured JSON evidence'),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(report.toJson()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MultiPageValidationSummaryPanel extends StatelessWidget {
  const _MultiPageValidationSummaryPanel({required this.report});

  final MultiPageValidationReport report;

  @override
  Widget build(BuildContext context) {
    final summary = report.summary;
    return ExpansionTile(
      key: const Key('p13-9-validation-summary'),
      title: const Text('P13.9 multi-page validation'),
      subtitle: Text(
        '${summary.uniqueAcceptedPages}/${summary.requiredPages} unique pages · '
        '${summary.duplicateAttempts} duplicate attempt(s)',
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            'Wrong-page detections: ${summary.wrongPageDetections}\n'
            'Rejected identity attempts: ${summary.rejectedIdentityAttempts}\n'
            'Session complete: ${summary.sessionComplete ? 'yes' : 'no'}\n'
            'Final order: '
            '${summary.finalPageOrder.map((id) => id.value).join(' → ')}\n'
            'Total processing: '
            '${summary.totalProcessingDuration.inMilliseconds} ms\n'
            'Average processing: '
            '${summary.averageProcessingDuration.inMilliseconds} ms',
          ),
        ),
        ExpansionTile(
          title: const Text('Attempt evidence JSON'),
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(report.toJson()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ScannerCompleteScreen extends StatelessWidget {
  const _ScannerCompleteScreen({required this.session});

  final ScannerValidationSession session;

  @override
  Widget build(BuildContext context) {
    final validation = session.validationReport;
    final multiPageValidation = session.multiPageValidationReport;
    return Scaffold(
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
              if (validation != null) ...[
                const SizedBox(height: 16),
                _PhysicalValidationSummaryPanel(report: validation),
              ],
              if (multiPageValidation != null) ...[
                const SizedBox(height: 16),
                _MultiPageValidationSummaryPanel(report: multiPageValidation),
              ],
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
}
