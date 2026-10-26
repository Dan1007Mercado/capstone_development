import 'dart:async';

import '../../../core/errors/engine_error.dart';
import '../../../core/ids/identifiers.dart';
import '../../../core/result/engine_result.dart';
import '../../../engines/camera/domain/camera_models.dart';
import '../../../engines/scanner/domain/scan_result.dart';
import '../../../engines/scanner/domain/scanner_diagnostic_snapshot.dart';
import '../domain/camera_scan_context.dart';
import '../domain/camera_scan_ports.dart';
import '../domain/camera_scan_state.dart';

final class CameraScannerCoordinator {
  CameraScannerCoordinator({
    required this.camera,
    required this.imageLoader,
    required this.scanner,
    required CameraScanContext context,
    this.autoCaptureEnabled = true,
  }) : _context = context {
    _latestCameraState = camera.state;
    _state = CameraScanState(
      phase: CameraScanPhase.idle,
      cameraState: _latestCameraState,
    );
    _cameraSubscription = camera.states.listen(_onCameraState);
  }

  final CameraScanCamera camera;
  final CapturedImageBytesLoader imageLoader;
  final OfflineScanRunner scanner;
  final bool autoCaptureEnabled;
  CameraScanContext _context;

  final StreamController<CameraScanState> _states =
      StreamController<CameraScanState>.broadcast();
  late final StreamSubscription<CameraEngineState> _cameraSubscription;
  late CameraEngineState _latestCameraState;
  late CameraScanState _state;
  bool _operationInProgress = false;
  bool _autoCaptureArmed = true;
  bool _requiresFreshReadiness = false;
  int _readinessProcessedFrameBaseline = 0;
  bool _cameraSessionRequested = false;
  bool _disposed = false;
  Set<PageId> _completedPageIds = const {};
  int _diagnosticScanCount = 0;

  CameraScanState get state => _state;
  Stream<CameraScanState> get states => _states.stream;

  CameraScanContext get activeContext => _context;

  void updateCompletedPages(Iterable<PageId> pageIds) {
    _completedPageIds = Set.unmodifiable(pageIds);
  }

  EngineResult<bool> updateContext(CameraScanContext value) {
    if (_disposed) return _disposedFailure();
    if (_operationInProgress) return _busyFailure();
    final error = value.validate();
    if (error != null) return EngineResult.failure(error);
    _context = value;
    camera.resetTracking();
    _latestCameraState = camera.state;
    _autoCaptureArmed = true;
    _requiresFreshReadiness = true;
    _readinessProcessedFrameBaseline =
        _latestCameraState.diagnostics.processedFrameCount;
    _emit(
      CameraScanState(
        phase: _phaseForCamera(_latestCameraState),
        cameraState: _latestCameraState,
      ),
    );
    return EngineResult.success(true);
  }

  Future<EngineResult<bool>> initialize() async {
    if (_disposed) return _disposedFailure();
    if (_operationInProgress) return _busyFailure();
    final contextError = _context.validate();
    if (contextError != null) {
      _emit(
        CameraScanState(
          phase: CameraScanPhase.scanFailed,
          cameraState: _latestCameraState,
          error: contextError,
        ),
      );
      return EngineResult.failure(contextError);
    }

    _cameraSessionRequested = true;
    _requiresFreshReadiness = false;
    _emit(
      CameraScanState(
        phase: CameraScanPhase.cameraInitializing,
        cameraState: _latestCameraState,
      ),
    );
    final initialized = await camera.initialize();
    if (_disposed) return _disposedFailure();
    if (initialized.isFailure) {
      return _cameraFailure(
        'CAPTURE_SCAN_CAMERA_INITIALIZATION_FAILED',
        'The capture-and-scan camera could not initialize.',
        initialized.error,
      );
    }
    final started = await camera.startAnalysis();
    if (_disposed) return _disposedFailure();
    if (started.isFailure) {
      return _cameraFailure(
        'CAPTURE_SCAN_CAMERA_STREAM_FAILED',
        'The capture-and-scan analysis stream could not start.',
        started.error,
      );
    }
    _publishCameraPhase();
    return EngineResult.success(true);
  }

