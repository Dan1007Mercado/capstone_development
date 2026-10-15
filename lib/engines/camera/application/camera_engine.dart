import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../aruco/domain/image_geometry.dart';
import '../domain/camera_backend.dart';
import '../domain/camera_engine_config.dart';
import '../domain/camera_models.dart';

final class CameraEngine {
  CameraEngine({
    required this.backend,
    required this.analyzer,
    CameraEngineConfig? config,
  }) : config = config ?? CameraEngineConfig();

  final CameraBackend backend;
  final CameraFrameAnalyzer analyzer;
  final CameraEngineConfig config;

  final StreamController<CameraEngineState> _states =
      StreamController<CameraEngineState>.broadcast();
  CameraEngineState _state = const CameraEngineState.uninitialized();
  bool _analysisBusy = false;
  bool _disposed = false;
  DateTime? _lastAcceptedFrameAt;
  DateTime? _lastAutoCaptureRequestAt;
  List<ImagePoint>? _previousRegistrationPoints;
  double? _previousAreaRatio;
  int _stableFrameCount = 0;
  int _receivedFrames = 0;
  int _acceptedFrames = 0;
  int _processedFrames = 0;
  int _droppedFrames = 0;
  Duration _totalAnalysisDuration = Duration.zero;
  final Queue<DateTime> _processedFrameTimes = Queue<DateTime>();

  CameraEngineState get state => _state;
  CameraDiagnostics get diagnostics => _diagnostics;
  Stream<CameraEngineState> get states => _states.stream;

  Future<EngineResult<bool>> initialize() async {
    if (_disposed) return _disposedFailure();
    if (_state.lifecycle != CameraLifecycleState.uninitialized &&
        _state.lifecycle != CameraLifecycleState.error) {
      return _failure(
        'CAMERA_INITIALIZATION_FAILED',
        'Camera can only initialize from an uninitialized or error state.',
      );
    }
    _emit(_copyState(lifecycle: CameraLifecycleState.initializing));
    final result = await backend.initialize(config);
    if (_disposed) return _disposedFailure();
    if (result.isFailure) {
      _emit(
        _copyState(lifecycle: CameraLifecycleState.error, error: result.error),
      );
      return EngineResult.failure(result.error);
    }
    _emit(
      CameraEngineState(
        lifecycle: CameraLifecycleState.ready,
        previewInfo: result.value,
        diagnostics: _diagnostics,
        readiness: const CaptureReadiness.notReady(),
      ),
    );
    return EngineResult.success(true);
  }

  Future<EngineResult<bool>> startAnalysis() async {
    if (_disposed) return _disposedFailure();
    if (_state.lifecycle != CameraLifecycleState.ready) {
      return _failure(
        'CAMERA_STREAM_FAILED',
        'Analysis can start only while the camera is ready.',
      );
    }
    final result = await backend.startAnalysis(_onFrame);
    if (result.isFailure) {
      _emit(
        _copyState(lifecycle: CameraLifecycleState.error, error: result.error),
      );
      return result;
    }
    _emit(_copyState(lifecycle: CameraLifecycleState.analyzing));
    return result;
  }

  Future<EngineResult<bool>> stopAnalysis() async {
    if (_disposed) return _disposedFailure();
    if (_state.lifecycle != CameraLifecycleState.analyzing) {
      return EngineResult.success(true);
    }
    final result = await backend.stopAnalysis();
    if (result.isFailure) {
      _emit(
        _copyState(lifecycle: CameraLifecycleState.error, error: result.error),
      );
      return result;
    }
    _resetStability();
    _emit(_copyState(lifecycle: CameraLifecycleState.ready));
    return result;
  }

