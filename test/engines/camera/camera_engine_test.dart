import 'dart:async';
import 'dart:typed_data';

import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/page_marker_signature_resolver.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/camera/application/camera_engine.dart';
import 'package:capstone_development/engines/camera/domain/camera_backend.dart';
import 'package:capstone_development/engines/camera/domain/camera_engine_config.dart';
import 'package:capstone_development/engines/camera/domain/camera_models.dart';
import 'package:capstone_development/engines/camera/domain/live_frame_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('initialize transitions to ready', () async {
    final fixture = _Fixture();
    expect((await fixture.engine.initialize()).isSuccess, isTrue);
    expect(fixture.engine.state.lifecycle, CameraLifecycleState.ready);
    expect(fixture.engine.state.previewInfo, isNotNull);
    await fixture.dispose();
  });

  test('rear camera reports the default torch state in diagnostics', () async {
    final fixture = _Fixture();
    await fixture.engine.initialize();

    expect(fixture.engine.diagnostics.torchAvailable, isTrue);
    expect(fixture.engine.diagnostics.torchEnabled, isTrue);
    expect(fixture.engine.diagnostics.torchDesiredEnabled, isTrue);
    await fixture.dispose();
  });

  test('manual torch override is retained as desired session state', () async {
    final fixture = _Fixture();
    await fixture.engine.initialize();

    final result = await fixture.engine.setTorchEnabled(false);

    expect(result.isSuccess, isTrue);
    expect(fixture.backend.torchValues, [false]);
    expect(fixture.engine.diagnostics.torchEnabled, isFalse);
    expect(fixture.engine.diagnostics.torchDesiredEnabled, isFalse);
    await fixture.dispose();
  });

  test('unsupported torch is non-fatal and remains diagnostic', () async {
    final backend = _FakeCameraBackend()
      ..torchResult = _failure('CAMERA_TORCH_UNAVAILABLE', 'unsupported');
    final fixture = _Fixture(backend: backend);
    await fixture.engine.initialize();

    final result = await fixture.engine.setTorchEnabled(false);

    expect(result.isFailure, isTrue);
    expect(fixture.engine.state.lifecycle, CameraLifecycleState.ready);
    expect(fixture.engine.diagnostics.torchAvailable, isFalse);
    expect(fixture.engine.diagnostics.lastTorchError, 'unsupported');
    await fixture.dispose();
  });

  test(
    'suspend records torch off while preserving the user preference',
    () async {
      final fixture = _Fixture();
      await fixture.engine.initialize();
      await fixture.engine.setTorchEnabled(false);

      await fixture.engine.suspend();

      expect(fixture.engine.diagnostics.torchAvailable, isFalse);
      expect(fixture.engine.diagnostics.torchEnabled, isFalse);
      expect(fixture.engine.diagnostics.torchDesiredEnabled, isFalse);
      expect(fixture.backend.disposed, isTrue);
      await fixture.dispose();
    },
  );

  test('initialization failure becomes structured error state', () async {
    final backend = _FakeCameraBackend()
      ..initializeResult = _failure('CAMERA_INITIALIZATION_FAILED', 'failed');
    final fixture = _Fixture(backend: backend);
    final result = await fixture.engine.initialize();
    expect(result.error.code, 'CAMERA_INITIALIZATION_FAILED');
    expect(fixture.engine.state.lifecycle, CameraLifecycleState.error);
    await fixture.dispose();
  });

  test('permission failure is preserved', () async {
    final backend = _FakeCameraBackend()
      ..initializeResult = _failure('CAMERA_PERMISSION_DENIED', 'denied');
    final fixture = _Fixture(backend: backend);
    expect(
      (await fixture.engine.initialize()).error.code,
      'CAMERA_PERMISSION_DENIED',
    );
    await fixture.dispose();
  });

  test('analysis starts and stops explicitly', () async {
    final fixture = _Fixture();
    await fixture.initializeAndStart();
    expect(fixture.engine.state.lifecycle, CameraLifecycleState.analyzing);
    expect(fixture.backend.startCalls, 1);
    await fixture.engine.stopAnalysis();
    expect(fixture.engine.state.lifecycle, CameraLifecycleState.ready);
    expect(fixture.backend.stopCalls, 1);
    await fixture.dispose();
  });

  test(
    'frame throttling processes only frames at the configured interval',
    () async {
      final fixture = _Fixture();
      await fixture.initializeAndStart();
      fixture.emitAt(0);
      await _settle();
      fixture.emitAt(50);
      await _settle();
      fixture.emitAt(100);
      await _settle();
      expect(fixture.analyzer.calls, 2);
      expect(fixture.engine.state.diagnostics.droppedFrameCount, 1);
      expect(fixture.backend.materializeCalls, 2);
      await fixture.dispose();
    },
  );

  test('busy analyzer drops a new eligible frame', () async {
    final analyzer = _FakeAnalyzer()..gate = Completer<void>();
    final fixture = _Fixture(analyzer: analyzer);
    await fixture.initializeAndStart();
    fixture.emitAt(0);
    await _settle();
    fixture.emitAt(200);
    expect(fixture.engine.diagnostics.droppedFrameCount, 1);
    expect(fixture.backend.materializeCalls, 1);
    analyzer.gate!.complete();
    await _settle();
    expect(analyzer.calls, 1);
    await fixture.dispose();
  });

  test(
    'next eligible frame starts immediately after prior analysis completes',
    () async {
      final analyzer = _FakeAnalyzer()..gate = Completer<void>();
      final fixture = _Fixture(analyzer: analyzer);
      await fixture.initializeAndStart();
      fixture.emitAt(0);
      await _settle();
      fixture.emitAt(200);
      expect(analyzer.calls, 1);

      analyzer.gate!.complete();
      await _settle();
      analyzer.gate = null;
      fixture.emitAt(201);
      await _settle();

      expect(analyzer.calls, 2);
      expect(fixture.backend.materializeCalls, 2);
      await fixture.dispose();
    },
  );

  test('busy analyzer never creates an unbounded queue', () async {
    final analyzer = _FakeAnalyzer()..gate = Completer<void>();
    final fixture = _Fixture(analyzer: analyzer);
    await fixture.initializeAndStart();
    for (var index = 0; index < 100; index++) {
      fixture.emitAt(index * 200);
    }
    await _settle();
    expect(analyzer.calls, 1);
    expect(fixture.engine.diagnostics.droppedFrameCount, 99);
    expect(fixture.backend.materializeCalls, 1);
    analyzer.gate!.complete();
    await _settle();
    await fixture.dispose();
  });

  test('analysis FPS config rejects zero and values above preview bounds', () {
    expect(() => CameraEngineConfig(targetAnalysisFps: 0), throwsArgumentError);
    expect(
      () => CameraEngineConfig(targetAnalysisFps: 61),
      throwsArgumentError,
    );
    for (final dimension in [720, 800, 960]) {
      expect(CameraEngineConfig(analysisMaxDimension: dimension), isNotNull);
    }
    expect(
      () => CameraEngineConfig(analysisMaxDimension: 479),
      throwsArgumentError,
    );
    expect(
      () => CameraEngineConfig(analysisMaxDimension: 1921),
      throwsArgumentError,
    );
    expect(CameraEngineConfig().analysisMaxDimension, 800);
    expect(CameraEngineConfig().paperEdgeDetectionIntervalFrames, 3);
  });

  test('detected marker IDs are preserved in engine state', () async {
    final fixture = _Fixture();
    await fixture.initializeAndStart();
    fixture.emitAt(0);
    await _settle();
    expect(fixture.engine.state.analysis!.tracking.detectedMarkerIds, [
      10,
      11,
      12,
      13,
    ]);
    await fixture.dispose();
  });

  test('missing markers are not ready', () async {
    final fixture = _Fixture(
      analyzer: _FakeAnalyzer(observation: _observation(ids: [10, 11, 12])),
    );
    await fixture.initializeAndStart();
    fixture.emitAt(0);
    await _settle();
    expect(
      fixture.engine.state.readiness.status,
      CaptureReadinessStatus.markersMissing,
    );
    await fixture.dispose();
  });

  test('all markers allow quality and stability evaluation', () async {
    final fixture = _Fixture();
    await fixture.initializeAndStart();
    fixture.emitAt(0);
    await _settle();
    expect(
      fixture.engine.state.readiness.status,
      CaptureReadinessStatus.unstable,
    );
    expect(fixture.engine.state.analysis!.quality.brightness, 128);
    await fixture.dispose();
  });

  test('too-small page is not ready', () async {
    final fixture = _Fixture(
      analyzer: _FakeAnalyzer(observation: _observation(area: 0.01)),
    );
    await fixture.initializeAndStart();
    fixture.emitAt(0);
    await _settle();
    expect(
      fixture.engine.state.readiness.status,
      CaptureReadinessStatus.tooSmall,
    );
    await fixture.dispose();
  });

  test('extreme perspective is not ready', () async {
    final fixture = _Fixture(
      analyzer: _FakeAnalyzer(observation: _observation(perspective: 20)),
    );
    await fixture.initializeAndStart();
    fixture.emitAt(0);
    await _settle();
    expect(
      fixture.engine.state.readiness.status,
      CaptureReadinessStatus.tooSkewed,
    );
    await fixture.dispose();
  });

  test(
    'moderate perspective reaches ready after the stability window',
    () async {
      final fixture = _Fixture(
        analyzer: _FakeAnalyzer(
          observations: [
            for (var index = 0; index < 3; index++)
              _observation(perspective: 4.5),
          ],
        ),
      );
      await fixture.initializeAndStart();

      await fixture.emitAndSettle(0);
      await fixture.emitAndSettle(200);
      await fixture.emitAndSettle(400);

      expect(
        fixture.engine.state.readiness.status,
        CaptureReadinessStatus.ready,
      );
      await fixture.dispose();
    },
  );

  test('too-dark frame is not ready', () async {
    final fixture = _Fixture(
      analyzer: _FakeAnalyzer(observation: _observation(brightness: 20)),
    );
    await fixture.initializeAndStart();
    fixture.emitAt(0);
    await _settle();
    expect(
      fixture.engine.state.readiness.status,
      CaptureReadinessStatus.tooDark,
    );
    await fixture.dispose();
  });

  test('too-bright frame is not ready', () async {
    final fixture = _Fixture(
      analyzer: _FakeAnalyzer(observation: _observation(brightness: 240)),
    );
    await fixture.initializeAndStart();
    fixture.emitAt(0);
    await _settle();
    expect(
      fixture.engine.state.readiness.status,
      CaptureReadinessStatus.tooBright,
    );
    await fixture.dispose();
  });

  test('blurry frame is not ready', () async {
    final fixture = _Fixture(
      analyzer: _FakeAnalyzer(observation: _observation(sharpness: 20)),
    );
    await fixture.initializeAndStart();
    fixture.emitAt(0);
    await _settle();
    expect(
      fixture.engine.state.readiness.status,
      CaptureReadinessStatus.tooBlurry,
    );
    await fixture.dispose();
  });

  test('unstable marker motion remains not ready', () async {
    final analyzer = _FakeAnalyzer(
      observations: [
        _observation(),
        _observation(points: _points(offset: 100)),
      ],
    );
    final fixture = _Fixture(analyzer: analyzer);
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);
    await fixture.emitAndSettle(200);
    expect(
      fixture.engine.state.readiness.status,
      CaptureReadinessStatus.unstable,
    );
    expect(fixture.engine.state.readiness.stableFrameCount, 1);
    await fixture.dispose();
  });

  test('required stable good frames become ready', () async {
    final fixture = _Fixture();
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);
    await fixture.emitAndSettle(200);
    await fixture.emitAndSettle(400);
    expect(fixture.engine.state.readiness.status, CaptureReadinessStatus.ready);
    await fixture.dispose();
  });

  test('one unstable frame resets stable progress', () async {
    final analyzer = _FakeAnalyzer(
      observations: [
        _observation(),
        _observation(),
        _observation(points: _points(offset: 100)),
      ],
    );
    final fixture = _Fixture(analyzer: analyzer);
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);
    await fixture.emitAndSettle(200);
    await fixture.emitAndSettle(400);
    expect(fixture.engine.state.readiness.stableFrameCount, 1);
    expect(fixture.engine.state.readiness.isReady, isFalse);
    await fixture.dispose();
  });

  test('auto-capture request appears only after stable readiness', () async {
    final fixture = _Fixture();
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);
    expect(fixture.engine.state.autoCaptureRequested, isFalse);
    await fixture.emitAndSettle(200);
    expect(fixture.engine.state.autoCaptureRequested, isFalse);
    await fixture.emitAndSettle(400);
    expect(fixture.engine.state.autoCaptureRequested, isTrue);
    await fixture.dispose();
  });

  test('auto-capture request respects cooldown', () async {
    final fixture = _Fixture();
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);
    await fixture.emitAndSettle(200);
    await fixture.emitAndSettle(400);
    expect(fixture.engine.state.autoCaptureRequested, isTrue);
    await fixture.emitAndSettle(600);
    expect(fixture.engine.state.autoCaptureRequested, isFalse);
    await fixture.emitAndSettle(2600);
    expect(fixture.engine.state.autoCaptureRequested, isTrue);
    await fixture.dispose();
  });

  test('capture uses backend still path and restarts analysis', () async {
    final fixture = _Fixture();
    await fixture.initializeAndStart();
    final result = await fixture.engine.capture();
    expect(result.isSuccess, isTrue);
    expect(result.value.encodedBytes, [7, 8, 9]);
    expect(fixture.backend.captureCalls, 1);
    expect(fixture.backend.stopCalls, 1);
    expect(fixture.backend.startCalls, 2);
    expect(fixture.engine.state.lifecycle, CameraLifecycleState.analyzing);
    await fixture.dispose();
  });

  test('capture failure is structured', () async {
    final backend = _FakeCameraBackend()
      ..captureResult = _failure('CAMERA_CAPTURE_FAILED', 'capture failed');
    final fixture = _Fixture(backend: backend);
    await fixture.initializeAndStart();
    final result = await fixture.engine.capture();
    expect(result.error.code, 'CAMERA_CAPTURE_FAILED');
    await fixture.dispose();
  });

  test('camera analysis frame defensively copies source bytes', () {
    final source = Uint8List.fromList([1, 2, 3, 4]);
    final frame = _frame(0, bytes: source, width: 2, height: 2);
    source[0] = 99;
    expect(frame.lumaBytes, [1, 2, 3, 4]);
  });

  test('dispose stops active analysis and releases resources', () async {
    final fixture = _Fixture();
    await fixture.initializeAndStart();
    await fixture.engine.dispose();
    expect(fixture.backend.stopCalls, 1);
    expect(fixture.backend.disposed, isTrue);
    expect(fixture.analyzer.disposed, isTrue);
    expect(fixture.engine.state.lifecycle, CameraLifecycleState.disposed);
  });

  test('completed analysis does not publish after dispose', () async {
    final analyzer = _FakeAnalyzer()..gate = Completer<void>();
    final fixture = _Fixture(analyzer: analyzer);
    await fixture.initializeAndStart();
    fixture.emitAt(0);
    await _settle();
    final dispose = fixture.engine.dispose();
    analyzer.gate!.complete();
    await dispose;
    expect(fixture.engine.state.lifecycle, CameraLifecycleState.disposed);
    expect(fixture.engine.state.analysis, isNull);
  });

  test(
    'deterministic frame sequences produce deterministic readiness',
    () async {
      final first = await _runStableSequence();
      final second = await _runStableSequence();
      expect(first.$1, second.$1);
      expect(first.$2, second.$2);
    },
  );

  test('diagnostics count received and processed frames', () async {
    final fixture = _Fixture();
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);
    await fixture.emitAndSettle(200);
    expect(fixture.engine.state.diagnostics.receivedFrameCount, 2);
    expect(fixture.engine.state.diagnostics.acceptedFrameCount, 2);
    expect(fixture.engine.state.diagnostics.processedFrameCount, 2);
    expect(
      fixture.engine.state.diagnostics.estimatedAnalysisFps,
      closeTo(5, .01),
    );
    await fixture.dispose();
  });

  test('analysis timing diagnostics remain internally consistent', () async {
    const timings = CameraAnalysisTimings(
      preparationDuration: Duration(milliseconds: 2),
      sharpnessDuration: Duration(milliseconds: 1),
      arucoDetectionDuration: Duration(milliseconds: 5),
      geometryDuration: Duration(milliseconds: 1),
      workerDuration: Duration(milliseconds: 10),
      isolateOverheadDuration: Duration(milliseconds: 2),
      totalDuration: Duration(milliseconds: 12),
    );
    expect(timings.measuredWorkerStages, const Duration(milliseconds: 9));
    expect(timings.isInternallyConsistent, isTrue);

    const inconsistent = CameraAnalysisTimings(
      arucoDetectionDuration: Duration(milliseconds: 11),
      workerDuration: Duration(milliseconds: 10),
      totalDuration: Duration(milliseconds: 10),
    );
    expect(inconsistent.isInternallyConsistent, isFalse);
  });

  test('engine publishes end-to-end timing for each processed frame', () async {
    final fixture = _Fixture();
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);
    final analysis = fixture.engine.state.analysis!;
    expect(analysis.timings.totalDuration, analysis.processingDuration);
    expect(analysis.timings.isInternallyConsistent, isTrue);
    await fixture.dispose();
  });

  test('diagnostics count throttled and busy drops exactly', () async {
    final fixture = _Fixture();
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);
    fixture.emitAt(20);
    fixture.emitAt(40);
    fixture.emitAt(60);
    expect(fixture.engine.diagnostics.droppedFrameCount, 3);
    expect(fixture.engine.diagnostics.receivedFrameCount, 4);
    expect(fixture.engine.diagnostics.acceptedFrameCount, 1);
    expect(fixture.backend.materializeCalls, 1);
    await fixture.dispose();
  });

  test('rejected frames do not emit one state update per frame', () async {
    final analyzer = _FakeAnalyzer()..gate = Completer<void>();
    final fixture = _Fixture(analyzer: analyzer);
    var stateEmissions = 0;
    final subscription = fixture.engine.states.listen((_) => stateEmissions++);
    await fixture.initializeAndStart();
    fixture.emitAt(0);
    await _settle();
    final emissionsBeforeDrops = stateEmissions;

    for (var index = 1; index <= 100; index++) {
      fixture.emitAt(index * 200);
    }
    await _settle();

    expect(stateEmissions, emissionsBeforeDrops);
    expect(fixture.engine.diagnostics.droppedFrameCount, 100);
    expect(fixture.backend.materializeCalls, 1);
    analyzer.gate!.complete();
    await _settle();
    await subscription.cancel();
    await fixture.dispose();
  });

  test('orchestration never overlaps heavy analyzer calls', () async {
    final analyzer = _FakeAnalyzer()..delay = const Duration(milliseconds: 5);
    final fixture = _Fixture(analyzer: analyzer);
    await fixture.initializeAndStart();
    for (var index = 0; index < 20; index++) {
      fixture.emitAt(index * 200);
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(analyzer.maximumActiveCalls, 1);
    await fixture.dispose();
  });

  test('analysis failure is wrapped with its structured cause', () async {
    final analyzer = _FakeAnalyzer()
      ..result = _failure('ARUCO_BACKEND_UNAVAILABLE', 'native unavailable');
    final fixture = _Fixture(analyzer: analyzer);
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);
    expect(fixture.engine.state.error!.code, 'CAMERA_ANALYSIS_FAILED');
    expect(
      fixture.engine.state.error!.details['causeCode'],
      'ARUCO_BACKEND_UNAVAILABLE',
    );
    expect(fixture.engine.state.analysis, isNull);
    expect(fixture.engine.diagnostics.lastErrorCode, 'CAMERA_ANALYSIS_FAILED');
    expect(
      fixture.engine.diagnostics.lastErrorRootCause,
      contains('ARUCO_BACKEND_UNAVAILABLE'),
    );
    await fixture.dispose();
  });

  test('unexpected analyzer exception releases busy state for retry', () async {
    final analyzer = _FakeAnalyzer()
      ..errorToThrow = StateError('synthetic analyzer exception');
    final fixture = _Fixture(analyzer: analyzer);
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);

    expect(fixture.engine.state.lifecycle, CameraLifecycleState.error);
    expect(fixture.engine.diagnostics.lastErrorStage, 'frameAnalysis');

    expect((await fixture.engine.initialize()).isSuccess, isTrue);
    expect((await fixture.engine.startAnalysis()).isSuccess, isTrue);
    await fixture.emitAndSettle(200);
    expect(analyzer.calls, 2);
    expect(fixture.engine.diagnostics.processedFrameCount, 1);
    await fixture.dispose();
  });

  test('a missing-marker observation resets marker readiness', () async {
    final analyzer = _FakeAnalyzer(
      observations: [
        _observation(),
        _observation(ids: const [], points: const []),
      ],
    );
    final fixture = _Fixture(
      analyzer: analyzer,
      config: CameraEngineConfig(
        minimumStableFrames: 1,
        stabilityWindowSize: 1,
      ),
    );
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);
    expect(fixture.engine.state.readiness.status, CaptureReadinessStatus.ready);
    await fixture.emitAndSettle(500);
    expect(
      fixture.engine.state.readiness.status,
      CaptureReadinessStatus.markersMissing,
    );
    await fixture.dispose();
  });

  test('every processed frame records an ArUco opportunity', () async {
    final analyzer = _FakeAnalyzer(
      observations: [
        _observation(ids: const [], points: const []),
        _observation(),
      ],
    );
    final fixture = _Fixture(analyzer: analyzer);
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);
    await fixture.emitAndSettle(200);
    final diagnostics = fixture.engine.diagnostics;
    expect(diagnostics.arucoAttemptedFrameCount, 2);
    expect(diagnostics.arucoAttemptRatio, 1);
    await fixture.dispose();
  });

  test('recoverable frame analysis failure keeps camera analyzing', () async {
    final analyzer = _FakeAnalyzer()
      ..result = _failure(
        'CAMERA_FRAME_ANALYSIS_RECOVERABLE',
        'bad frame skipped',
      );
    final fixture = _Fixture(analyzer: analyzer);
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);

    expect(fixture.engine.state.lifecycle, CameraLifecycleState.analyzing);
    expect(fixture.engine.state.error, isNull);
    expect(fixture.engine.state.readiness.isReady, isFalse);
    expect(fixture.engine.diagnostics.recoverableAnalysisFailureCount, 1);
    expect(
      fixture.engine.diagnostics.lastErrorCode,
      'CAMERA_FRAME_ANALYSIS_RECOVERABLE',
    );

    analyzer.result = null;
    await fixture.emitAndSettle(200);
    expect(analyzer.calls, 2);
    expect(fixture.engine.diagnostics.processedFrameCount, 1);
    await fixture.dispose();
  });

  test('malformed materialized frame is recoverable', () async {
    final fixture = _Fixture();
    await fixture.initializeAndStart();
    fixture.backend.emit(
      DateTime.utc(2026),
      () => throw StateError('synthetic malformed frame'),
    );
    await _settle();

    expect(fixture.engine.state.lifecycle, CameraLifecycleState.analyzing);
    expect(fixture.engine.state.error, isNull);
    expect(fixture.engine.diagnostics.recoverableAnalysisFailureCount, 1);
    expect(
      fixture.engine.diagnostics.lastErrorCode,
      'CAMERA_FRAME_MATERIALIZATION_FAILED',
    );
    expect(fixture.engine.diagnostics.lastErrorStage, 'frameMaterialization');
    await fixture.emitAndSettle(200);
    expect(fixture.analyzer.calls, 1);
    await fixture.dispose();
  });

  test('reset clears geometry and rejects an in-flight stale result', () async {
    final analyzer = _FakeAnalyzer()..gate = Completer<void>();
    final fixture = _Fixture(analyzer: analyzer);
    await fixture.initializeAndStart();
    fixture.emitAt(0);
    await _settle();

    fixture.engine.resetTracking();
    expect(fixture.engine.state.analysis, isNull);
    expect(
      fixture.engine.state.readiness.status,
      CaptureReadinessStatus.searching,
    );

    analyzer.gate!.complete();
    await _settle();
    expect(fixture.engine.state.analysis, isNull);

    analyzer.gate = null;
    await fixture.emitAndSettle(200);
    expect(fixture.engine.state.analysis, isNotNull);
    await fixture.dispose();
  });

  test('paper edge absent forever still reaches ready', () async {
    final validMarkersWithoutPaper = _observation();
    final waiting = _observation();
    final fixture = _Fixture(
      analyzer: _FakeAnalyzer(
        observations: [
          validMarkersWithoutPaper,
          waiting,
          waiting,
          waiting,
          waiting,
          validMarkersWithoutPaper,
          waiting,
          waiting,
          waiting,
          waiting,
          validMarkersWithoutPaper,
        ],
      ),
    );
    await fixture.initializeAndStart();
    for (var frame = 0; frame <= 10; frame++) {
      await fixture.emitAndSettle(frame * 100);
    }

    expect(fixture.engine.state.lifecycle, CameraLifecycleState.analyzing);
    expect(fixture.engine.state.readiness.status, CaptureReadinessStatus.ready);
    await fixture.dispose();
  });

  test('paper edge presence does not change readiness progression', () async {
    final paper = _testDocument();
    final withPaper = _Fixture(
      analyzer: _FakeAnalyzer(
        observations: [
          for (var index = 0; index < 3; index++)
            _observation(document: paper, documentFresh: true),
        ],
      ),
    );
    final withoutPaper = _Fixture(
      analyzer: _FakeAnalyzer(
        observations: [for (var index = 0; index < 3; index++) _observation()],
      ),
    );
    await withPaper.initializeAndStart();
    await withoutPaper.initializeAndStart();
    final withPaperStatuses = <CaptureReadinessStatus>[];
    final withoutPaperStatuses = <CaptureReadinessStatus>[];

    for (var frame = 0; frame < 3; frame++) {
      await withPaper.emitAndSettle(frame * 200);
      await withoutPaper.emitAndSettle(frame * 200);
      withPaperStatuses.add(withPaper.engine.state.readiness.status);
      withoutPaperStatuses.add(withoutPaper.engine.state.readiness.status);
    }

    expect(withPaperStatuses, withoutPaperStatuses);
    expect(withPaperStatuses.last, CaptureReadinessStatus.ready);
    await withPaper.dispose();
    await withoutPaper.dispose();
  });

  test('marker stability is independent of paper timing', () async {
    final validMarkersWithoutPaper = _observation();
    final fixture = _Fixture(
      analyzer: _FakeAnalyzer(
        observations: [validMarkersWithoutPaper, validMarkersWithoutPaper],
      ),
      config: CameraEngineConfig(
        minimumStableFrames: 2,
        stabilityWindowSize: 2,
      ),
    );
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);
    await fixture.emitAndSettle(1200);

    expect(fixture.engine.state.readiness.status, CaptureReadinessStatus.ready);
    expect(fixture.engine.state.readiness.stableFrameCount, 2);
    await fixture.dispose();
  });

  test('missing markers stay not ready while camera remains alive', () async {
    final fixture = _Fixture(
      analyzer: _FakeAnalyzer(
        observation: _observation(ids: const [], points: const []),
      ),
    );
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);

    expect(fixture.engine.state.lifecycle, CameraLifecycleState.analyzing);
    expect(
      fixture.engine.state.readiness.status,
      CaptureReadinessStatus.markersMissing,
    );
    await fixture.dispose();
  });

  test('page identity change requires fresh marker stability', () async {
    final sheet1 = _observation(resolvedPageId: PageId('SH1'));
    final sheet2 = _observation(resolvedPageId: PageId('SH2'));
    final fixture = _Fixture(
      analyzer: _FakeAnalyzer(observations: [sheet1, sheet1, sheet2, sheet2]),
      config: CameraEngineConfig(
        minimumStableFrames: 2,
        stabilityWindowSize: 2,
      ),
    );
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);
    await fixture.emitAndSettle(200);
    expect(fixture.engine.state.readiness.isReady, isTrue);

    await fixture.emitAndSettle(400);
    expect(
      fixture.engine.state.readiness.status,
      CaptureReadinessStatus.unstable,
    );
    expect(fixture.engine.state.readiness.stableFrameCount, 1);
    await fixture.emitAndSettle(600);
    expect(fixture.engine.state.readiness.isReady, isTrue);
    await fixture.dispose();
  });

  test('document detector failure is diagnostic and non-fatal', () async {
    final fixture = _Fixture(
      analyzer: _FakeAnalyzer(
        observation: _observation(
          documentDetectionFailed: true,
          documentDetectionError: 'synthetic contour failure',
        ),
      ),
      config: CameraEngineConfig(
        minimumStableFrames: 1,
        stabilityWindowSize: 1,
      ),
    );
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);

    expect(fixture.engine.state.lifecycle, CameraLifecycleState.analyzing);
    expect(fixture.engine.state.readiness.isReady, isTrue);
    expect(fixture.engine.diagnostics.paperEdgeDetectionFailureCount, 1);
    expect(
      fixture.engine.diagnostics.lastPaperEdgeDetectionError,
      'synthetic contour failure',
    );
    await fixture.dispose();
  });

  test('bad paper perspective does not control marker readiness', () async {
    final movingDocument = _testDocument(perspectiveRatio: 99);
    final observations = [
      for (var index = 0; index < 3; index++)
        _observation(
          document: movingDocument,
          documentFresh: true,
          resolvedPageId: PageId('SH1'),
        ),
    ];
    final fixture = _Fixture(
      analyzer: _FakeAnalyzer(observations: observations),
    );
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);
    await fixture.emitAndSettle(200);
    await fixture.emitAndSettle(400);

    expect(fixture.engine.state.readiness.status, CaptureReadinessStatus.ready);
    expect(fixture.engine.diagnostics.arucoAttemptedFrameCount, 3);
    await fixture.dispose();
  });

  test('retained visual document does not authorize capture', () async {
    final fixture = _Fixture(
      analyzer: _FakeAnalyzer(
        observation: _observation(
          ids: const [],
          points: const [],
          document: _testDocument(),
          documentFresh: false,
          documentTrackingPhase: DocumentTrackingPhase.temporarilyLost,
        ),
      ),
    );
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);

    expect(fixture.engine.state.analysis!.document, isNotNull);
    expect(fixture.engine.state.analysis!.documentFresh, isFalse);
    expect(
      fixture.engine.state.readiness.status,
      CaptureReadinessStatus.markersMissing,
    );
    expect(fixture.engine.state.autoCaptureRequested, isFalse);
    await fixture.dispose();
  });

  test('diagnostics count temporary-loss episodes once', () async {
    final retained = _observation(
      ids: const [],
      points: const [],
      document: _testDocument(),
      documentFresh: false,
      documentTrackingPhase: DocumentTrackingPhase.temporarilyLost,
    );
    final fixture = _Fixture(
      analyzer: _FakeAnalyzer(
        observations: [
          retained,
          retained,
          _observation(ids: const [], points: const []),
          retained,
        ],
      ),
    );
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);
    await fixture.emitAndSettle(200);
    await fixture.emitAndSettle(400);
    await fixture.emitAndSettle(600);

    expect(fixture.engine.diagnostics.paperEdgeTemporaryLossCount, 2);
    expect(fixture.engine.diagnostics.paperEdgeLossCount, 1);
    await fixture.dispose();
  });

  test(
    'wrong identity requires consistent observations and recovers',
    () async {
      final wrong = _observation(
        ids: const [20, 21, 22, 23],
        resolvedPageId: null,
        pageResolutionErrorCode: 'SCAN_UNKNOWN_PAGE_MARKERS',
      );
      final fixture = _Fixture(
        config: CameraEngineConfig(
          minimumStableFrames: 1,
          stabilityWindowSize: 1,
          pageMarkerSignatures: [
            PageMarkerSignature(
              pageId: PageId('SH1'),
              markerIds: MarkerIds.defaults,
            ),
          ],
        ),
        analyzer: _FakeAnalyzer(
          observations: [
            wrong,
            wrong,
            wrong,
            _observation(resolvedPageId: PageId('SH1')),
          ],
        ),
      );
      await fixture.initializeAndStart();

      await fixture.emitAndSettle(0);
      expect(
        fixture.engine.state.readiness.status,
        CaptureReadinessStatus.verifyingMarkers,
      );
      expect(
        fixture.engine.state.analysis!.tracking.pageResolutionErrorCode,
        isNull,
      );
      await fixture.emitAndSettle(200);
      expect(
        fixture.engine.state.readiness.status,
        CaptureReadinessStatus.verifyingMarkers,
      );
      await fixture.emitAndSettle(400);
      expect(
        fixture.engine.state.readiness.status,
        CaptureReadinessStatus.unknownSheet,
      );
      expect(
        fixture.engine.state.analysis!.tracking.pageResolutionErrorCode,
        'SCAN_UNKNOWN_PAGE_MARKERS',
      );
      await fixture.emitAndSettle(600);
      expect(fixture.engine.state.readiness.isReady, isTrue);
      expect(
        fixture.engine.state.analysis!.tracking.pageResolutionErrorCode,
        isNull,
      );
      await fixture.dispose();
    },
  );

  test('each accepted frame gets an ArUco opportunity', () async {
    final fixture = _Fixture(
      analyzer: _FakeAnalyzer(
        observations: [
          for (var index = 0; index < 3; index++)
            _observation(resolvedPageId: PageId('SH1')),
        ],
      ),
    );
    await fixture.initializeAndStart();
    await fixture.emitAndSettle(0);
    await fixture.emitAndSettle(200);
    await fixture.emitAndSettle(400);

    expect(fixture.engine.state.readiness.isReady, isTrue);
    expect(fixture.engine.diagnostics.arucoAttemptedFrameCount, 3);
    expect(fixture.engine.diagnostics.arucoAttemptRatio, 1);
    await fixture.dispose();
  });
}

