import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:capstone_development/application/camera_scanner/application/camera_scanner_coordinator.dart';
import 'package:capstone_development/application/camera_scanner/domain/camera_scan_context.dart';
import 'package:capstone_development/application/camera_scanner/domain/camera_scan_ports.dart';
import 'package:capstone_development/application/camera_scanner/domain/camera_scan_state.dart';
import 'package:capstone_development/application/camera_scanner/infrastructure/isolate_offline_scanner_runner.dart';
import 'package:capstone_development/application/real_scanner/published_scanner_resolver.dart';
import 'package:capstone_development/application/real_scanner/scanner_validation_session.dart';
import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/debug/p5_native_validation_fixture.dart';
import 'package:capstone_development/debug/p11_1_scanner_validation_sheet.dart';
import 'package:capstone_development/debug/p11_camera_scanner_composition.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/camera/domain/camera_engine_config.dart';
import 'package:capstone_development/engines/camera/domain/camera_models.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessed_page.dart';
import 'package:capstone_development/engines/scanner/domain/scan_result.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'persistent scanner isolate transfers bytes, reuses, and disposes',
    () async {
      final template = buildP5NativeValidationTemplate();
      final page = buildP5NativeValidationPage();
      final context = CameraScanContext(
        template: template,
        pageLayout: page,
        templateId: template.id,
        templateVersion: template.version,
        pageId: page.pageId,
        scannerConfig: ScannerConfig(),
      );
      final expected = _scanResult(context: context);
      final runner = IsolateOfflineScannerRunner(testResult: expected);
      final bytes = Uint8List.fromList([1, 2, 3, 4]);

      final first = await runner.scan(encodedImage: bytes, context: context);
      bytes.fillRange(0, bytes.length, 99);
      final second = await runner.scan(
        encodedImage: Uint8List.fromList([5, 6]),
        context: context,
      );

      expect(first.isSuccess, isTrue);
      expect(first.value.workerReused, isFalse);
      expect(first.value.transferredByteCount, 4);
      expect(first.value.transferredByteChecksum, 10);
      expect(first.value.result.templateId, template.id);
      expect(first.value.result.pageId, page.pageId);
      expect(second.isSuccess, isTrue);
      expect(second.value.workerReused, isTrue);
      expect(second.value.transferredByteCount, 2);
      await runner.dispose();
      await runner.dispose();
      final afterDispose = await runner.scan(
        encodedImage: Uint8List.fromList([1]),
        context: context,
      );
      expect(afterDispose.error.code, 'FINAL_SCANNER_WORKER_DISPOSED');
    },
  );

  test('scanner isolate preserves structured worker failure', () async {
    final template = buildP5NativeValidationTemplate();
    final page = buildP5NativeValidationPage();
    final runner = IsolateOfflineScannerRunner(
      testError: EngineError(
        code: 'TEST_WORKER_FAILURE',
        message: 'Worker failed predictably.',
        details: const {'stage': 'alignment'},
      ),
    );
    final result = await runner.scan(
      encodedImage: Uint8List.fromList([1, 2, 3]),
      context: CameraScanContext(
        template: template,
        pageLayout: page,
        templateId: template.id,
        templateVersion: template.version,
        pageId: page.pageId,
        scannerConfig: ScannerConfig(),
      ),
    );

    expect(result.error.code, 'TEST_WORKER_FAILURE');
    expect(result.error.details, {'stage': 'alignment'});
    await runner.dispose();
  });

  test(
    'validation session accepts out-of-order pages and rejects duplicates',
    () {
      final inputs = buildP11ScannerValidationSheetInputs();
      var session = ScannerValidationSession.start(
        artifact: PublishedScannerArtifact(
          template: inputs.template,
          layout: inputs.layout,
        ),
      );
      final firstPage = session.pages.last;
      final first = session.recordResult(
        _scanResult(context: session.contextForPage(firstPage.pageId).value),
      );
      expect(first.isSuccess, isTrue);
      session = first.value;
      expect(session.state, ScannerValidationSessionState.reviewing);
      expect(session.completedPageCount, 1);

      session = session.continueAfterReview().value;
      expect(session.state, ScannerValidationSessionState.scanning);
      final duplicate = session.recordResult(
        _scanResult(
          context: CameraScanContext(
            template: inputs.template,
            pageLayout: firstPage,
            templateId: inputs.template.id,
            templateVersion: inputs.template.version,
            pageId: firstPage.pageId,
            scannerConfig: ScannerConfig(),
          ),
        ),
      );
      expect(duplicate.error.code, 'SCAN_PAGE_ALREADY_COMPLETED');

      for (final pageId in List.of(session.remainingPageIds)) {
        final result = session.recordResult(
          _scanResult(context: session.contextForPage(pageId).value),
        );
        expect(result.isSuccess, isTrue);
        session = result.value.continueAfterReview().value;
      }
      expect(session.isComplete, isTrue);
      expect(session.state, ScannerValidationSessionState.complete);
    },
  );

  test(
    'ready camera captures once and scans high-quality bytes once',
    () async {
      final fixture = _Fixture();
      await fixture.initialize();

      final result = await fixture.coordinator.captureAndScan();

      expect(result.isSuccess, isTrue);
      expect(fixture.camera.captureCalls, 1);
      expect(fixture.scanner.calls, 1);
      expect(fixture.scanner.encodedImages.single, fixture.camera.stillBytes);
      expect(fixture.scanner.contexts.single, same(fixture.context));
      expect(
        fixture.scanner.contexts.single.template,
        same(fixture.context.template),
      );
      expect(
        fixture.scanner.contexts.single.pageLayout,
        same(fixture.context.pageLayout),
      );
      expect(fixture.coordinator.state.phase, CameraScanPhase.scanCompleted);
      expect(fixture.camera.stopCalls, 1);
      expect(fixture.camera.startCalls, 2);
      await fixture.dispose();
    },
  );

  test('diagnostic capture is explicit and forwarded once', () async {
    final fixture = _Fixture();
    await fixture.initialize();

    final result = await fixture.coordinator.captureAndScan(
      includeDiagnostics: true,
    );

    expect(result.isSuccess, isTrue);
    expect(fixture.scanner.includeDiagnosticsRequests, [isTrue]);
    await fixture.dispose();
  });

  test('normal capture does not request diagnostic evidence', () async {
    final fixture = _Fixture();
    await fixture.initialize();

    expect((await fixture.coordinator.captureAndScan()).isSuccess, isTrue);

    expect(fixture.scanner.includeDiagnosticsRequests, [isFalse]);
    await fixture.dispose();
  });

  test('normal capture is rejected until P10 readiness is ready', () async {
    final fixture = _Fixture(readyOnStart: false);
    await fixture.initialize();

    final result = await fixture.coordinator.captureAndScan();

    expect(result.error.code, 'CAPTURE_SCAN_NOT_READY');
    expect(fixture.camera.captureCalls, 0);
    expect(fixture.scanner.calls, 0);
    expect(fixture.coordinator.state.phase, CameraScanPhase.tracking);
    await fixture.dispose();
  });

  test('duplicate requests never overlap capture or scanner work', () async {
    final gate = Completer<void>();
    final fixture = _Fixture(captureGate: gate);
    await fixture.initialize();

    final first = fixture.coordinator.captureAndScan();
    await _waitFor(() => fixture.camera.captureCalls == 1);
    final duplicate = await fixture.coordinator.captureAndScan();

    expect(duplicate.error.code, 'CAPTURE_SCAN_BUSY');
    expect(fixture.camera.captureCalls, 1);
    gate.complete();
    expect((await first).isSuccess, isTrue);
    expect(fixture.scanner.maximumActiveCalls, 1);
    await fixture.dispose();
  });

  test('one auto-capture request starts exactly one scan', () async {
    final fixture = _Fixture();
    await fixture.initialize();

    fixture.camera.emitAnalyzing(ready: true, autoCaptureRequested: true);
    await _waitFor(() => fixture.scanner.calls == 1);

    expect(fixture.camera.captureCalls, 1);
    expect(fixture.coordinator.state.phase, CameraScanPhase.scanCompleted);
    await fixture.dispose();
  });

  test('diagnostic mode ignores automatic capture requests', () async {
    final fixture = _Fixture(autoCaptureEnabled: false);
    await fixture.initialize();

    fixture.camera.emitAnalyzing(ready: true, autoCaptureRequested: true);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(fixture.camera.captureCalls, 0);
    expect(fixture.scanner.calls, 0);
    expect(fixture.coordinator.state.canCapture, isTrue);
    await fixture.dispose();
  });

  test('repeated ready auto signals remain latched after completion', () async {
    final fixture = _Fixture();
    await fixture.initialize();
    fixture.camera.emitAnalyzing(ready: true, autoCaptureRequested: true);
    await _waitFor(() => fixture.scanner.calls == 1);

    for (var index = 0; index < 5; index++) {
      fixture.camera.emitAnalyzing(ready: true, autoCaptureRequested: true);
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(fixture.camera.captureCalls, 1);
    expect(fixture.scanner.calls, 1);
    await fixture.dispose();
  });

  test('scanner failure preserves the structured P9 cause', () async {
    final fixture = _Fixture(
      scannerResults: [_failure('SCAN_ALIGNMENT_FAILED', 'alignment failed')],
    );
    await fixture.initialize();

    final result = await fixture.coordinator.captureAndScan();

    expect(result.error.code, 'CAPTURE_SCAN_SCANNER_FAILED');
    expect(result.error.details['causeCode'], 'SCAN_ALIGNMENT_FAILED');
    expect(fixture.coordinator.state.phase, CameraScanPhase.scanFailed);
    expect(fixture.coordinator.state.result, isNull);
    await fixture.dispose();
  });

  test(
    'wrong final marker signature remains an exact typed coordinator failure',
    () async {
      final fixture = _Fixture(
        scannerResults: [
          _failure('SCAN_UNKNOWN_PAGE_MARKERS', 'wrong physical page'),
        ],
      );
      await fixture.initialize();

      final result = await fixture.coordinator.captureAndScan();

      expect(result.error.code, 'SCAN_UNKNOWN_PAGE_MARKERS');
      expect(
        fixture.coordinator.state.error?.code,
        'SCAN_UNKNOWN_PAGE_MARKERS',
      );
      await fixture.dispose();
    },
  );

  test('capture failure does not call the scanner', () async {
    final fixture = _Fixture(
      captureResult: _failure('CAMERA_CAPTURE_FAILED', 'capture failed'),
    );
    await fixture.initialize();

    final result = await fixture.coordinator.captureAndScan();

    expect(result.error.code, 'CAPTURE_SCAN_CAPTURE_FAILED');
    expect(fixture.scanner.calls, 0);
    expect(fixture.camera.startCalls, 2);
    await fixture.dispose();
  });

  test('byte load failure does not call the scanner', () async {
    final fixture = _Fixture(
      loadResult: _failure('CAPTURE_FILE_READ_FAILED', 'read failed'),
    );
    await fixture.initialize();

    final result = await fixture.coordinator.captureAndScan();

    expect(result.error.code, 'CAPTURE_SCAN_IMAGE_LOAD_FAILED');
    expect(result.error.details['causeCode'], 'CAPTURE_FILE_READ_FAILED');
    expect(fixture.scanner.calls, 0);
    await fixture.dispose();
  });

  test('success reset second success clears stale result', () async {
    final fixture = _Fixture();
    await fixture.initialize();
    final first = await fixture.coordinator.captureAndScan();
    expect(first.isSuccess, isTrue);

    expect(fixture.coordinator.reset().isSuccess, isTrue);
    expect(fixture.coordinator.state.result, isNull);
    expect(fixture.coordinator.state.phase, CameraScanPhase.tracking);
    expect(
      (await fixture.coordinator.captureAndScan()).error.code,
      'CAPTURE_SCAN_NOT_READY',
    );
    fixture.camera.emitAnalyzing(ready: true);
    await Future<void>.delayed(Duration.zero);
    final second = await fixture.coordinator.captureAndScan();

    expect(second.isSuccess, isTrue);
    expect(fixture.camera.captureCalls, 2);
    expect(fixture.scanner.calls, 2);
    await fixture.dispose();
  });

  test('failure retry success clears stale error', () async {
    final fixture = _Fixture(
      scannerResults: [
        _failure('SCAN_ALIGNMENT_FAILED', 'alignment failed'),
        EngineResult.success(_scanResult()),
      ],
    );
    await fixture.initialize();
    expect((await fixture.coordinator.captureAndScan()).isFailure, isTrue);

    fixture.coordinator.reset();
    fixture.camera.emitAnalyzing(ready: true);
    await Future<void>.delayed(Duration.zero);
    final retry = await fixture.coordinator.captureAndScan();

    expect(retry.isSuccess, isTrue);
    expect(fixture.coordinator.state.error, isNull);
    expect(fixture.coordinator.state.phase, CameraScanPhase.scanCompleted);
    await fixture.dispose();
  });

  test('fatal camera retry restarts once without duplicate streams', () async {
    final fixture = _Fixture();
    await fixture.initialize();
    fixture.camera.emitError();
    await Future<void>.delayed(Duration.zero);
    expect(fixture.coordinator.state.phase, CameraScanPhase.scanFailed);

    expect((await fixture.coordinator.resume()).isSuccess, isTrue);
    expect((await fixture.coordinator.resume()).isSuccess, isTrue);

    expect(fixture.camera.initializeCalls, 2);
    expect(fixture.camera.startCalls, 2);
    await fixture.dispose();
  });

  test(
    'dispose during pending scan publishes no state after disposed',
    () async {
      final scannerGate = Completer<void>();
      final fixture = _Fixture(scannerGate: scannerGate);
      await fixture.initialize();
      final operation = fixture.coordinator.captureAndScan();
      await _waitFor(() => fixture.scanner.calls == 1);
      expect(
        fixture.camera.startCalls,
        2,
        reason: 'Live analysis must resume while final scanning is pending.',
      );

      await fixture.coordinator.dispose();
      scannerGate.complete();
      final result = await operation;

      expect(result.error.code, 'CAPTURE_SCAN_DISPOSED');
      expect(fixture.coordinator.state.phase, CameraScanPhase.disposed);
    },
  );

  test(
    'dispose during pending capture is idempotent and never scans',
    () async {
      final captureGate = Completer<void>();
      final fixture = _Fixture(captureGate: captureGate);
      await fixture.initialize();
      final operation = fixture.coordinator.captureAndScan();
      await _waitFor(() => fixture.camera.captureCalls == 1);

      await fixture.coordinator.dispose();
      await fixture.coordinator.dispose();
      captureGate.complete();
      final result = await operation;

      expect(result.error.code, 'CAPTURE_SCAN_DISPOSED');
      expect(fixture.scanner.calls, 0);
      expect(fixture.coordinator.state.phase, CameraScanPhase.disposed);
    },
  );

  test('workflow emits only valid capture and scan phases', () async {
    final fixture = _Fixture();
    await fixture.initialize();
    final phases = <CameraScanPhase>[];
    final subscription = fixture.coordinator.states.listen(
      (state) => phases.add(state.phase),
    );

    await fixture.coordinator.captureAndScan();
    await Future<void>.delayed(Duration.zero);

    expect(
      phases,
      containsAllInOrder([
        CameraScanPhase.capturing,
        CameraScanPhase.scanning,
        CameraScanPhase.scanCompleted,
      ]),
    );
    expect(
      phases.where((phase) => phase == CameraScanPhase.capturing).length,
      1,
    );
    expect(
      phases.where((phase) => phase == CameraScanPhase.scanning).length,
      1,
    );
    expect(
      fixture.coordinator.state.finalScanTimings.totalDuration,
      greaterThanOrEqualTo(
        fixture.coordinator.state.finalScanTimings.scannerDuration,
      ),
    );
    await subscription.cancel();
    await fixture.dispose();
  });

  test('updated expected page reaches scanner without substitution', () async {
    final fixture = _Fixture();
    await fixture.initialize();
    final inputs = buildP11ScannerValidationSheetInputs();
    final expected = inputs.layout.pages[1];
    final context = buildP11CameraScanContext(
      template: inputs.template,
      layout: inputs.layout,
      scannerConfig: ScannerConfig(),
      pageIndex: 1,
    );

    expect(fixture.coordinator.updateContext(context).isSuccess, isTrue);
    fixture.camera.emitAnalyzing(ready: true);
    await Future<void>.delayed(Duration.zero);
    expect((await fixture.coordinator.captureAndScan()).isSuccess, isTrue);

    expect(fixture.scanner.contexts.single, same(context));
    expect(fixture.scanner.contexts.single.pageLayout, same(expected));
    expect(fixture.scanner.contexts.single.pageId, expected.pageId);
    await fixture.dispose();
  });

  test('P11 contains no LayoutEngine or widget-owned scanner logic', () {
    final coordinator = File(
      'lib/application/camera_scanner/application/'
      'camera_scanner_coordinator.dart',
    ).readAsStringSync();
    final screen = File(
      'lib/debug/p11_camera_scanner_screen.dart',
    ).readAsStringSync();
    final composition = File(
      'lib/debug/p11_camera_scanner_composition.dart',
    ).readAsStringSync();
    final worker = File(
      'lib/application/camera_scanner/infrastructure/'
      'isolate_offline_scanner_runner.dart',
    ).readAsStringSync();
    final scanner = File(
      'lib/engines/scanner/application/offline_scanner_engine.dart',
    ).readAsStringSync();

    expect(coordinator, isNot(contains('LayoutEngine')));
    expect(coordinator, isNot(contains('BubbleMeasurementEngine')));
    expect(screen, isNot(contains('OfflineScannerEngine')));
    expect(screen, isNot(contains('.scan(')));
    expect(composition, isNot(contains('OpenCvArucoVisionBackend')));
    expect(worker, contains('TransferableTypedData'));
    expect(worker, contains('OpenCvArucoVisionBackend'));
    expect(worker, contains('OpenCvPreprocessingBackend'));
    expect(
      scanner,
      isNot(
        contains('alignment.align(\n      Uint8List.fromList(encodedImage)'),
      ),
    );
    expect(
      worker,
      contains(
        'if (bootstrap.testResult != null || bootstrap.testError != null)',
      ),
    );
  });
}

