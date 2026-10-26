import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../application/camera_scanner/domain/camera_scan_state.dart';
import '../application/camera_scanner/domain/preview_coordinate_mapper.dart';
import '../application/real_scanner/published_scanner_resolver.dart';
import '../application/real_scanner/multi_page_validation_recorder.dart';
import '../application/real_scanner/physical_validation_recorder.dart';
import '../application/real_scanner/real_scanner_runtime.dart';
import '../application/real_scanner/scanner_validation_flow.dart';
import '../application/real_scanner/scanner_validation_session.dart';
import '../application/real_scanner/scanner_user_feedback.dart';
import '../application/real_scanner/scanner_debug_report.dart';
import '../application/answer_sheet_packets/packet_generation_service.dart';
import '../application/answer_sheet_packets/packet_models.dart';
import '../application/answer_sheet_packets/packet_response_repository.dart';
import '../application/answer_sheet_packets/packet_response_service.dart';
import '../core/errors/engine_error.dart';
import '../engines/camera/domain/camera_engine_config.dart';
import '../engines/camera/domain/camera_models.dart';
import '../engines/recognition/domain/mark_classification.dart';
import '../engines/scanner/domain/scan_result.dart';
import '../engines/template/application/template_publication_service.dart';
import '../engines/template/domain/template_question.dart';
import 'real_scanner_roi_diagnostics_screen.dart';
import 'scanner_diagnostics_sheet.dart';
import 'scanner_detection_overlay.dart';

class RealScannerSelectionScreen extends StatefulWidget {
  const RealScannerSelectionScreen({
    this.publicationService,
    this.resolver,
    this.packetRepository,
    super.key,
  }) : assert(
         publicationService != null || resolver != null,
         'A scanner resolver or legacy publication service is required.',
       );

  final TemplatePublicationService? publicationService;
  final PublishedScannerResolver? resolver;
  final PacketResponseRepository? packetRepository;

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

  Future<void> _start() async {
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
    final packetRepository = widget.packetRepository;
    List<AnswerSheetPacket> packets = const [];
    if (packetRepository != null) {
      final loaded = await packetRepository.listPackets();
      if (!mounted) return;
      if (loaded.isFailure) {
        setState(() => _error = loaded.error);
        return;
      }
      packets = loaded.value
          .where(
            (packet) =>
                packet.templateId == selected.templateId &&
                packet.templateVersion == selected.templateVersion,
          )
          .toList(growable: false);
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RealScannerCameraScreen(
          session: ScannerValidationSession.start(
            artifact: selected,
            validationPlan: buildP13_8DenseKnownAnswerPlan(selected.template),
            multiPageValidationPlan: buildP13_9MultiPageValidationPlan(
              selected,
            ),
            packetScanContext: packets.isEmpty
                ? null
                : packetScanContext(packets),
          ),
          packetResponseService: packetRepository == null
              ? null
              : PacketResponseService(repository: packetRepository),
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
              onPressed: selected == null ? null : () => unawaited(_start()),
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
  const RealScannerCameraScreen({
    required this.session,
    this.packetResponseService,
    super.key,
  });

  final ScannerValidationSession session;
  final PacketResponseService? packetResponseService;

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
  bool _disposing = false;
  PacketPageClaimResult? _packetClaim;
  EngineError? _packetClaimError;
  Timer? _failurePolygonTimer;
  bool _showRejectedOutcome = false;
  bool _showFailurePolygon = false;
  ScannerDebugHistory _debugHistory = ScannerDebugHistory();

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
    if (state.phase == CameraScanPhase.scanFailed) {
      _recordDebugAttempt(
        state,
        ScannerDebugAttemptOutcome.failed,
        error: state.error,
      );
    } else if (action == ScannerValidationFlowAction.resultRecorded) {
      _recordDebugAttempt(state, ScannerDebugAttemptOutcome.succeeded);
    } else if (action == ScannerValidationFlowAction.resultRejected) {
      final acceptance = _flow.acceptanceRejection;
      _recordDebugAttempt(
        state,
        ScannerDebugAttemptOutcome.failed,
        error:
            _flow.sessionError ??
            (acceptance == null
                ? null
                : EngineError(
                    code: acceptance.decision.name,
                    message: acceptance.guidance,
                  )),
      );
    }
    if (state.phase == CameraScanPhase.scanFailed ||
        action == ScannerValidationFlowAction.resultRejected) {
      _showRejectedOutcome = true;
      _showFailurePolygon = true;
      _failurePolygonTimer?.cancel();
      _failurePolygonTimer = Timer(const Duration(milliseconds: 1400), () {
        if (!mounted || _disposing) return;
        setState(() => _showFailurePolygon = false);
      });
    }
    setState(() {});
    switch (action) {
      case ScannerValidationFlowAction.resultRecorded:
        _runtime.coordinator.updateCompletedPages(_flow.completedPageIds);
        _claimPacketResult(state.result);
        break;
      case ScannerValidationFlowAction.resultRejected:
        _packetClaim = null;
        _packetClaimError = null;
        break;
      case ScannerValidationFlowAction.stateUpdated:
      case ScannerValidationFlowAction.completionIgnored:
        break;
    }
  }

  void _recordDebugAttempt(
    CameraScanState state,
    ScannerDebugAttemptOutcome outcome, {
    EngineError? error,
  }) {
    _debugHistory = _debugHistory.record(
      state: state,
      outcome: outcome,
      timestamp: DateTime.now(),
      error: error,
    );
  }

  void _showScannerDiagnostics() {
    final report = const ScannerDebugReportBuilder().build(
      currentState: _flow.latestCameraState,
      expectedMarkerIds: _runtime
          .coordinator
          .activeContext
          .pageLayout
          .markerRegions
          .map((marker) => marker.markerId),
      history: _debugHistory,
      platform: defaultTargetPlatform.name,
    );
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => ScannerDiagnosticsSheet(report: report),
      ),
    );
  }

