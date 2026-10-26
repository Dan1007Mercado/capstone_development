import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import '../../../core/errors/engine_error.dart';
import '../../../core/ids/identifiers.dart';
import '../../../core/result/engine_result.dart';
import '../../aruco/domain/image_geometry.dart';
import '../domain/camera_backend.dart';
import '../domain/camera_engine_config.dart';
import '../domain/camera_models.dart';
import '../domain/live_frame_analysis.dart';

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
  PageId? _previousPageId;
  int _stableFrameCount = 0;
  int _receivedFrames = 0;
  int _acceptedFrames = 0;
  int _processedFrames = 0;
  int _droppedFrames = 0;
  Duration _totalAnalysisDuration = Duration.zero;
  Duration _totalPaperEdgeDetectionDuration = Duration.zero;
  Duration _totalArucoDuration = Duration.zero;
  int _paperEdgeDetections = 0;
  int _paperEdgeDetectionFailures = 0;
  String? _lastPaperEdgeDetectionError;
  int _paperEdgeTemporaryLosses = 0;
  bool _documentTemporarilyLost = false;
  bool _documentPresent = false;
  int _paperEdgeAcquisitions = 0;
  int _paperEdgeLosses = 0;
  int _recoverableAnalysisFailures = 0;
  String? _lastRecoverableAnalysisError;
  String? _lastErrorCode;
  String? _lastErrorStage;
  String? _lastErrorRootCause;
  int _lifecycleTransitionCount = 0;
  CameraLifecycleState? _previousLifecycle;
  CameraLifecycleState _currentLifecycle = CameraLifecycleState.uninitialized;
  int _trackingGeneration = 0;
  int _arucoAttemptedFrames = 0;
  int _readyFrames = 0;
  final Queue<DateTime> _processedFrameTimes = Queue<DateTime>();
  final Map<CaptureReadinessStatus, Duration> _readinessDurations = {};
  CaptureReadinessStatus? _lastReadinessStatus;
  DateTime? _lastReadinessEvaluatedAt;
  DateTime? _firstPageRecognizedAt;
  Duration? _firstRecognitionToReadyDuration;
  int _wrongIdentityStreak = 0;
  bool _wrongIdentityConfirmed = false;
  DateTime? _analysisStartedAt;
  Duration? _timeToFirstMarker;
  Duration? _timeToFirstIdentity;
  Duration? _timeToReady;

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
      _recordError(result.error, stage: 'initialization');
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
      _recordError(result.error, stage: 'streamStart');
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
      _recordError(result.error, stage: 'streamStop');
      _emit(
        _copyState(lifecycle: CameraLifecycleState.error, error: result.error),
      );
      return result;
    }
    resetTracking();
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
        _recordError(stopped.error, stage: 'captureStreamStop');
        return EngineResult.failure(stopped.error);
      }
    }
    _emit(_copyState(lifecycle: CameraLifecycleState.capturing));
    final capture = await backend.captureStill();
    if (_disposed) return EngineResult.failure(_disposedError());

    if (wasAnalyzing) {
      final restarted = await backend.startAnalysis(_onFrame);
      if (restarted.isFailure) {
        _recordError(restarted.error, stage: 'captureStreamRestart');
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
      _recordError(capture.error, stage: 'stillCapture');
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
      final stopped = await backend.stopAnalysis();
      if (stopped.isFailure) {
        _recordError(stopped.error, stage: 'suspendStreamStop');
        _emit(
          CameraEngineState(
            lifecycle: CameraLifecycleState.error,
            previewInfo: _state.previewInfo,
            diagnostics: _diagnostics,
            readiness: const CaptureReadiness.notReady(),
            error: stopped.error,
          ),
        );
        return stopped;
      }
    }
    await backend.dispose();
    resetTracking();
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
      _recoverableAnalysisFailures++;
      _lastRecoverableAnalysisError = error.toString();
      _recordErrorValues(
        code: 'CAMERA_FRAME_MATERIALIZATION_FAILED',
        stage: 'frameMaterialization',
        rootCause: error.toString(),
      );
      _resetStability();
      final readiness = CaptureReadiness(
        status: CaptureReadinessStatus.searching,
        stableFrameCount: 0,
        requiredStableFrameCount: config.minimumStableFrames,
      );
      _emit(
        CameraEngineState(
          lifecycle: CameraLifecycleState.analyzing,
          previewInfo: _state.previewInfo,
          diagnostics: _diagnostics,
          readiness: readiness,
        ),
      );
      return;
    }
    unawaited(
      _analyze(
        frame,
        materializationStopwatch.elapsed,
        totalStopwatch,
        _trackingGeneration,
      ),
    );
  }

  Future<void> _analyze(
    CameraAnalysisFrame frame,
    Duration materializationDuration,
    Stopwatch totalStopwatch,
    int trackingGeneration,
  ) async {
    late final EngineResult<CameraFrameObservation> result;
    try {
      result = await analyzer.analyze(frame, config);
    } on Object catch (error) {
      _recordErrorValues(
        code: 'CAMERA_ANALYSIS_FAILED',
        stage: 'frameAnalysis',
        rootCause: error.toString(),
      );
      if (_disposed || _state.lifecycle != CameraLifecycleState.analyzing) {
        return;
      }
      _resetStability();
      _emit(
        CameraEngineState(
          lifecycle: CameraLifecycleState.error,
          previewInfo: _state.previewInfo,
          diagnostics: _diagnostics,
          readiness: const CaptureReadiness.notReady(),
          error: EngineError(
            code: 'CAMERA_ANALYSIS_FAILED',
            message: 'Camera preview analysis failed unexpectedly.',
            details: {'stage': 'frameAnalysis', 'cause': error.toString()},
          ),
        ),
      );
      return;
    } finally {
      if (totalStopwatch.isRunning) totalStopwatch.stop();
      _analysisBusy = false;
    }
    if (_disposed || _state.lifecycle != CameraLifecycleState.analyzing) return;
    if (result.isFailure) {
      if (result.error.code == 'CAMERA_FRAME_ANALYSIS_RECOVERABLE') {
        _recoverableAnalysisFailures++;
        _lastRecoverableAnalysisError = result.error.message;
        _recordErrorValues(
          code: result.error.code,
          stage: 'frameAnalysis',
          rootCause:
              result.error.details['cause']?.toString() ?? result.error.message,
        );
        _resetStability();
        final readiness = CaptureReadiness(
          status: CaptureReadinessStatus.searching,
          stableFrameCount: 0,
          requiredStableFrameCount: config.minimumStableFrames,
        );
        _emit(
          CameraEngineState(
            lifecycle: CameraLifecycleState.analyzing,
            previewInfo: _state.previewInfo,
            diagnostics: _diagnostics,
            readiness: readiness,
          ),
        );
        return;
      }
      _recordErrorValues(
        code: 'CAMERA_ANALYSIS_FAILED',
        stage: 'analysisBackend',
        rootCause: '${result.error.code}: ${result.error.message}',
      );
      _resetStability();
      _emit(
        CameraEngineState(
          lifecycle: CameraLifecycleState.error,
          previewInfo: _state.previewInfo,
          diagnostics: _diagnostics,
          readiness: const CaptureReadiness.notReady(),
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
    if (trackingGeneration != _trackingGeneration) return;

    final timings = result.value.timings.withEngineDurations(
      materializationDuration: materializationDuration,
      totalDuration: totalStopwatch.elapsed,
    );
    _processedFrames++;
    _totalAnalysisDuration += timings.totalDuration;
    _totalPaperEdgeDetectionDuration += timings.paperEdgeDetectionDuration;
    if (result.value.documentFresh) _paperEdgeDetections++;
    if (result.value.documentFresh && !_documentPresent) {
      _paperEdgeAcquisitions++;
    }
    if (result.value.document == null && _documentPresent) {
      _paperEdgeLosses++;
    }
    _documentPresent = result.value.document != null;
    final temporarilyLost =
        result.value.documentTrackingPhase ==
        DocumentTrackingPhase.temporarilyLost;
    if (temporarilyLost && !_documentTemporarilyLost) {
      _paperEdgeTemporaryLosses++;
    }
    _documentTemporarilyLost = temporarilyLost;
    if (result.value.documentDetectionFailed) {
      _paperEdgeDetectionFailures++;
      _lastPaperEdgeDetectionError = result.value.documentDetectionError;
    }
    _arucoAttemptedFrames++;
    _totalArucoDuration += timings.arucoDetectionDuration;
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
            resolvedPageId: result.value.resolvedPageId,
            pageResolutionErrorCode: _wrongIdentityConfirmed
                ? result.value.pageResolutionErrorCode
                : null,
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
          document: result.value.document,
          documentFresh: result.value.documentFresh,
          documentTrackingPhase: result.value.documentTrackingPhase,
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
    final isWrongIdentity =
        observation.pageResolutionErrorCode == 'SCAN_UNKNOWN_PAGE_MARKERS' ||
        observation.pageResolutionErrorCode == 'SCAN_DUPLICATE_PAGE_MARKERS';
    _wrongIdentityStreak = isWrongIdentity ? _wrongIdentityStreak + 1 : 0;
    _wrongIdentityConfirmed = _wrongIdentityStreak >= 3;
    final expected = config.markerIds.values.toSet();
    final detected = observation.detectedMarkerIds.toSet();
    CaptureReadinessStatus? failure;
    if (config.pageMarkerSignatures.isNotEmpty &&
        observation.resolvedPageId == null) {
      failure = _wrongIdentityConfirmed
          ? CaptureReadinessStatus.unknownSheet
          : CaptureReadinessStatus.verifyingMarkers;
    } else if (config.requireAllMarkers &&
        config.pageMarkerSignatures.isEmpty &&
        !detected.containsAll(expected)) {
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
    final pageChanged =
        _previousPageId != null &&
        observation.resolvedPageId != _previousPageId;
    if (pageChanged) _resetStability();
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
      _previousPageId = observation.resolvedPageId;
      if (_stableFrameCount < config.minimumStableFrames) {
        failure = CaptureReadinessStatus.unstable;
      }
    }

    final readiness = CaptureReadiness(
      status: failure ?? CaptureReadinessStatus.ready,
      stableFrameCount: _stableFrameCount,
      requiredStableFrameCount: config.minimumStableFrames,
    );
    _recordReadinessTiming(observation, readiness.status, timestamp);
    if (readiness.isReady) _readyFrames++;
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
      readinessDurations: Map.unmodifiable(_readinessDurations),
      firstRecognitionToReadyDuration: _firstRecognitionToReadyDuration,
      paperEdgeDetectionCount: _paperEdgeDetections,
      paperEdgeDetectionFailureCount: _paperEdgeDetectionFailures,
      lastPaperEdgeDetectionError: _lastPaperEdgeDetectionError,
      paperEdgeTemporaryLossCount: _paperEdgeTemporaryLosses,
      paperEdgeAcquisitionCount: _paperEdgeAcquisitions,
      paperEdgeLossCount: _paperEdgeLosses,
      recoverableAnalysisFailureCount: _recoverableAnalysisFailures,
      lastRecoverableAnalysisError: _lastRecoverableAnalysisError,
      lastErrorCode: _lastErrorCode,
      lastErrorStage: _lastErrorStage,
      lastErrorRootCause: _lastErrorRootCause,
      lifecycleTransitionCount: _lifecycleTransitionCount,
      previousLifecycle: _previousLifecycle,
      currentLifecycle: _currentLifecycle,
      arucoAttemptedFrameCount: _arucoAttemptedFrames,
      readyFrameCount: _readyFrames,
      averagePaperEdgeDetectionDuration: _processedFrames == 0
          ? Duration.zero
          : Duration(
              microseconds:
                  _totalPaperEdgeDetectionDuration.inMicroseconds ~/
                  _processedFrames,
            ),
      averageArucoDuration: _arucoAttemptedFrames == 0
          ? Duration.zero
          : Duration(
              microseconds:
                  _totalArucoDuration.inMicroseconds ~/ _arucoAttemptedFrames,
            ),
      timeToFirstMarker: _timeToFirstMarker,
      timeToFirstIdentity: _timeToFirstIdentity,
      timeToReady: _timeToReady,
    );
  }

  void _recordReadinessTiming(
    CameraFrameObservation observation,
    CaptureReadinessStatus status,
    DateTime timestamp,
  ) {
    _analysisStartedAt ??= timestamp;
    final analysisStartedAt = _analysisStartedAt!;
    Duration sinceStart() {
      final elapsed = timestamp.difference(analysisStartedAt);
      return elapsed.isNegative ? Duration.zero : elapsed;
    }

    if (observation.detectedMarkerIds.isNotEmpty) {
      _timeToFirstMarker ??= sinceStart();
    }
    final previousAt = _lastReadinessEvaluatedAt;
    final previousStatus = _lastReadinessStatus;
    if (previousAt != null && previousStatus != null) {
      final elapsed = timestamp.difference(previousAt);
      if (!elapsed.isNegative) {
        _readinessDurations[previousStatus] =
            (_readinessDurations[previousStatus] ?? Duration.zero) + elapsed;
      }
    }
    _lastReadinessEvaluatedAt = timestamp;
    _lastReadinessStatus = status;
    if (observation.resolvedPageId != null) {
      _timeToFirstIdentity ??= sinceStart();
      _firstPageRecognizedAt ??= timestamp;
    }
    if (status == CaptureReadinessStatus.ready &&
        _firstRecognitionToReadyDuration == null &&
        _firstPageRecognizedAt != null) {
      final elapsed = timestamp.difference(_firstPageRecognizedAt!);
      _firstRecognitionToReadyDuration = elapsed.isNegative
          ? Duration.zero
          : elapsed;
    }
    if (status == CaptureReadinessStatus.ready) {
      _timeToReady ??= sinceStart();
    }
  }

  void resetTracking() {
    if (_disposed) return;
    _trackingGeneration++;
    analyzer.resetTracking();
    _documentTemporarilyLost = false;
    _documentPresent = false;
    _wrongIdentityStreak = 0;
    _wrongIdentityConfirmed = false;
    _lastAcceptedFrameAt = null;
    _lastAutoCaptureRequestAt = null;
    _resetStability();
    _emit(
      CameraEngineState(
        lifecycle: _state.lifecycle,
        previewInfo: _state.previewInfo,
        diagnostics: _diagnostics,
        readiness: _state.lifecycle == CameraLifecycleState.analyzing
            ? CaptureReadiness(
                status: CaptureReadinessStatus.searching,
                stableFrameCount: 0,
                requiredStableFrameCount: config.minimumStableFrames,
              )
            : const CaptureReadiness.notReady(),
        error: _state.error,
      ),
    );
  }

  void _recordError(EngineError error, {required String stage}) {
    _recordErrorValues(
      code: error.code,
      stage: stage,
      rootCause:
          error.details['cause']?.toString() ??
          error.details['pluginCode']?.toString() ??
          error.message,
    );
  }

  void _recordErrorValues({
    required String code,
    required String stage,
    required String rootCause,
  }) {
    _lastErrorCode = code;
    _lastErrorStage = stage;
    _lastErrorRootCause = rootCause;
  }

  void _resetStability() {
    _previousRegistrationPoints = null;
    _previousAreaRatio = null;
    _previousPageId = null;
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
    if (_currentLifecycle != state.lifecycle) {
      _previousLifecycle = _currentLifecycle;
      _currentLifecycle = state.lifecycle;
      _lifecycleTransitionCount++;
    }
    final emitted = CameraEngineState(
      lifecycle: state.lifecycle,
      previewInfo: state.previewInfo,
      analysis: state.lifecycle == CameraLifecycleState.error
          ? null
          : state.analysis,
      diagnostics: _diagnostics,
      readiness: state.readiness,
      error: state.error,
      autoCaptureRequested: state.autoCaptureRequested,
    );
    _state = emitted;
    if (!_states.isClosed) _states.add(emitted);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    final wasAnalyzing = _state.lifecycle == CameraLifecycleState.analyzing;
    _disposed = true;
    if (wasAnalyzing) await backend.stopAnalysis();
    await analyzer.dispose();
    await backend.dispose();
    _emit(
      CameraEngineState(
        lifecycle: CameraLifecycleState.disposed,
        diagnostics: _diagnostics,
        readiness: const CaptureReadiness.notReady(),
      ),
    );
    if (!_states.isClosed) {
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