  Future<EngineResult<ScanResult>> captureAndScan({
    bool force = false,
    bool includeDiagnostics = false,
  }) async {
    if (_disposed) return EngineResult.failure(_disposedError());
    if (_operationInProgress) {
      return EngineResult.failure(_busyError());
    }
    final contextError = _context.validate();
    if (contextError != null) {
      _emitFailure(contextError, FinalScanTimings.zero);
      return EngineResult.failure(contextError);
    }
    final lifecycle = _latestCameraState.lifecycle;
    final cameraValid =
        lifecycle == CameraLifecycleState.analyzing ||
        lifecycle == CameraLifecycleState.ready;
    if (!cameraValid ||
        (!force &&
            (_requiresFreshReadiness ||
                !_latestCameraState.readiness.isReady))) {
      final error = EngineError(
        code: 'CAPTURE_SCAN_NOT_READY',
        message: 'Capture requires a valid camera and ready page alignment.',
        details: {
          'cameraLifecycle': lifecycle.name,
          'readiness': _latestCameraState.readiness.status.name,
          'freshReadinessRequired': _requiresFreshReadiness,
          'force': force,
        },
      );
      _emit(
        CameraScanState(
          phase: _phaseForCamera(_latestCameraState),
          cameraState: _latestCameraState,
          error: error,
        ),
      );
      return EngineResult.failure(error);
    }

    _operationInProgress = true;
    _autoCaptureArmed = false;
    final totalStopwatch = Stopwatch()..start();
    var stopAnalysisDuration = Duration.zero;
    var captureDuration = Duration.zero;
    var byteLoadDuration = Duration.zero;
    var scannerDuration = Duration.zero;
    var workerDuration = Duration.zero;
    var isolateOverhead = Duration.zero;
    var workerReused = false;
    var workerStartupDuration = Duration.zero;
    FinalCaptureDiagnostics? finalCaptureDiagnostics;
    final shouldRestartAnalysis = lifecycle == CameraLifecycleState.analyzing;
    var analysisStopped = false;

    _emit(
      CameraScanState(
        phase: CameraScanPhase.capturing,
        cameraState: _latestCameraState,
      ),
    );

    try {
      final stopAnalysisStopwatch = Stopwatch()..start();
      final stopped = await camera.stopAnalysis();
      stopAnalysisStopwatch.stop();
      stopAnalysisDuration = stopAnalysisStopwatch.elapsed;
      if (_disposed) return EngineResult.failure(_disposedError());
      if (stopped.isFailure) {
        return await _finishFailure(
          code: 'CAPTURE_SCAN_CAMERA_STREAM_FAILED',
          message: 'Camera analysis could not pause for still capture.',
          cause: stopped.error,
          totalStopwatch: totalStopwatch,
          stopAnalysisDuration: stopAnalysisDuration,
          captureDuration: captureDuration,
          byteLoadDuration: byteLoadDuration,
          scannerDuration: scannerDuration,
          restartAnalysis: false,
        );
      }
      analysisStopped = shouldRestartAnalysis;

      final captureStopwatch = Stopwatch()..start();
      final capture = await camera.capture();
      captureStopwatch.stop();
      captureDuration = captureStopwatch.elapsed;
      if (_disposed) return EngineResult.failure(_disposedError());
      if (capture.isFailure) {
        return await _finishFailure(
          code: 'CAPTURE_SCAN_CAPTURE_FAILED',
          message: 'High-quality still capture failed.',
          cause: capture.error,
          totalStopwatch: totalStopwatch,
          stopAnalysisDuration: stopAnalysisDuration,
          captureDuration: captureDuration,
          byteLoadDuration: byteLoadDuration,
          scannerDuration: scannerDuration,
          restartAnalysis: analysisStopped,
        );
      }
      finalCaptureDiagnostics = FinalCaptureDiagnostics(
        width: capture.value.width,
        height: capture.value.height,
        timestamp: capture.value.timestamp,
      );

      final loadStopwatch = Stopwatch()..start();
      final loaded = await imageLoader.load(capture.value);
      loadStopwatch.stop();
      byteLoadDuration = loadStopwatch.elapsed;
      if (_disposed) return EngineResult.failure(_disposedError());
      final encodedImage = loaded.valueOrNull;
      if (loaded.isFailure || encodedImage == null || encodedImage.isEmpty) {
        final cause = loaded.isFailure
            ? loaded.error
            : EngineError(
                code: 'CAPTURE_IMAGE_EMPTY',
                message: 'The high-quality captured image contains no bytes.',
              );
        return await _finishFailure(
          code: 'CAPTURE_SCAN_IMAGE_LOAD_FAILED',
          message: 'The high-quality captured image could not be loaded.',
          cause: cause,
          totalStopwatch: totalStopwatch,
          stopAnalysisDuration: stopAnalysisDuration,
          captureDuration: captureDuration,
          byteLoadDuration: byteLoadDuration,
          scannerDuration: scannerDuration,
          restartAnalysis: analysisStopped,
          finalCaptureDiagnostics: finalCaptureDiagnostics,
        );
      }

      // Once the still bytes are owned, live analysis can safely resume while
      // the independent scanner isolate works. Auto capture remains disarmed
      // and the operation remains single-flight.
      final earlyRestart = await _restoreCamera(analysisStopped);
      if (_disposed) return EngineResult.failure(_disposedError());
      if (earlyRestart.isFailure) {
        return await _finishFailure(
          code: 'CAPTURE_SCAN_CAMERA_STREAM_FAILED',
          message: 'Camera analysis could not resume after still capture.',
          cause: earlyRestart.error,
          totalStopwatch: totalStopwatch,
          stopAnalysisDuration: stopAnalysisDuration,
          captureDuration: captureDuration,
          byteLoadDuration: byteLoadDuration,
          scannerDuration: scannerDuration,
          restartAnalysis: false,
          finalCaptureDiagnostics: finalCaptureDiagnostics,
        );
      }
      analysisStopped = false;

      _emit(
        CameraScanState(
          phase: CameraScanPhase.scanning,
          cameraState: _latestCameraState,
          finalScanTimings: FinalScanTimings(
            stopAnalysisDuration: stopAnalysisDuration,
            captureDuration: captureDuration,
            byteLoadDuration: byteLoadDuration,
          ),
          finalCaptureDiagnostics: finalCaptureDiagnostics,
        ),
      );
      final scannerStopwatch = Stopwatch()..start();
      final scan = await scanner.scan(
        encodedImage: encodedImage,
        context: _context,
        includeDiagnostics: includeDiagnostics,
      );
      scannerStopwatch.stop();
      scannerDuration = scannerStopwatch.elapsed;
      if (scan.isSuccess) {
        workerDuration = scan.value.workerDuration;
        isolateOverhead = scan.value.isolateOverhead;
        workerReused = scan.value.workerReused;
        workerStartupDuration = scan.value.workerStartupDuration;
      }
      totalStopwatch.stop();
      if (_disposed) return EngineResult.failure(_disposedError());

      final timings = FinalScanTimings(
        stopAnalysisDuration: stopAnalysisDuration,
        captureDuration: captureDuration,
        byteLoadDuration: byteLoadDuration,
        scannerDuration: scannerDuration,
        totalDuration: totalStopwatch.elapsed,
        workerDuration: workerDuration,
        isolateOverhead: isolateOverhead,
        workerReused: workerReused,
        workerStartupDuration: workerStartupDuration,
      );
      if (scan.isFailure) {
        final error = _isPageResolutionFailure(scan.error.code)
            ? scan.error
            : _wrapFailure(
                'CAPTURE_SCAN_SCANNER_FAILED',
                'The offline scanner rejected the captured page.',
                scan.error,
              );
        _emitFailure(
          error,
          timings,
          finalCaptureDiagnostics: finalCaptureDiagnostics,
        );
        return EngineResult.failure(error);
      }

      final sequencedDiagnostic = _sequenceDiagnostic(
        scan.value.diagnosticSnapshot,
      );
      _emit(
        CameraScanState(
          phase: CameraScanPhase.scanCompleted,
          cameraState: _latestCameraState,
          result: scan.value.result,
          finalScanTimings: timings,
          diagnosticSnapshot: sequencedDiagnostic,
          finalCaptureDiagnostics: finalCaptureDiagnostics,
        ),
      );
      return EngineResult.success(scan.value.result);
    } on Object catch (error) {
      if (totalStopwatch.isRunning) totalStopwatch.stop();
      if (!_disposed) await _restoreCamera(analysisStopped);
      final failure = EngineError(
        code: 'CAPTURE_SCAN_UNEXPECTED_FAILURE',
        message: 'The capture-and-scan workflow failed unexpectedly.',
        details: {'cause': error.toString()},
      );
      final timings = FinalScanTimings(
        stopAnalysisDuration: stopAnalysisDuration,
        captureDuration: captureDuration,
        byteLoadDuration: byteLoadDuration,
        scannerDuration: scannerDuration,
        totalDuration: totalStopwatch.elapsed,
      );
      _emitFailure(
        failure,
        timings,
        finalCaptureDiagnostics: finalCaptureDiagnostics,
      );
      return EngineResult.failure(failure);
    } finally {
      _operationInProgress = false;
    }
  }

