import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../../engines/aruco/infrastructure/opencv_aruco_vision_backend.dart';
import '../../../engines/preprocessing/infrastructure/opencv_preprocessing_backend.dart';
import '../../../engines/scanner/domain/scan_result.dart';
import '../../../engines/scanner/domain/scanner_diagnostic_snapshot.dart';
import '../../../engines/scanner/infrastructure/offline_scanner_composition.dart';
import '../../real_scanner/scanner_identity_validation.dart';
import '../domain/camera_scan_context.dart';
import '../domain/camera_scan_ports.dart';

/// Persistent final-scanner isolate. Only Dart values and transferable bytes
/// cross this boundary; OpenCV resources are constructed and disposed inside
/// the worker isolate by the P5-P9 composition.
final class IsolateOfflineScannerRunner implements OfflineScanRunner {
  IsolateOfflineScannerRunner({ScanResult? testResult, EngineError? testError})
    : assert(testResult == null || testError == null),
      _testResult = testResult,
      _testError = testError;

  /// Pure-Dart result injection is used only to test the real isolate protocol
  /// on hosts where native OpenCV is intentionally unavailable.
  final ScanResult? _testResult;
  final EngineError? _testError;
  Isolate? _isolate;
  ReceivePort? _responses;
  ReceivePort? _errors;
  ReceivePort? _exits;
  SendPort? _workerPort;
  Future<void>? _starting;
  final Map<int, _PendingScan> _pending = {};
  var _nextRequestId = 0;
  var _completedScans = 0;
  var _disposed = false;
  Completer<void>? _workerDisposed;

  @override
  Future<EngineResult<FinalScannerRun>> scan({
    required Uint8List encodedImage,
    required CameraScanContext context,
    bool includeDiagnostics = false,
  }) async {
    if (_disposed) return EngineResult.failure(_disposedError());
    if (encodedImage.isEmpty) {
      return EngineResult.failure(
        EngineError(
          code: 'FINAL_SCANNER_IMAGE_EMPTY',
          message: 'The final scanner received no encoded still bytes.',
        ),
      );
    }
    try {
      final startupStopwatch = Stopwatch()..start();
      await _ensureStarted();
      startupStopwatch.stop();
      if (_disposed || _workerPort == null) {
        return EngineResult.failure(_disposedError());
      }
      final requestId = _nextRequestId++;
      final completer = Completer<_WorkerScanResponse>();
      final stopwatch = Stopwatch()..start();
      _pending[requestId] = _PendingScan(completer, stopwatch);
      _workerPort!.send(
        _WorkerScanRequest(
          requestId: requestId,
          encodedImage: TransferableTypedData.fromList([encodedImage]),
          context: context,
          includeDiagnostics: includeDiagnostics,
        ),
      );
      final response = await completer.future;
      stopwatch.stop();
      if (response.result.isFailure) {
        return EngineResult.failure(response.result.error);
      }
      final overhead = stopwatch.elapsed - response.workerDuration;
      final run = FinalScannerRun(
        result: response.result.value,
        workerDuration: response.workerDuration,
        isolateOverhead: overhead.isNegative ? Duration.zero : overhead,
        workerReused: _completedScans > 0,
        workerStartupDuration: _completedScans == 0
            ? startupStopwatch.elapsed
            : Duration.zero,
        transferredByteCount: response.transferredByteCount,
        transferredByteChecksum: response.transferredByteChecksum,
        diagnosticSnapshot: response.diagnosticSnapshot,
      );
      _completedScans++;
      return EngineResult.success(run);
    } on Object catch (error) {
      return EngineResult.failure(_workerFailure(error));
    }
  }

  Future<void> _ensureStarted() => _starting ??= _start();

  Future<void> _start() async {
    final ready = Completer<void>();
    _responses = ReceivePort();
    _errors = ReceivePort();
    _exits = ReceivePort();
    _responses!.listen((message) {
      if (message is SendPort) {
        _workerPort = message;
        if (!ready.isCompleted) ready.complete();
      } else if (message is _WorkerScanResponse) {
        _pending.remove(message.requestId)?.completer.complete(message);
      } else if (message is _WorkerDisposed) {
        _workerDisposed?.complete();
      }
    });
    _errors!.listen((error) => _failWorker(error));
    _exits!.listen((_) => _failWorker('Final scanner worker exited.'));
    _isolate = await Isolate.spawn<_WorkerBootstrap>(
      _finalScannerWorkerMain,
      _WorkerBootstrap(_responses!.sendPort, _testResult, _testError),
      debugName: 'final-scanner-worker',
      onError: _errors!.sendPort,
      onExit: _exits!.sendPort,
    );
    await ready.future;
  }

  void _failWorker(Object error) {
    if (_workerDisposed != null && !_workerDisposed!.isCompleted) {
      _workerDisposed!.complete();
    }
    final failure = _WorkerScanResponse.failure(_workerFailure(error));
    for (final pending in _pending.values) {
      if (!pending.completer.isCompleted) {
        pending.completer.complete(failure);
      }
    }
    _pending.clear();
  }

  EngineError _workerFailure(Object error) => EngineError(
    code: 'FINAL_SCANNER_WORKER_FAILED',
    message: 'The dedicated final scanner worker failed.',
    details: {'cause': error.toString()},
  );