final class _Fixture {
  _Fixture({
    bool readyOnStart = true,
    bool autoCaptureEnabled = true,
    Completer<void>? captureGate,
    Completer<void>? scannerGate,
    EngineResult<CapturedPageImage>? captureResult,
    EngineResult<Uint8List>? loadResult,
    List<EngineResult<ScanResult>>? scannerResults,
  }) : camera = _FakeCamera(
         readyOnStart: readyOnStart,
         captureGate: captureGate,
         captureResult: captureResult,
       ),
       loader = _FakeLoader(loadResult),
       scanner = _FakeScanner(gate: scannerGate, results: scannerResults) {
    final template = buildP5NativeValidationTemplate();
    final page = buildP5NativeValidationPage();
    context = CameraScanContext(
      template: template,
      pageLayout: page,
      templateId: template.id,
      templateVersion: template.version,
      pageId: page.pageId,
      scannerConfig: ScannerConfig(),
    );
    coordinator = CameraScannerCoordinator(
      camera: camera,
      imageLoader: loader,
      scanner: scanner,
      context: context,
      autoCaptureEnabled: autoCaptureEnabled,
    );
  }

  final _FakeCamera camera;
  final _FakeLoader loader;
  final _FakeScanner scanner;
  late final CameraScanContext context;
  late final CameraScannerCoordinator coordinator;