final class _Fixture {
  _Fixture({
    _FakeCameraBackend? backend,
    _FakeAnalyzer? analyzer,
    CameraEngineConfig? config,
  }) : backend = backend ?? _FakeCameraBackend(),
       analyzer = analyzer ?? _FakeAnalyzer() {
    engine = CameraEngine(
      backend: this.backend,
      analyzer: this.analyzer,
      config: config ?? CameraEngineConfig(),
    );
  }

  final _FakeCameraBackend backend;
  final _FakeAnalyzer analyzer;
  late final CameraEngine engine;

  Future<void> initializeAndStart() async {
    expect((await engine.initialize()).isSuccess, isTrue);
    expect((await engine.startAnalysis()).isSuccess, isTrue);
  }

  void emitAt(int milliseconds) {
    final timestamp = DateTime.utc(
      2026,
    ).add(Duration(milliseconds: milliseconds));
    backend.emit(timestamp, () => _frame(milliseconds));
  }

  Future<void> emitAndSettle(int milliseconds) async {
    emitAt(milliseconds);
    await _settle();
  }

  Future<void> dispose() => engine.dispose();
}

final class _FakeCameraBackend implements CameraBackend {
  EngineResult<CameraPreviewInfo> initializeResult = EngineResult.success(
    const CameraPreviewInfo(
      width: 1920,
      height: 1080,
      sensorOrientationDegrees: 90,
      lens: CameraLensPreference.rear,
      automaticFocusEnabled: true,
      automaticExposureEnabled: true,
      requestedPreviewFps: 60,
      torchAvailable: true,
      torchEnabled: true,
    ),
  );
  EngineResult<bool> startResult = EngineResult.success(true);
  EngineResult<bool> stopResult = EngineResult.success(true);
  EngineResult<bool> torchResult = EngineResult.success(true);
  EngineResult<CapturedPageImage> captureResult = EngineResult.success(
    CapturedPageImage(
      encodedBytes: Uint8List.fromList([7, 8, 9]),
      timestamp: DateTime.utc(2026),
      sensorOrientationDegrees: 90,
      deviceOrientation: CameraDeviceOrientation.portraitUp,
      orientationAppliedByBackend: true,
    ),
  );
  CameraFrameCallback? callback;
  int startCalls = 0;
  int stopCalls = 0;
  int captureCalls = 0;
  int materializeCalls = 0;
  bool disposed = false;
  final List<bool> torchValues = [];