  void _claimPacketResult(ScanResult? result) {
    final service = widget.packetResponseService;
    if (service == null || result?.packetIdentity == null) return;
    unawaited(() async {
      final claimed = await service.claim(result!);
      if (!mounted || _disposing) return;
      setState(() {
        _packetClaim = claimed.valueOrNull;
        _packetClaimError = claimed.errorOrNull;
      });
    }());
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
    _clearRejectedOutcome();
    setState(() {});
  }

  void _retryScan() {
    _flow.clearSessionError();
    _clearRejectedOutcome();
    _runtime.coordinator.reset();
    setState(() {});
  }

  void _clearRejectedOutcome() {
    _failurePolygonTimer?.cancel();
    _showRejectedOutcome = false;
    _showFailurePolygon = false;
  }

  void _captureDuplicate() {
    unawaited(_runtime.coordinator.captureAndScan(force: true));
  }

  Future<void> _retryCamera() async {
    _flow.clearSessionError();
    _clearRejectedOutcome();
    await _runtime.coordinator.resume();
    if (mounted && !_disposing) setState(() {});
  }

  @override
  void dispose() {
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription.cancel());
    _failurePolygonTimer?.cancel();
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
        packetClaim: _packetClaim,
        packetClaimError: _packetClaimError,
        onShowDiagnostics: _showScannerDiagnostics,
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
    final acceptanceRejection = _flow.acceptanceRejection;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Scan ${session.artifact.template.name}'),
        actions: [
          IconButton(
            key: const Key('scanner-torch-toggle'),
            tooltip: state.cameraState.diagnostics.torchAvailable
                ? state.cameraState.diagnostics.torchEnabled
                      ? 'Turn flashlight off'
                      : 'Turn flashlight on'
                : 'Flashlight unavailable',
            onPressed:
                !state.operationInProgress &&
                    state.cameraState.diagnostics.torchAvailable &&
                    (state.cameraState.lifecycle ==
                            CameraLifecycleState.ready ||
                        state.cameraState.lifecycle ==
                            CameraLifecycleState.analyzing)
                ? () => unawaited(
                    _runtime.coordinator.setTorchEnabled(
                      !state.cameraState.diagnostics.torchDesiredEnabled,
                    ),
                  )
                : null,
            icon: Icon(
              state.cameraState.diagnostics.torchEnabled
                  ? Icons.flashlight_on
                  : Icons.flashlight_off,
            ),
          ),
          IconButton(
            key: const Key('open-scanner-diagnostics'),
            tooltip: 'Scanner diagnostics',
            onPressed: _showScannerDiagnostics,
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
                      final overlay = _mappedOverlayGeometry(
                        constraints.biggest,
                        state,
                      );
                      final previewAspect = _previewContentAspect(
                        state,
                        controller.value.aspectRatio,
                      );
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
                                points:
                                    _showRejectedOutcome && !_showFailurePolygon
                                    ? const []
                                    : overlay.points,
                                state: _showRejectedOutcome
                                    ? ScannerOverlayState.failure
                                    : scannerOverlayState(state),
                                geometrySource: overlay.source,
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
            ScannerFailureCard(
              feedback: scannerUserFeedbackForError(displayedError),
              onAction:
                  scannerUserFeedbackForError(displayedError).kind ==
                      ScannerFailureKind.fatal
                  ? () => unawaited(_retryCamera())
                  : _retryScan,
              onShowDiagnostics: _showScannerDiagnostics,
            ),
          if (acceptanceRejection != null)
            ScannerFailureCard(
              key: const Key('scan-rescan-required'),
              feedback: scannerUserFeedbackForAcceptance(acceptanceRejection),
              onAction: _retryScan,
              onShowDiagnostics: _showScannerDiagnostics,
            ),
          if (_packetClaim != null || _packetClaimError != null)
            _PacketClaimPanel(claim: _packetClaim, error: _packetClaimError),
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
        ],
      ),
    );
  }

  ScannerOverlayGeometry _mappedOverlayGeometry(
    Size viewport,
    CameraScanState state,
  ) {
    final analysis = state.cameraState.analysis;
    final activePage = _runtime.coordinator.activeContext.pageLayout;
    final resolvedPageId = analysis?.tracking.resolvedPageId;
    final applicablePage =
        resolvedPageId == null || activePage.pageId == resolvedPageId
        ? activePage
        : null;
    final overlay = scannerOverlayGeometry(analysis, page: applicablePage);
    if (analysis == null || overlay.points.length != 4) {
      return const ScannerOverlayGeometry.none();
    }
    return ScannerOverlayGeometry(
      points: _coordinateMapper.mapQuadrilateral(
        sourcePoints: overlay.points,
        sourceSize: analysis.sourceFrameSize,
        viewportSize: PreviewSize(viewport.width, viewport.height),
        sensorOrientationDegrees: analysis.sensorOrientationDegrees,
        deviceOrientation: analysis.deviceOrientation,
        mirrored:
            state.cameraState.previewInfo?.lens == CameraLensPreference.front,
      ),
      source: overlay.source,
    );
  }

  double _previewContentAspect(
    CameraScanState state,
    double controllerAspectRatio,
  ) {
    final analysis = state.cameraState.analysis;
    if (analysis == null) return 1 / controllerAspectRatio;
    final oriented = _coordinateMapper.orientedSourceSize(
      sourceSize: analysis.sourceFrameSize,
      sensorOrientationDegrees: analysis.sensorOrientationDegrees,
      deviceOrientation: analysis.deviceOrientation,
      mirrored:
          state.cameraState.previewInfo?.lens == CameraLensPreference.front,
    );
    return oriented.width / oriented.height;
  }
}