  Future<void> initialize() async {
    expect((await coordinator.initialize()).isSuccess, isTrue);
  }

  Future<void> dispose() async {
    if (coordinator.state.phase != CameraScanPhase.disposed) {
      await coordinator.dispose();
    }
  }
}

final class _FakeCamera implements CameraScanCamera {
  _FakeCamera({
    required this.readyOnStart,
    this.captureGate,
    EngineResult<CapturedPageImage>? captureResult,
  }) : captureResult =
           captureResult ??
           EngineResult.success(
             CapturedPageImage(
               encodedBytes: Uint8List.fromList(const [91, 92, 93, 94]),
               timestamp: DateTime.utc(2026),
               sensorOrientationDegrees: 90,
               deviceOrientation: CameraDeviceOrientation.portraitUp,
               orientationAppliedByBackend: true,
               width: 4000,
               height: 3000,
             ),
           );

  final bool readyOnStart;
  final Completer<void>? captureGate;
  final EngineResult<CapturedPageImage> captureResult;
  final StreamController<CameraEngineState> _states =
      StreamController<CameraEngineState>.broadcast();
  CameraEngineState _state = const CameraEngineState.uninitialized();
  int startCalls = 0;
  int initializeCalls = 0;
  int stopCalls = 0;
  int captureCalls = 0;
  int processedFrames = 0;
  bool disposed = false;