  EngineResult<bool> reset() {
    if (_disposed) return _disposedFailure();
    if (_operationInProgress) return _busyFailure();
    camera.resetTracking();
    _latestCameraState = camera.state;
    _autoCaptureArmed = true;
    _requiresFreshReadiness = true;
    _readinessProcessedFrameBaseline =
        _latestCameraState.diagnostics.processedFrameCount;
    _emit(
      CameraScanState(
        phase: _phaseForCamera(_latestCameraState),
        cameraState: _latestCameraState,
      ),
    );
    return EngineResult.success(true);
  }

  ScannerDiagnosticSnapshot? _sequenceDiagnostic(
    ScannerDiagnosticSnapshot? snapshot,
  ) {
    if (snapshot == null) return null;
    _diagnosticScanCount++;
    return snapshot.withScanSequenceIndex(_diagnosticScanCount);
  }

  Future<EngineResult<bool>> suspend() async {
    if (_disposed) return _disposedFailure();
    _cameraSessionRequested = false;
    if (_operationInProgress) return EngineResult.success(true);
    final result = await camera.suspend();
    if (_disposed) return _disposedFailure();
    if (result.isFailure) {
      return _cameraFailure(
        'CAPTURE_SCAN_CAMERA_SUSPEND_FAILED',
        'The capture-and-scan camera could not suspend.',
        result.error,
      );
    }
    _emit(
      CameraScanState(
        phase: CameraScanPhase.idle,
        cameraState: _latestCameraState,
      ),
    );
    return result;
  }