  Future<EngineResult<CapturedPageImage>> capture() async {
    if (_disposed) {
      return EngineResult.failure(_disposedError());
    }
    final wasAnalyzing = _state.lifecycle == CameraLifecycleState.analyzing;
    if (!wasAnalyzing && _state.lifecycle != CameraLifecycleState.ready) {
      return _failure(
        'CAMERA_CAPTURE_FAILED',
        'Still capture requires a ready or analyzing camera.',
      );
    }
    if (wasAnalyzing) {
      final stopped = await backend.stopAnalysis();
      if (stopped.isFailure) {
        return EngineResult.failure(stopped.error);
      }
    }
    _emit(_copyState(lifecycle: CameraLifecycleState.capturing));
    final capture = await backend.captureStill();
    if (_disposed) return EngineResult.failure(_disposedError());

    if (wasAnalyzing) {
      final restarted = await backend.startAnalysis(_onFrame);
      if (restarted.isFailure) {
        _emit(
          _copyState(
            lifecycle: CameraLifecycleState.error,
            error: restarted.error,
          ),
        );
        return EngineResult.failure(restarted.error);
      }
    }
    if (capture.isFailure) {
      _emit(
        _copyState(
          lifecycle: wasAnalyzing
              ? CameraLifecycleState.analyzing
              : CameraLifecycleState.ready,
          error: capture.error,
        ),
      );
      return capture;
    }
    _emit(
      _copyState(
        lifecycle: wasAnalyzing
            ? CameraLifecycleState.analyzing
            : CameraLifecycleState.ready,
      ),
    );
    return capture;
  }

  Future<EngineResult<bool>> suspend() async {
    if (_disposed) return _disposedFailure();
    if (_state.lifecycle == CameraLifecycleState.analyzing) {
      await backend.stopAnalysis();
    }
    await backend.dispose();
    _resetStability();
    _emit(const CameraEngineState.uninitialized());
    return EngineResult.success(true);
  }

  Future<EngineResult<bool>> resume() => initialize();

  void _onFrame(DateTime timestamp, CameraFrameMaterializer materialize) {
    if (_disposed || _state.lifecycle != CameraLifecycleState.analyzing) return;
    _receivedFrames++;
    final lastAccepted = _lastAcceptedFrameAt;
    if (_analysisBusy ||
        (lastAccepted != null &&
            timestamp.difference(lastAccepted) < config.analysisInterval)) {
      _droppedFrames++;
      return;
    }
    _analysisBusy = true;
    _lastAcceptedFrameAt = timestamp;
    _acceptedFrames++;
    final totalStopwatch = Stopwatch()..start();
    final materializationStopwatch = Stopwatch()..start();
    late final CameraAnalysisFrame frame;
    try {
      // This must remain synchronous so native CameraImage resources are not
      // retained beyond the plugin callback that owns them.
      frame = materialize();
      materializationStopwatch.stop();
    } on Object catch (error) {
      materializationStopwatch.stop();
      totalStopwatch.stop();
      _analysisBusy = false;
      _emit(
        _copyState(
          lifecycle: CameraLifecycleState.error,
          error: EngineError(
            code: 'CAMERA_FRAME_MATERIALIZATION_FAILED',
            message: 'An accepted camera frame could not be materialized.',
            details: {'cause': error.toString()},
          ),
        ),
      );
      return;
    }
    unawaited(
      _analyze(frame, materializationStopwatch.elapsed, totalStopwatch),
    );
  }