  Uint8List get stillBytes => captureResult.value.encodedBytes;

  @override
  CameraEngineState get state => _state;

  @override
  Stream<CameraEngineState> get states => _states.stream;

  @override
  Future<EngineResult<bool>> initialize() async {
    initializeCalls++;
    _publish(_cameraState(lifecycle: CameraLifecycleState.ready));
    return EngineResult.success(true);
  }

  @override
  Future<EngineResult<bool>> startAnalysis() async {
    startCalls++;
    _publishAnalyzing(ready: readyOnStart);
    return EngineResult.success(true);
  }

  @override
  Future<EngineResult<bool>> stopAnalysis() async {
    stopCalls++;
    _publish(
      _cameraState(
        lifecycle: CameraLifecycleState.ready,
        ready: _state.readiness.isReady,
        processedFrames: processedFrames,
      ),
    );
    return EngineResult.success(true);
  }

  @override
  Future<EngineResult<CapturedPageImage>> capture() async {
    captureCalls++;
    if (captureGate != null) await captureGate!.future;
    return captureResult;
  }

  @override
  Future<EngineResult<bool>> setTorchEnabled(bool enabled) async =>
      EngineResult.success(enabled);

  void emitAnalyzing({required bool ready, bool autoCaptureRequested = false}) {
    processedFrames++;
    _publishAnalyzing(ready: ready, autoCaptureRequested: autoCaptureRequested);
  }