  @override
  Future<EngineResult<CameraPreviewInfo>> initialize(
    CameraEngineConfig config,
  ) async => initializeResult;

  @override
  Future<EngineResult<bool>> startAnalysis(CameraFrameCallback onFrame) async {
    startCalls++;
    callback = onFrame;
    return startResult;
  }

  @override
  Future<EngineResult<bool>> stopAnalysis() async {
    stopCalls++;
    callback = null;
    return stopResult;
  }

  @override
  Future<EngineResult<CapturedPageImage>> captureStill() async {
    captureCalls++;
    return captureResult;
  }

  @override
  Future<EngineResult<bool>> setTorchEnabled(bool enabled) async {
    torchValues.add(enabled);
    return torchResult.isFailure ? torchResult : EngineResult.success(enabled);
  }

  void emit(DateTime timestamp, CameraFrameMaterializer materialize) {
    callback?.call(timestamp, () {
      materializeCalls++;
      return materialize();
    });
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    callback = null;
  }
}

final class _FakeAnalyzer implements CameraFrameAnalyzer {
  _FakeAnalyzer({
    CameraFrameObservation? observation,
    List<CameraFrameObservation>? observations,
  }) : observation = observation ?? _observation(),
       observations = observations == null ? null : List.of(observations);

  CameraFrameObservation observation;
  List<CameraFrameObservation>? observations;
  EngineResult<CameraFrameObservation>? result;
  Completer<void>? gate;
  Duration delay = Duration.zero;
  Object? errorToThrow;
  int calls = 0;
  int activeCalls = 0;
  int maximumActiveCalls = 0;
  bool disposed = false;