  Future<void> _analyze(
    CameraAnalysisFrame frame,
    Duration materializationDuration,
    Stopwatch totalStopwatch,
  ) async {
    final result = await analyzer.analyze(frame, config);
    totalStopwatch.stop();
    _analysisBusy = false;
    if (_disposed || _state.lifecycle != CameraLifecycleState.analyzing) return;
    if (result.isFailure) {
      _emit(
        _copyState(
          lifecycle: CameraLifecycleState.error,
          error: EngineError(
            code: 'CAMERA_ANALYSIS_FAILED',
            message: 'Camera preview analysis failed.',
            details: {
              'causeCode': result.error.code,
              'causeMessage': result.error.message,
              'causeDetails': result.error.details,
            },
          ),
        ),
      );
      return;
    }

    final timings = result.value.timings.withEngineDurations(
      materializationDuration: materializationDuration,
      totalDuration: totalStopwatch.elapsed,
    );
    _processedFrames++;
    _totalAnalysisDuration += timings.totalDuration;
    _processedFrameTimes.addLast(frame.timestamp);
    while (_processedFrameTimes.length > config.stabilityWindowSize) {
      _processedFrameTimes.removeFirst();
    }
    final evaluation = _evaluate(result.value, frame.timestamp);
    _emit(
      CameraEngineState(
        lifecycle: CameraLifecycleState.analyzing,
        previewInfo: _state.previewInfo,
        analysis: CameraAnalysisState(
          tracking: MarkerTrackingState(
            detectedMarkerIds: result.value.detectedMarkerIds,
            registrationPoints: result.value.registrationPoints,
          ),
          quality: FrameQuality(
            brightness: result.value.brightness,
            sharpness: result.value.sharpness,
            pageAreaRatio: result.value.pageAreaRatio,
            perspectiveRatio: result.value.perspectiveRatio,
          ),
          readiness: evaluation.$1,
          stabilityScore: evaluation.$2,
          processingDuration: timings.totalDuration,
          sourceFrameSize: result.value.frameSize,
          analysisFrameSize: result.value.analysisFrameSize,
          analysisScaleX: result.value.analysisScaleX,
          analysisScaleY: result.value.analysisScaleY,
          timings: timings,
          sensorOrientationDegrees: frame.sensorOrientationDegrees,
          deviceOrientation: frame.deviceOrientation,
        ),
        diagnostics: _diagnostics,
        readiness: evaluation.$1,
        autoCaptureRequested: evaluation.$3,
      ),
    );
  }

  (CaptureReadiness, double, bool) _evaluate(
    CameraFrameObservation observation,
    DateTime timestamp,
  ) {
    final expected = config.markerIds.values.toSet();
    final detected = observation.detectedMarkerIds.toSet();
    CaptureReadinessStatus? failure;
    if (config.requireAllMarkers && !detected.containsAll(expected)) {
      failure = CaptureReadinessStatus.markersMissing;
    } else if ((observation.pageAreaRatio ?? 0) < config.minimumPageAreaRatio ||
        (observation.minimumMarkerSidePixels ?? 0) <
            config.minimumMarkerSidePixels) {
      failure = CaptureReadinessStatus.tooSmall;
    } else if ((observation.perspectiveRatio ?? double.infinity) >
        config.maximumPerspectiveRatio) {
      failure = CaptureReadinessStatus.tooSkewed;
    } else if (observation.brightness < config.minimumBrightness) {
      failure = CaptureReadinessStatus.tooDark;
    } else if (observation.brightness > config.maximumBrightness) {
      failure = CaptureReadinessStatus.tooBright;
    } else if (observation.sharpness < config.minimumSharpness) {
      failure = CaptureReadinessStatus.tooBlurry;
    }

    var stabilityScore = 0.0;
    if (failure != null || observation.registrationPoints.length != 4) {
      _resetStability();
    } else {
      final previous = _previousRegistrationPoints;
      if (previous == null) {
        _stableFrameCount = 1;
        stabilityScore = 1;
      } else {
        final diagonal = math.sqrt(
          observation.frameSize.width * observation.frameSize.width +
              observation.frameSize.height * observation.frameSize.height,
        );
        var maximumDisplacement = 0.0;
        for (var index = 0; index < 4; index++) {
          maximumDisplacement = math.max(
            maximumDisplacement,
            previous[index].distanceTo(observation.registrationPoints[index]) /
                diagonal,
          );
        }
        final areaChange =
            (observation.pageAreaRatio! -
                    (_previousAreaRatio ?? observation.pageAreaRatio!))
                .abs();
        final motion = math.max(maximumDisplacement, areaChange);
        stabilityScore = (1 - motion / config.maximumMotionThreshold)
            .clamp(0, 1)
            .toDouble();
        if (motion <= config.maximumMotionThreshold) {
          _stableFrameCount = math.min(
            _stableFrameCount + 1,
            config.stabilityWindowSize,
          );
        } else {
          _stableFrameCount = 1;
        }
      }
      _previousRegistrationPoints = List.of(observation.registrationPoints);
      _previousAreaRatio = observation.pageAreaRatio;
      if (_stableFrameCount < config.minimumStableFrames) {
        failure = CaptureReadinessStatus.unstable;
      }
    }

    final readiness = CaptureReadiness(
      status: failure ?? CaptureReadinessStatus.ready,
      stableFrameCount: _stableFrameCount,
      requiredStableFrameCount: config.minimumStableFrames,
    );
    var autoCaptureRequested = false;
    if (readiness.isReady && config.autoCaptureEnabled) {
      final lastRequest = _lastAutoCaptureRequestAt;
      if (lastRequest == null ||
          timestamp.difference(lastRequest) >= config.captureCooldown) {
        _lastAutoCaptureRequestAt = timestamp;
        autoCaptureRequested = true;
      }
    }
    return (readiness, stabilityScore, autoCaptureRequested);
  }