  void emitError() {
    _publish(
      CameraEngineState(
        lifecycle: CameraLifecycleState.error,
        diagnostics: const CameraDiagnostics(),
        readiness: const CaptureReadiness.notReady(),
        error: EngineError(
          code: 'CAMERA_ANALYSIS_FAILED',
          message: 'Synthetic camera failure.',
        ),
      ),
    );
  }

  void _publishAnalyzing({
    required bool ready,
    bool autoCaptureRequested = false,
  }) {
    _publish(
      _cameraState(
        lifecycle: CameraLifecycleState.analyzing,
        ready: ready,
        autoCaptureRequested: autoCaptureRequested,
        processedFrames: processedFrames,
      ),
    );
  }

  void _publish(CameraEngineState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  @override
  Future<EngineResult<bool>> suspend() async {
    _publish(const CameraEngineState.uninitialized());
    return EngineResult.success(true);
  }

  @override
  void resetTracking() {}

  @override
  Future<void> dispose() async {
    if (disposed) return;
    disposed = true;
    _publish(
      const CameraEngineState(
        lifecycle: CameraLifecycleState.disposed,
        diagnostics: CameraDiagnostics(),
        readiness: CaptureReadiness.notReady(),
      ),
    );
    await _states.close();
  }
}

final class _FakeLoader implements CapturedImageBytesLoader {
  _FakeLoader(this.result);