class ScannerReviewStateView extends StatelessWidget {
  const ScannerReviewStateView({
    required this.session,
    required this.reviewResult,
    required this.onContinue,
    this.packetClaim,
    this.packetClaimError,
    this.onShowDiagnostics,
    super.key,
  });

  final ScannerValidationSession session;
  final ScanResult? reviewResult;
  final VoidCallback onContinue;
  final PacketPageClaimResult? packetClaim;
  final EngineError? packetClaimError;
  final VoidCallback? onShowDiagnostics;

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
      packetClaim: packetClaim,
      packetClaimError: packetClaimError,
      onShowDiagnostics: onShowDiagnostics,
    );
  }
}

class ScannerStatusBanner extends StatefulWidget {
  const ScannerStatusBanner({
    required this.text,
    required this.progress,
    super.key,
  });

  final String text;
  final String progress;

  @override
  State<ScannerStatusBanner> createState() => _ScannerStatusBannerState();
}

class _ScannerStatusBannerState extends State<ScannerStatusBanner> {
  static const _minimumMessageDuration = Duration(milliseconds: 450);
  late String _displayedText = widget.text;
  DateTime _changedAt = DateTime.now();
  Timer? _pendingChange;

  @override
  void didUpdateWidget(covariant ScannerStatusBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text == _displayedText) {
      _pendingChange?.cancel();
      return;
    }
    if (_isImmediate(widget.text)) {
      _setDisplayedText(widget.text);
      return;
    }
    final elapsed = DateTime.now().difference(_changedAt);
    if (elapsed >= _minimumMessageDuration) {
      _setDisplayedText(widget.text);
      return;
    }
    _pendingChange?.cancel();
    _pendingChange = Timer(_minimumMessageDuration - elapsed, () {
      if (!mounted) return;
      _setDisplayedText(widget.text);
    });
  }

  bool _isImmediate(String text) => const {
    'Reading your answers...',
    'Sheet successfully recorded',
    'Scan needs attention',
  }.contains(text);

  void _setDisplayedText(String value) {
    _pendingChange?.cancel();
    if (!mounted) return;
    setState(() {
      _displayedText = value;
      _changedAt = DateTime.now();
    });
  }

  @override
  void dispose() {
    _pendingChange?.cancel();
    super.dispose();
  }

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
          Text(
            _displayedText,
            style: const TextStyle(color: Colors.white, fontSize: 17),
          ),
          Text(widget.progress, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    ),
  );
}