  CameraDiagnostics get _diagnostics {
    var estimatedFps = 0.0;
    if (_processedFrameTimes.length > 1) {
      final span = _processedFrameTimes.last.difference(
        _processedFrameTimes.first,
      );
      if (span.inMicroseconds > 0) {
        estimatedFps =
            (_processedFrameTimes.length - 1) /
            (span.inMicroseconds / Duration.microsecondsPerSecond);
      }
    }
    return CameraDiagnostics(
      receivedFrameCount: _receivedFrames,
      acceptedFrameCount: _acceptedFrames,
      processedFrameCount: _processedFrames,
      droppedFrameCount: _droppedFrames,
      estimatedAnalysisFps: estimatedFps,
      averageAnalysisDuration: _processedFrames == 0
          ? Duration.zero
          : Duration(
              microseconds:
                  _totalAnalysisDuration.inMicroseconds ~/ _processedFrames,
            ),
    );
  }

  void _resetStability() {
    _previousRegistrationPoints = null;
    _previousAreaRatio = null;
    _stableFrameCount = 0;
  }

  CameraEngineState _copyState({
    CameraLifecycleState? lifecycle,
    CameraPreviewInfo? previewInfo,
    CameraAnalysisState? analysis,
    CameraDiagnostics? diagnostics,
    CaptureReadiness? readiness,
    EngineError? error,
    bool autoCaptureRequested = false,
  }) => CameraEngineState(
    lifecycle: lifecycle ?? _state.lifecycle,
    previewInfo: previewInfo ?? _state.previewInfo,
    analysis: analysis ?? _state.analysis,
    diagnostics: diagnostics ?? _state.diagnostics,
    readiness: readiness ?? _state.readiness,
    error: error,
    autoCaptureRequested: autoCaptureRequested,
  );

  void _emit(CameraEngineState state) {
    if (_disposed && state.lifecycle != CameraLifecycleState.disposed) return;
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    final wasAnalyzing = _state.lifecycle == CameraLifecycleState.analyzing;
    _disposed = true;
    if (wasAnalyzing) await backend.stopAnalysis();
    await analyzer.dispose();
    await backend.dispose();
    _state = CameraEngineState(
      lifecycle: CameraLifecycleState.disposed,
      diagnostics: _diagnostics,
      readiness: const CaptureReadiness.notReady(),
    );
    if (!_states.isClosed) {
      _states.add(_state);
      await _states.close();
    }
  }

  EngineResult<T> _failure<T>(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );

  EngineResult<bool> _disposedFailure() =>
      EngineResult.failure(_disposedError());

  EngineError _disposedError() => EngineError(
    code: 'CAMERA_DISPOSED',
    message: 'The camera engine has already been disposed.',
  );
}