  EngineError _disposedError() => EngineError(
    code: 'FINAL_SCANNER_WORKER_DISPOSED',
    message: 'The dedicated final scanner worker has been disposed.',
  );

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (_workerPort != null) {
      _workerDisposed = Completer<void>();
      _workerPort!.send(const _WorkerDispose());
      await _workerDisposed!.future;
    }
    _isolate?.kill(priority: Isolate.immediate);
    _failWorker(_disposedError());
    _responses?.close();
    _errors?.close();
    _exits?.close();
    _workerPort = null;
    _isolate = null;
  }
}

final class _PendingScan {
  const _PendingScan(this.completer, this.stopwatch);

  final Completer<_WorkerScanResponse> completer;
  final Stopwatch stopwatch;
}

final class _WorkerScanRequest {
  const _WorkerScanRequest({
    required this.requestId,
    required this.encodedImage,
    required this.context,
    required this.includeDiagnostics,
  });

  final int requestId;
  final TransferableTypedData encodedImage;
  final CameraScanContext context;
  final bool includeDiagnostics;
}

final class _WorkerScanResponse {
  const _WorkerScanResponse({
    required this.requestId,
    required this.result,
    required this.workerDuration,
    required this.transferredByteCount,
    required this.transferredByteChecksum,
    required this.diagnosticSnapshot,
  });

  factory _WorkerScanResponse.failure(EngineError error) => _WorkerScanResponse(
    requestId: -1,
    result: EngineResult.failure(error),
    workerDuration: Duration.zero,
    transferredByteCount: 0,
    transferredByteChecksum: 0,
    diagnosticSnapshot: null,
  );

  final int requestId;
  final EngineResult<ScanResult> result;
  final Duration workerDuration;
  final int transferredByteCount;
  final int transferredByteChecksum;
  final ScannerDiagnosticSnapshot? diagnosticSnapshot;
}

final class _WorkerDispose {
  const _WorkerDispose();
}

final class _WorkerDisposed {
  const _WorkerDisposed();
}

final class _WorkerBootstrap {
  const _WorkerBootstrap(this.mainPort, this.testResult, this.testError);

  final SendPort mainPort;
  final ScanResult? testResult;
  final EngineError? testError;
}

void _finalScannerWorkerMain(_WorkerBootstrap bootstrap) {
  final inbox = ReceivePort();
  final alignmentBackend =
      bootstrap.testResult == null && bootstrap.testError == null
      ? OpenCvArucoVisionBackend()
      : null;
  final scanner = bootstrap.testResult == null && bootstrap.testError == null
      ? OfflineScannerComposition.create(
          alignmentBackend: alignmentBackend!,
          preprocessingBackend: const OpenCvPreprocessingBackend(),
        )
      : null;
  bootstrap.mainPort.send(inbox.sendPort);
  inbox.listen((message) {
    if (message is _WorkerDispose) {
      alignmentBackend?.dispose();
      inbox.close();
      bootstrap.mainPort.send(const _WorkerDisposed());
      Isolate.exit();
    }
    if (message is! _WorkerScanRequest) return;
    final stopwatch = Stopwatch()..start();
    EngineResult<ScanResult> result;
    var transferredByteCount = 0;
    var transferredByteChecksum = 0;
    ScannerDiagnosticSnapshot? diagnosticSnapshot;
    try {
      final bytes = message.encodedImage.materialize().asUint8List();
      transferredByteCount = bytes.length;
      // The checksum exists only for pure-Dart isolate protocol tests. The
      // production scanner never performs an O(N) diagnostic pass over JPEG.
      if (bootstrap.testResult != null || bootstrap.testError != null) {
        transferredByteChecksum = bytes.fold<int>(
          0,
          (sum, byte) => (sum + byte) & 0x7fffffff,
        );
      }
      if (scanner != null) {
        result = scanner.scan(
          encodedImage: bytes,
          template: message.context.template,
          pageLayout: message.context.pageLayout,
          config: message.context.scannerConfig,
          diagnosticSink: message.includeDiagnostics
              ? (snapshot) => diagnosticSnapshot = snapshot
              : null,
          packetScanContext: message.context.packetScanContext,
        );
      } else {
        result = bootstrap.testError != null
            ? EngineResult.failure(bootstrap.testError!)
            : EngineResult.success(bootstrap.testResult!);
      }
      if (result.isSuccess) {
        final resultIdentity = validateScanResultIdentity(
          result.value,
          message.context,
        );
        if (resultIdentity.isFailure) {
          result = EngineResult.failure(resultIdentity.error);
        }
      }
    } on Object catch (error) {
      result = EngineResult.failure(
        EngineError(
          code: 'FINAL_SCANNER_WORKER_FAILED',
          message: 'The dedicated final scanner worker failed.',
          details: {'cause': error.toString()},
        ),
      );
    }
    stopwatch.stop();
    bootstrap.mainPort.send(
      _WorkerScanResponse(
        requestId: message.requestId,
        result: result,
        workerDuration: stopwatch.elapsed,
        transferredByteCount: transferredByteCount,
        transferredByteChecksum: transferredByteChecksum,
        diagnosticSnapshot: diagnosticSnapshot,
      ),
    );
  });
}