  final EngineResult<Uint8List>? result;

  @override
  Future<EngineResult<Uint8List>> load(CapturedPageImage capture) async =>
      result ?? EngineResult.success(Uint8List.fromList(capture.encodedBytes));
}

final class _FakeScanner implements OfflineScanRunner {
  _FakeScanner({this.gate, List<EngineResult<ScanResult>>? results})
    : results = results == null ? [] : List.of(results);

  final Completer<void>? gate;
  final List<EngineResult<ScanResult>> results;
  final List<Uint8List> encodedImages = [];
  final List<CameraScanContext> contexts = [];
  final List<bool> includeDiagnosticsRequests = [];
  int calls = 0;
  int activeCalls = 0;
  int maximumActiveCalls = 0;

  @override
  Future<EngineResult<FinalScannerRun>> scan({
    required Uint8List encodedImage,
    required CameraScanContext context,
    bool includeDiagnostics = false,
  }) async {
    calls++;
    activeCalls++;
    if (activeCalls > maximumActiveCalls) maximumActiveCalls = activeCalls;
    encodedImages.add(Uint8List.fromList(encodedImage));
    contexts.add(context);
    includeDiagnosticsRequests.add(includeDiagnostics);
    if (gate != null) await gate!.future;
    activeCalls--;
    final result = results.isEmpty
        ? EngineResult.success(_scanResult(context: context))
        : results.removeAt(0);
    if (result.isFailure) return EngineResult.failure(result.error);
    return EngineResult.success(
      FinalScannerRun(
        result: result.value,
        workerDuration: const Duration(milliseconds: 10),
        isolateOverhead: const Duration(milliseconds: 1),
        workerReused: calls > 1,
      ),
    );
  }

