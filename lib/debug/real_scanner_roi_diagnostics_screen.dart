import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../application/camera_scanner/domain/camera_scan_state.dart';
import '../application/real_scanner/published_scanner_resolver.dart';
import '../application/real_scanner/real_scanner_runtime.dart';
import '../application/real_scanner/roi_diagnostic_history.dart';
import '../application/real_scanner/scanner_validation_session.dart';
import '../core/ids/identifiers.dart';
import '../engines/recognition/domain/bubble_measurement.dart';
import '../engines/recognition/domain/mark_classification.dart';
import '../engines/scanner/domain/scanner_diagnostic_snapshot.dart';
import 'omr_camera_preview.dart';

class RealScannerRoiDiagnosticsScreen extends StatefulWidget {
  const RealScannerRoiDiagnosticsScreen({required this.artifact, super.key});

  final PublishedScannerArtifact artifact;

  @override
  State<RealScannerRoiDiagnosticsScreen> createState() =>
      _RealScannerRoiDiagnosticsScreenState();
}

class _RealScannerRoiDiagnosticsScreenState
    extends State<RealScannerRoiDiagnosticsScreen>
    with WidgetsBindingObserver {
  late final RealScannerRuntime _runtime;
  late final StreamSubscription<CameraScanState> _subscription;
  late CameraScanState _state;
  ScannerDiagnosticSnapshot? _snapshot;
  ui.Image? _canonicalImage;
  RoiDiagnosticHistory _history = RoiDiagnosticHistory();
  QuestionId? _selectedQuestionId;
  DiagnosticBubbleIdentity? _selectedBubble;
  bool _recordNextScan = false;
  bool _disposing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runtime = createRealScannerRuntime(
      ScannerValidationSession.start(artifact: widget.artifact),
      autoCaptureEnabled: false,
    );
    _state = _runtime.coordinator.state;
    _subscription = _runtime.coordinator.states.listen(_onScannerState);
    unawaited(_runtime.coordinator.initialize());
  }

  Future<void> _onScannerState(CameraScanState state) async {
    if (!mounted || _disposing) return;
    _state = state;
    final diagnostic = state.diagnosticSnapshot;
    if (state.phase == CameraScanPhase.scanCompleted && diagnostic != null) {
      final image = await _decodeCanonicalImage(diagnostic);
      if (!mounted || _disposing) {
        image.dispose();
        return;
      }
      _canonicalImage?.dispose();
      final questionIds = diagnostic.classification.questions
          .map((question) => question.questionId)
          .toList(growable: false);
      final preferred = questionIds.where((id) => id.value == 'q4').firstOrNull;
      final selectedQuestion = preferred ?? questionIds.firstOrNull;
      setState(() {
        _snapshot = diagnostic;
        _canonicalImage = image;
        if (_recordNextScan) _history = _history.record(diagnostic);
        _selectedQuestionId = selectedQuestion;
        _selectedBubble = _firstIdentityFor(diagnostic, selectedQuestion);
        _recordNextScan = false;
      });
      _runtime.coordinator.reset();
      return;
    }
    if (mounted) setState(() {});
  }

  Future<ui.Image> _decodeCanonicalImage(
    ScannerDiagnosticSnapshot snapshot,
  ) async {
    if (snapshot.canonicalImageFormat == ScannerDiagnosticImageFormat.png) {
      final codec = await ui.instantiateImageCodec(
        snapshot.canonicalImageBytes,
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    }
    final grayscale = snapshot.canonicalImageBytes;
    final rgba = Uint8List(grayscale.length * 4);
    for (var source = 0, target = 0; source < grayscale.length; source++) {
      final value = grayscale[source];
      rgba[target++] = value;
      rgba[target++] = value;
      rgba[target++] = value;
      rgba[target++] = 255;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      snapshot.canonicalSize.width,
      snapshot.canonicalSize.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
      rowBytes: snapshot.canonicalSize.width * 4,
    );
    return completer.future;
  }

  void _capture({required bool retainEvidence}) {
    _recordNextScan = retainEvidence;
    unawaited(
      _runtime.coordinator.captureAndScan(includeDiagnostics: true).then((
        result,
      ) {
        if (result.isFailure && mounted) {
          setState(() => _recordNextScan = false);
        }
      }),
    );
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
    _disposing = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription.cancel());
    unawaited(_runtime.coordinator.dispose());
    _canonicalImage?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final canonicalImage = _canonicalImage;
    final controller = _runtime.backend.controller;
    final error = _state.error;
    final canCapture = _state.canCapture && !_state.operationInProgress;
    return Scaffold(
      appBar: AppBar(title: const Text('ROI Diagnostics')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.artifact.templateId.value} '
              'v${widget.artifact.templateVersion.value}',
            ),
            Text(
              'Active page: ${_runtime.coordinator.activeContext.pageId.value}',
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 260,
              child: controller != null && controller.value.isInitialized
                  ? OmrCameraPreview(
                      controller: controller,
                      pageLayout: _runtime.coordinator.activeContext.pageLayout,
                      isReady: _state.canCapture,
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const Key('capture-diagnostic-scan'),
                  onPressed: canCapture
                      ? () => _capture(retainEvidence: false)
                      : null,
                  child: const Text('Capture Diagnostic Scan'),
                ),
                FilledButton.tonal(
                  key: const Key('record-stability-scan'),
                  onPressed: canCapture
                      ? () => _capture(retainEvidence: true)
                      : null,
                  child: const Text('Record Stability Scan'),
                ),
                OutlinedButton(
                  key: const Key('clear-stability-history'),
                  onPressed: _history.scans.isEmpty
                      ? null
                      : () => setState(() => _history = _history.clear()),
                  child: const Text('Clear Stability History'),
                ),
                OutlinedButton(
                  key: const Key('show-diagnostic-json'),
                  onPressed: snapshot == null ? null : _showJson,
                  child: const Text('Show Diagnostic JSON'),
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                '${error.code}: ${error.message}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (snapshot != null && canonicalImage != null) ...[
              const SizedBox(height: 16),
              _selectors(snapshot),
              const SizedBox(height: 8),
              Text(
                'Canonical ${snapshot.canonicalSize.width} x '
                '${snapshot.canonicalSize.height} - scan '
                '${snapshot.scanSequenceIndex}',
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 520,
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 8,
                  child: AspectRatio(
                    aspectRatio:
                        snapshot.canonicalSize.width /
                        snapshot.canonicalSize.height,
                    child: CustomPaint(
                      key: const Key('canonical-roi-overlay'),
                      painter: CanonicalRoiOverlayPainter(
                        image: canonicalImage,
                        snapshot: snapshot,
                        selectedQuestionId: _selectedQuestionId,
                        selectedBubble: _selectedBubble,
                        labels: _optionLabels(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ..._measurementCards(snapshot),
              _stabilityPanel(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _selectors(ScannerDiagnosticSnapshot snapshot) {
    final questions = snapshot.classification.questions;
    final selectedQuestion = _selectedQuestionId;
    final identities = _identitiesFor(snapshot, selectedQuestion);
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        SizedBox(
          width: 180,
          child: DropdownButtonFormField<QuestionId>(
            key: const Key('diagnostic-question-selector'),
            initialValue: selectedQuestion,
            decoration: const InputDecoration(labelText: 'Question'),
            items: [
              for (final question in questions)
                DropdownMenuItem(
                  value: question.questionId,
                  child: Text(question.questionId.value.toUpperCase()),
                ),
            ],
            onChanged: (value) => setState(() {
              _selectedQuestionId = value;
              _selectedBubble = _firstIdentityFor(snapshot, value);
            }),
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<DiagnosticBubbleIdentity>(
            key: const Key('diagnostic-bubble-selector'),
            initialValue: identities.contains(_selectedBubble)
                ? _selectedBubble
                : identities.firstOrNull,
            decoration: const InputDecoration(labelText: 'Bubble'),
            items: [
              for (final identity in identities)
                DropdownMenuItem(
                  value: identity,
                  child: Text(_displayLabel(identity)),
                ),
            ],
            onChanged: (value) => setState(() => _selectedBubble = value),
          ),
        ),
      ],
    );
  }

  List<Widget> _measurementCards(ScannerDiagnosticSnapshot snapshot) {
    final question = snapshot.classification.questions
        .where((item) => item.questionId == _selectedQuestionId)
        .firstOrNull;
    if (question == null) return const [];
    final measurements = snapshot.measurements.measurements.where(
      (measurement) => measurement.questionId == question.questionId,
    );
    final ranked = List<BubbleMarkDecision>.of(question.bubbleDecisions)
      ..sort(
        (first, second) =>
            second.combinedMarkScore.compareTo(first.combinedMarkScore),
      );
    final top = ranked.firstOrNull;
    final second = ranked.length > 1 ? ranked[1] : null;
    String number(double value) => value.toStringAsFixed(3);
    return [
      Text(
        '${question.questionId.value.toUpperCase()} classification: '
        '${question.state.name.toUpperCase()}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      SelectableText(
        'top: ${top == null ? '-' : _decisionDisplayLabel(top)} | '
        'second: ${second == null ? '-' : _decisionDisplayLabel(second)}\n'
        'score gap: ${number(question.diagnostics.scoreGap)} | '
        'coverage gap: ${number(question.diagnostics.coverageGap)} | '
        'coverage ratio: ${number(question.diagnostics.coverageRatio)}\n'
        'reason: ${question.diagnostics.reason.name}',
      ),
      for (final measurement in measurements)
        _measurementCard(measurement, question),
    ];
  }

  Widget _measurementCard(
    BubbleMeasurement measurement,
    QuestionClassification question,
  ) {
    final decision = question.bubbleDecisions.singleWhere(
      (item) =>
          item.optionId == measurement.optionId &&
          item.numericColumnIndex == measurement.numericColumnIndex &&
          item.numericDigitValue == measurement.numericDigitValue,
    );
    final identity = _identity(measurement);
    final selected = identity == _selectedBubble;
    String number(double value, [int digits = 3]) =>
        value.toStringAsFixed(digits);
    return Card(
      color: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
      child: ListTile(
        onTap: () => setState(() => _selectedBubble = identity),
        title: Text(_displayLabel(identity)),
        subtitle: SelectableText(
          'center: ${number(measurement.roi.center.x, 1)}, '
          '${number(measurement.roi.center.y, 1)}\n'
          'fillRatio: ${number(measurement.fillRatio)} | '
          'coverageScore: ${number(decision.coverageScore)}\n'
          'normalizedDarkness: ${number(measurement.normalizedDarkness)}\n'
          'darknessContrast: ${number(measurement.darknessContrast)} | '
          'darknessScore: ${number(decision.darknessScore)}\n'
          'distributionScore: ${number(decision.distributionScore)} | '
          'combinedMarkScore: ${number(decision.combinedMarkScore)}\n'
          'category: ${decision.category.name} | state: ${decision.state.name}\n'
          'interior mean/median: ${number(measurement.interiorMeanIntensity, 1)} / '
          '${number(measurement.interiorMedianIntensity, 1)}\n'
          'local baseline: ${number(measurement.localBaselineIntensity, 1)} | '
          'foreground pixels: ${measurement.foregroundPixelCount}\n'
          'sampled interior/baseline: ${measurement.sampledInteriorPixelCount} / '
          '${measurement.sampledBaselinePixelCount} | '
          'clipping: ${measurement.quality.clipping.name}\n'
          'baseline foreground: ${number(measurement.quality.baselineForegroundRatio)} | '
          'baseline reliable: ${measurement.quality.localBaselineReliable}\n'
          'valid interior/baseline: '
          '${number(measurement.quality.interiorValidSampleRatio)} / '
          '${number(measurement.quality.baselineValidSampleRatio)} | '
          'neighbor masked: ${measurement.quality.neighborMaskedPixelCount}\n'
          'radii printed/interior/baseline: '
          '${number(measurement.roi.printedRadius, 1)} / '
          '${number(measurement.roi.interiorRadius, 1)} / '
          '${number(measurement.roi.baselineInnerRadius, 1)}-'
          '${number(measurement.roi.baselineOuterRadius, 1)}',
        ),
      ),
    );
  }

  Widget _stabilityPanel() {
    final identity = _selectedBubble;
    if (identity == null) return const SizedBox.shrink();
    final evidence = _history.evidenceFor(identity);
    final summary = _history.summarize(identity);
    if (evidence.isEmpty || summary == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('No retained stability scans for this bubble.'),
        ),
      );
    }
    String range(double minimum, double maximum) =>
        '${minimum.toStringAsFixed(3)} - ${maximum.toStringAsFixed(3)}';
    return Card(
      key: const Key('stability-summary'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stability: ${_displayLabel(identity)}'),
            Text(
              'fillRatio: ${range(summary.minimumFillRatio, summary.maximumFillRatio)}',
            ),
            Text(
              'normalizedDarkness: '
              '${range(summary.minimumNormalizedDarkness, summary.maximumNormalizedDarkness)}',
            ),
            Text(
              'darknessContrast: '
              '${range(summary.minimumDarknessContrast, summary.maximumDarknessContrast)}',
            ),
            Text(
              'coverageScore: '
              '${range(summary.minimumCoverageScore, summary.maximumCoverageScore)}',
            ),
            Text(
              'darknessScore: '
              '${range(summary.minimumDarknessScore, summary.maximumDarknessScore)}',
            ),
            Text(
              'distributionScore: '
              '${range(summary.minimumDistributionScore, summary.maximumDistributionScore)}',
            ),
            Text(
              'combinedMarkScore: '
              '${range(summary.minimumCombinedScore, summary.maximumCombinedScore)}',
            ),
            Text(
              'category changes: ${summary.categoryChanges} | '
              'question-state changes: ${summary.stateChanges}',
            ),
            const Divider(),
            for (final item in evidence)
              Text(
                'scan ${item.scanSequenceIndex}: '
                'fill ${item.fillRatio.toStringAsFixed(3)}, '
                'coverage ${item.coverageScore.toStringAsFixed(3)}, '
                'darkness ${item.darknessScore.toStringAsFixed(3)}, '
                'distribution ${item.distributionScore.toStringAsFixed(3)}, '
                'score ${item.combinedMarkScore.toStringAsFixed(3)}, '
                '${item.category.name}, ${item.questionState.name}',
              ),
          ],
        ),
      ),
    );
  }

  void _showJson() {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Diagnostic JSON'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(snapshot.toJson()),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Map<String, String> _optionLabels() => {
    for (final section in widget.artifact.template.sections)
      for (final question in section.questions)
        for (final option in question.options)
          '${question.id.value}|${option.id.value}': option.label,
  };

  String _displayLabel(DiagnosticBubbleIdentity identity) {
    final option = identity.optionId;
    if (option != null) {
      final label =
          _optionLabels()['${identity.questionId.value}|${option.value}'];
      return '${identity.questionId.value.toUpperCase()}-${label ?? option.value}';
    }
    return '${identity.questionId.value.toUpperCase()}-C'
        '${identity.numericColumnIndex}-${identity.numericDigitValue}';
  }

  String _decisionDisplayLabel(BubbleMarkDecision decision) => _displayLabel(
    DiagnosticBubbleIdentity(
      questionId: decision.questionId,
      optionId: decision.optionId,
      numericColumnIndex: decision.numericColumnIndex,
      numericDigitValue: decision.numericDigitValue,
    ),
  );

  List<DiagnosticBubbleIdentity> _identitiesFor(
    ScannerDiagnosticSnapshot snapshot,
    QuestionId? questionId,
  ) => [
    for (final measurement in snapshot.measurements.measurements)
      if (measurement.questionId == questionId) _identity(measurement),
  ];

  DiagnosticBubbleIdentity? _firstIdentityFor(
    ScannerDiagnosticSnapshot snapshot,
    QuestionId? questionId,
  ) => _identitiesFor(snapshot, questionId).firstOrNull;

  DiagnosticBubbleIdentity _identity(BubbleMeasurement measurement) =>
      DiagnosticBubbleIdentity(
        questionId: measurement.questionId,
        optionId: measurement.optionId,
        numericColumnIndex: measurement.numericColumnIndex,
        numericDigitValue: measurement.numericDigitValue,
      );
}

class CanonicalRoiOverlayPainter extends CustomPainter {
  const CanonicalRoiOverlayPainter({
    required this.image,
    required this.snapshot,
    required this.selectedQuestionId,
    required this.selectedBubble,
    required this.labels,
  });

  final ui.Image image;
  final ScannerDiagnosticSnapshot snapshot;
  final QuestionId? selectedQuestionId;
  final DiagnosticBubbleIdentity? selectedBubble;
  final Map<String, String> labels;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint(),
    );
    final scaleX = size.width / snapshot.canonicalSize.width;
    final scaleY = size.height / snapshot.canonicalSize.height;
    for (final measurement in snapshot.measurements.measurements) {
      final identity = DiagnosticBubbleIdentity(
        questionId: measurement.questionId,
        optionId: measurement.optionId,
        numericColumnIndex: measurement.numericColumnIndex,
        numericDigitValue: measurement.numericDigitValue,
      );
      final inQuestion = measurement.questionId == selectedQuestionId;
      final highlighted = identity == selectedBubble;
      final alpha = inQuestion ? 0.9 : 0.25;
      final center = Offset(
        measurement.roi.center.x * scaleX,
        measurement.roi.center.y * scaleY,
      );
      double radius(double value) => value * (scaleX + scaleY) / 2;
      canvas.drawCircle(
        center,
        radius(measurement.roi.interiorRadius),
        Paint()..color = Colors.green.withValues(alpha: alpha * 0.28),
      );
      final ringPaint = Paint()
        ..color = Colors.yellow.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = highlighted ? 2.5 : 1;
      canvas.drawCircle(
        center,
        radius(measurement.roi.baselineInnerRadius),
        ringPaint,
      );
      canvas.drawCircle(
        center,
        radius(measurement.roi.baselineOuterRadius),
        ringPaint,
      );
      canvas.drawCircle(
        center,
        radius(measurement.roi.printedRadius),
        Paint()
          ..color = (highlighted ? Colors.cyanAccent : Colors.white).withValues(
            alpha: alpha,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = highlighted ? 2.5 : 0.8,
      );
      canvas.drawCircle(
        center,
        highlighted ? 3.5 : 2,
        Paint()..color = Colors.red.withValues(alpha: alpha),
      );
      if (inQuestion) {
        final label = measurement.optionId == null
            ? '${measurement.questionId.value.toUpperCase()}-'
                  '${measurement.numericColumnIndex}:'
                  '${measurement.numericDigitValue}'
            : '${measurement.questionId.value.toUpperCase()}-'
                  '${labels['${measurement.questionId.value}|${measurement.optionId!.value}'] ?? measurement.optionId!.value}';
        final painter = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: highlighted ? Colors.cyanAccent : Colors.white,
              fontSize: highlighted ? 12 : 9,
              backgroundColor: Colors.black54,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, center + const Offset(5, -14));
      }
    }
  }

  @override
  bool shouldRepaint(CanonicalRoiOverlayPainter oldDelegate) =>
      oldDelegate.image != image ||
      oldDelegate.snapshot != snapshot ||
      oldDelegate.selectedQuestionId != selectedQuestionId ||
      oldDelegate.selectedBubble != selectedBubble;
}