  @override
  Future<EngineResult<CameraFrameObservation>> analyze(
    CameraAnalysisFrame frame,
    CameraEngineConfig config,
  ) async {
    calls++;
    activeCalls++;
    if (activeCalls > maximumActiveCalls) maximumActiveCalls = activeCalls;
    if (gate != null) await gate!.future;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    activeCalls--;
    final configuredError = errorToThrow;
    errorToThrow = null;
    if (configuredError != null) throw configuredError;
    final configuredResult = result;
    if (configuredResult != null) return configuredResult;
    final queue = observations;
    if (queue != null && queue.isNotEmpty) {
      return EngineResult.success(queue.removeAt(0));
    }
    return EngineResult.success(observation);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  void resetTracking() {}
}

CameraAnalysisFrame _frame(
  int milliseconds, {
  Uint8List? bytes,
  int width = 4,
  int height = 4,
}) => CameraAnalysisFrame(
  lumaBytes: bytes ?? Uint8List(width * height),
  width: width,
  height: height,
  bytesPerRow: width,
  bytesPerPixel: 1,
  timestamp: DateTime.utc(2026).add(Duration(milliseconds: milliseconds)),
  sensorOrientationDegrees: 90,
  deviceOrientation: CameraDeviceOrientation.portraitUp,
);

CameraFrameObservation _observation({
  List<int> ids = const [10, 11, 12, 13],
  List<ImagePoint>? points,
  double area = 0.4,
  double perspective = 1.5,
  double markerSide = 30,
  double brightness = 128,
  double sharpness = 200,
  PageId? resolvedPageId,
  String? pageResolutionErrorCode,
  bool documentDetectionFailed = false,
  String? documentDetectionError,
  DetectedDocument? document,
  bool documentFresh = false,
  DocumentTrackingPhase documentTrackingPhase = DocumentTrackingPhase.searching,
}) => CameraFrameObservation(
  detectedMarkerIds: ids,
  registrationPoints: points ?? _points(),
  pageAreaRatio: area,
  perspectiveRatio: perspective,
  minimumMarkerSidePixels: markerSide,
  brightness: brightness,
  sharpness: sharpness,
  frameSize: ImageSize(width: 1000, height: 1000),
  resolvedPageId: resolvedPageId,
  pageResolutionErrorCode: pageResolutionErrorCode,
  document: document,
  documentFresh: documentFresh,
  documentTrackingPhase: documentTrackingPhase,
  documentDetectionFailed: documentDetectionFailed,
  documentDetectionError: documentDetectionError,
);

List<ImagePoint> _points({double offset = 0}) => [
  ImagePoint(100 + offset, 100),
  ImagePoint(900 + offset, 100),
  ImagePoint(900 + offset, 900),
  ImagePoint(100 + offset, 900),
];

DetectedDocument _testDocument({double perspectiveRatio = 1.5}) =>
    DetectedDocument(
      geometry: DocumentGeometry(
        corners: _points(),
        areaRatio: 0.4,
        centroid: ImagePoint(500, 500),
        perspectiveRatio: perspectiveRatio,
      ),
      confidence: 0.9,
    );

EngineResult<T> _failure<T>(String code, String message) =>
    EngineResult.failure(EngineError(code: code, message: message));

Future<void> _settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 1));
}

Future<(CaptureReadinessStatus, int)> _runStableSequence() async {
  final fixture = _Fixture();
  await fixture.initializeAndStart();
  await fixture.emitAndSettle(0);
  await fixture.emitAndSettle(200);
  await fixture.emitAndSettle(400);
  final result = (
    fixture.engine.state.readiness.status,
    fixture.engine.state.readiness.stableFrameCount,
  );
  await fixture.dispose();
  return result;
}