  Future<EngineResult<bool>> resume() async {
    if (_disposed) return Future.value(_disposedFailure());
    _cameraSessionRequested = true;
    if (_operationInProgress) return Future.value(EngineResult.success(true));
    switch (_latestCameraState.lifecycle) {
      case CameraLifecycleState.analyzing:
      case CameraLifecycleState.initializing:
      case CameraLifecycleState.capturing:
        return EngineResult.success(true);
      case CameraLifecycleState.ready:
        final started = await camera.startAnalysis();
        if (started.isFailure) {
          return _cameraFailure(
            'CAPTURE_SCAN_CAMERA_STREAM_FAILED',
            'The capture-and-scan analysis stream could not resume.',
            started.error,
          );
        }
        _publishCameraPhase();
        return started;
      case CameraLifecycleState.uninitialized:
      case CameraLifecycleState.error:
        return initialize();
      case CameraLifecycleState.disposed:
        return _disposedFailure();
    }
  }

  Future<EngineResult<bool>> setTorchEnabled(bool enabled) async {
    if (_disposed) return _disposedFailure();
    return camera.setTorchEnabled(enabled);
  }

  Future<EngineResult<ScanResult>> _finishFailure({
    required String code,
    required String message,
    required EngineError cause,
    required Stopwatch totalStopwatch,
    required Duration stopAnalysisDuration,
    required Duration captureDuration,
    required Duration byteLoadDuration,
    required Duration scannerDuration,
    required bool restartAnalysis,
    FinalCaptureDiagnostics? finalCaptureDiagnostics,
  }) async {
    totalStopwatch.stop();
    final restart = await _restoreCamera(restartAnalysis);
    var error = _wrapFailure(code, message, cause);
    if (restart.isFailure) {
      error = _wrapFailure(
        'CAPTURE_SCAN_CAMERA_STREAM_FAILED',
        'Camera analysis could not recover after workflow failure.',
        restart.error,
      );
    }
    final timings = FinalScanTimings(
      stopAnalysisDuration: stopAnalysisDuration,
      captureDuration: captureDuration,
      byteLoadDuration: byteLoadDuration,
      scannerDuration: scannerDuration,
      totalDuration: totalStopwatch.elapsed,
    );
    _emitFailure(
      error,
      timings,
      finalCaptureDiagnostics: finalCaptureDiagnostics,
    );
    return EngineResult.failure(error);
  }

  Future<EngineResult<bool>> _restoreCamera(bool restartAnalysis) async {
    if (_disposed) return _disposedFailure();
    if (!_cameraSessionRequested) return camera.suspend();
    if (!restartAnalysis) return EngineResult.success(true);
    return camera.startAnalysis();
  }