  @override
  Future<void> dispose() async {}
}

CameraEngineState _cameraState({
  required CameraLifecycleState lifecycle,
  bool ready = false,
  bool autoCaptureRequested = false,
  int processedFrames = 0,
}) => CameraEngineState(
  lifecycle: lifecycle,
  previewInfo: const CameraPreviewInfo(
    width: 1920,
    height: 1080,
    sensorOrientationDegrees: 90,
    lens: CameraLensPreference.rear,
    automaticFocusEnabled: true,
    automaticExposureEnabled: true,
    requestedPreviewFps: 60,
  ),
  diagnostics: CameraDiagnostics(
    processedFrameCount: processedFrames,
    estimatedAnalysisFps: 8,
  ),
  readiness: CaptureReadiness(
    status: ready
        ? CaptureReadinessStatus.ready
        : CaptureReadinessStatus.unstable,
    stableFrameCount: ready ? 3 : 1,
    requiredStableFrameCount: 3,
  ),
  autoCaptureRequested: autoCaptureRequested,
);

ScanResult _scanResult({CameraScanContext? context}) {
  final template = context?.template ?? buildP5NativeValidationTemplate();
  final page = context?.pageLayout ?? buildP5NativeValidationPage();
  const statistics = ImageStatistics(
    meanIntensity: 200,
    intensityStandardDeviation: 20,
    minimumIntensity: 0,
    maximumIntensity: 255,
    darkPixelRatio: 0.1,
    brightPixelRatio: 0.8,
  );
  return ScanResult(
    templateId: template.id,
    templateVersion: template.version,
    pageId: page.pageId,
    questions: const [],
    pageState: ScanPageState.accepted,
    reviewReasons: const [],
    reviewQuestionIds: const [],
    diagnostics: ScanDiagnostics(
      totalProcessingDuration: Duration.zero,
      stageDurations: const ScanStageDurations(
        alignment: Duration.zero,
        preprocessing: Duration.zero,
        measurement: Duration.zero,
        classification: Duration.zero,
      ),
      alignment: PageAlignmentDiagnostics(
        expectedMarkerIds: const [10, 11, 12, 13],
        detectedMarkerIds: const [10, 11, 12, 13],
        sourceMarkerSideLengths: const [20, 20, 20, 20],
        sourceRegistrationPoints: const [],
        destinationRegistrationPoints: const [],
        registrationQuality: const RegistrationQuality(
          quadrilateralAreaRatio: 0.5,
          minimumMarkerSidePixels: 20,
          maximumPerspectiveRatio: 1,
        ),
        reprojectionErrors: const [0, 0, 0, 0],
        meanReprojectionError: 0,
        maxReprojectionError: 0,
        processingDuration: Duration.zero,
      ),
      preprocessing: const PreprocessingDiagnostics(
        sourceStatistics: statistics,
        normalizedStatistics: statistics,
        binaryForegroundRatio: 0.1,
        processingDuration: Duration.zero,
      ),
      summary: const ScanSummary(
        totalQuestions: 0,
        marked: 0,
        blank: 0,
        multiple: 0,
        ambiguous: 0,
        invalid: 0,
        requiredBlank: 0,
        measuredBubbles: 0,
      ),
    ),
  );
}

EngineResult<T> _failure<T>(String code, String message) =>
    EngineResult.failure(EngineError(code: code, message: message));

Future<void> _waitFor(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail('Condition did not become true.');
}