class ScannerFailureCard extends StatelessWidget {
  const ScannerFailureCard({
    required this.feedback,
    required this.onAction,
    this.onShowDiagnostics,
    super.key,
  });

  final ScannerUserFeedback feedback;
  final VoidCallback onAction;
  final VoidCallback? onShowDiagnostics;

  @override
  Widget build(BuildContext context) {
    final fatal = feedback.kind == ScannerFailureKind.fatal;
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: fatal ? colors.errorContainer : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: fatal ? colors.error : Colors.orange.shade700,
        ),
      ),
      child: Row(
        children: [
          Icon(
            fatal ? Icons.camera_alt_outlined : Icons.info_outline,
            color: fatal ? colors.onErrorContainer : Colors.orange.shade800,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feedback.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(feedback.description),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: onAction,
                child: Text(feedback.actionLabel),
              ),
              if (onShowDiagnostics != null)
                TextButton(
                  key: const Key('rejection-scanner-diagnostics'),
                  onPressed: onShowDiagnostics,
                  child: const Text('Debug details'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class ScannerPageResultScreen extends StatelessWidget {
  const ScannerPageResultScreen({
    required this.session,
    required this.result,
    required this.onContinue,
    this.packetClaim,
    this.packetClaimError,
    this.onShowDiagnostics,
    super.key,
  });

  final ScannerValidationSession session;
  final ScanResult result;
  final VoidCallback onContinue;
  final PacketPageClaimResult? packetClaim;
  final EngineError? packetClaimError;
  final VoidCallback? onShowDiagnostics;

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
    final recordingConfirmed = result.packetIdentity == null
        ? true
        : packetClaim?.status == PacketPageClaimStatus.accepted;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Page scan result'),
        actions: [
          if (onShowDiagnostics != null)
            IconButton(
              key: const Key('review-scanner-diagnostics'),
              tooltip: 'Scanner diagnostics',
              onPressed: onShowDiagnostics,
              icon: const Icon(Icons.bug_report_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (recordingConfirmed)
            Card(
              key: const Key('scan-recording-confirmed'),
              color: Colors.green.shade50,
              child: ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: const Text('Sheet successfully recorded'),
                subtitle: Text(
                  'Page ${result.packetIdentity?.pageIndex != null ? result.packetIdentity!.pageIndex + 1 : session.currentPageIndex + 1} accepted',
                ),
              ),
            )
          else if (packetClaimError == null)
            const Card(
              key: Key('scan-recording-pending'),
              child: ListTile(
                leading: SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                title: Text('Saving sheet...'),
              ),
            ),
          Text(
            session.artifact.template.name,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          Text('Version ${session.artifact.templateVersion.value}'),
          Text(
            'Page ${session.currentPageIndex + 1} of ${session.pages.length}',
          ),
          Text('PageId: ${result.pageId.value}'),
          if (result.packetIdentity case final identity?) ...[
            Text('Packet: ${identity.packetId.value}'),
            Text(
              'Packet page: ${identity.pageIndex + 1} / ${identity.totalPages}',
            ),
          ],
          if (packetClaim != null || packetClaimError != null)
            _PacketClaimPanel(claim: packetClaim, error: packetClaimError),
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

class _PacketClaimPanel extends StatelessWidget {
  const _PacketClaimPanel({this.claim, this.error});

  final PacketPageClaimResult? claim;
  final EngineError? error;

  @override
  Widget build(BuildContext context) {
    final failure = error;
    if (failure != null) {
      return Material(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text('${failure.code}: ${failure.message}'),
        ),
      );
    }
    final value = claim!;
    final duplicate = value.status == PacketPageClaimStatus.duplicate;
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          duplicate
              ? 'Page already scanned\n'
                    'Existing Response: ${value.response.responseId.value}'
              : 'Response: ${value.response.responseId.value}\n'
                    'Status: ${value.response.status.name.toUpperCase()}',
          key: const Key('packet-claim-result'),
        ),
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