  void _onCameraState(CameraEngineState cameraState) {
    _latestCameraState = cameraState;
    if (_disposed || _operationInProgress) return;
    final resolvedPageId = cameraState.analysis?.tracking.resolvedPageId;
    if (resolvedPageId != null) {
      final matching = _context.availablePages
          .where((page) => page.pageId == resolvedPageId)
          .firstOrNull;
      if (matching != null && _context.pageId != resolvedPageId) {
        _context = _context.withPage(matching);
        _autoCaptureArmed = true;
      }
      if (_completedPageIds.contains(resolvedPageId)) {
        _autoCaptureArmed = false;
        _publishCameraPhase();
        return;
      }
    }
    if (_requiresFreshReadiness &&
        cameraState.diagnostics.processedFrameCount >
            _readinessProcessedFrameBaseline) {
      _requiresFreshReadiness = false;
    }
    if (_state.phase == CameraScanPhase.scanCompleted ||
        _state.phase == CameraScanPhase.scanFailed) {
      return;
    }
    _publishCameraPhase();
    if (autoCaptureEnabled &&
        _autoCaptureArmed &&
        !_requiresFreshReadiness &&
        cameraState.autoCaptureRequested &&
        cameraState.readiness.isReady) {
      unawaited(captureAndScan());
    }
  }

  void _publishCameraPhase() {
    final error = _latestCameraState.error;
    if (_latestCameraState.lifecycle == CameraLifecycleState.error &&
        error != null) {
      _emitFailure(
        _wrapFailure(
          'CAPTURE_SCAN_CAMERA_FAILED',
          'The camera entered an error state.',
          error,
        ),
        FinalScanTimings.zero,
      );
      return;
    }
    _emit(
      CameraScanState(
        phase: _phaseForCamera(_latestCameraState),
        cameraState: _latestCameraState,
      ),
    );
  }

  CameraScanPhase _phaseForCamera(CameraEngineState cameraState) =>
      switch (cameraState.lifecycle) {
        CameraLifecycleState.uninitialized => CameraScanPhase.idle,
        CameraLifecycleState.initializing => CameraScanPhase.cameraInitializing,
        CameraLifecycleState.ready => CameraScanPhase.cameraReady,
        CameraLifecycleState.analyzing =>
          !_requiresFreshReadiness && cameraState.readiness.isReady
              ? CameraScanPhase.readyToCapture
              : CameraScanPhase.tracking,
        CameraLifecycleState.capturing => CameraScanPhase.capturing,
        CameraLifecycleState.error => CameraScanPhase.scanFailed,
        CameraLifecycleState.disposed => CameraScanPhase.disposed,
      };

  EngineResult<bool> _cameraFailure(
    String code,
    String message,
    EngineError cause,
  ) {
    final error = _wrapFailure(code, message, cause);
    _emitFailure(error, FinalScanTimings.zero);
    return EngineResult.failure(error);
  }

  void _emitFailure(
    EngineError error,
    FinalScanTimings timings, {
    FinalCaptureDiagnostics? finalCaptureDiagnostics,
  }) {
    _emit(
      CameraScanState(
        phase: CameraScanPhase.scanFailed,
        cameraState: _latestCameraState,
        error: error,
        finalScanTimings: timings,
        finalCaptureDiagnostics: finalCaptureDiagnostics,
      ),
    );
  }

  EngineError _wrapFailure(String code, String message, EngineError cause) =>
      EngineError(
        code: code,
        message: message,
        details: {
          'causeCode': cause.code,
          'causeMessage': cause.message,
          'causeDetails': cause.details,
        },
      );

  bool _isPageResolutionFailure(String code) => const {
    'SCAN_UNKNOWN_PAGE_MARKERS',
    'SCAN_DUPLICATE_PAGE_MARKERS',
    'SCAN_PAGE_ALREADY_COMPLETED',
  }.contains(code);

  EngineResult<bool> _busyFailure() => EngineResult.failure(_busyError());

  EngineError _busyError() => EngineError(
    code: 'CAPTURE_SCAN_BUSY',
    message: 'A capture-and-scan operation is already running.',
  );

  EngineResult<bool> _disposedFailure() =>
      EngineResult.failure(_disposedError());

  EngineError _disposedError() => EngineError(
    code: 'CAPTURE_SCAN_DISPOSED',
    message: 'The capture-and-scan coordinator has been disposed.',
  );

  void _emit(CameraScanState state) {
    if (_disposed && state.phase != CameraScanPhase.disposed) return;
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cameraSessionRequested = false;
    await _cameraSubscription.cancel();
    await scanner.dispose();
    await camera.dispose();
    _emit(
      CameraScanState(
        phase: CameraScanPhase.disposed,
        cameraState: camera.state,
      ),
    );
    await _states.close();
  }
}
