import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../../core/errors/engine_error.dart';
import '../../../core/ids/identifiers.dart';
import '../../../core/result/engine_result.dart';
import '../../aruco/domain/page_marker_signature_resolver.dart';
import '../../layout/domain/layout_config.dart';
import '../../aruco/domain/image_geometry.dart';
import '../../aruco/infrastructure/opencv_aruco_detector.dart';
import '../application/frame_stability_tracker.dart';
import '../application/live_frame_gate.dart';
import '../domain/camera_backend.dart';
import '../domain/camera_engine_config.dart';
import '../domain/camera_models.dart';
import '../domain/live_frame_analysis.dart';
import 'camera_analysis_geometry.dart';
import 'opencv_document_detector.dart';

final class IsolateCameraAnalysisWorker implements CameraFrameAnalyzer {
  Isolate? _isolate;
  SendPort? _commands;
  bool _disposed = false;

  @override
  Future<EngineResult<CameraFrameObservation>> analyze(
    CameraAnalysisFrame frame,
    CameraEngineConfig config,
  ) async {
    if (_disposed) {
      return _failure(
        'CAMERA_DISPOSED',
        'The camera analysis worker has been disposed.',
      );
    }
    final roundTripStopwatch = Stopwatch()..start();
    ReceivePort? response;
    var workerReady = false;
    try {
      await _ensureStarted();
      workerReady = true;
      response = ReceivePort();
      _commands!.send({
        'reply': response.sendPort,
        'luma': TransferableTypedData.fromList([frame.lumaBytes]),
        'width': frame.width,
        'height': frame.height,
        'bytesPerRow': frame.bytesPerRow,
        'bytesPerPixel': frame.bytesPerPixel,
        'analysisMaxDimension': config.analysisMaxDimension,
        'documentGateEnabled': config.documentGateEnabled,
        'documentGateMaxDimension': config.documentGateMaxDimension,
        'minimumDocumentAreaRatio': config.minimumDocumentAreaRatio,
        'maximumDocumentPerspectiveRatio':
            config.maximumDocumentPerspectiveRatio,
        'documentStabilityThreshold': config.documentStabilityThreshold,
        'minimumStableFrames': config.minimumStableFrames,
        'arucoProbeEveryNFrames': config.arucoProbeEveryNFrames,
        'minimumBrightness': config.minimumBrightness,
        'maximumBrightness': config.maximumBrightness,
        'minimumSharpness': config.minimumSharpness,
        'documentCannyLowThreshold': config.documentCannyLowThreshold,
        'documentCannyHighThreshold': config.documentCannyHighThreshold,
        'documentPolygonEpsilonRatio': config.documentPolygonEpsilonRatio,
        'markerIds': config.markerIds.values,
        'pageMarkerSignatures': [
          for (final signature in config.pageMarkerSignatures)
            {
              'pageId': signature.pageId.value,
              'ids': signature.markerIds.values,
            },
        ],
      });
      final message = await response.first as Map<Object?, Object?>;
      roundTripStopwatch.stop();
      if (message['ok'] != true) {
        return _failure(
          message['code']! as String,
          message['message']! as String,
          {'cause': message['cause']},
        );
      }
      final points = (message['registrationPoints']! as List<Object?>)
          .cast<List<Object?>>()
          .map((point) => ImagePoint(point[0]! as double, point[1]! as double));
      final documentPoints = (message['documentCorners']! as List<Object?>)
          .cast<List<Object?>>()
          .map((point) => ImagePoint(point[0]! as double, point[1]! as double))
          .toList(growable: false);
      final document = documentPoints.length == 4
          ? DetectedDocument(
              geometry: DocumentGeometry(
                corners: documentPoints,
                areaRatio: message['documentAreaRatio']! as double,
                centroid: ImagePoint(
                  message['documentCentroidX']! as double,
                  message['documentCentroidY']! as double,
                ),
                perspectiveRatio:
                    message['documentPerspectiveRatio']! as double,
              ),
              confidence: message['documentConfidence']! as double,
            )
          : null;
      final gateReason = LiveFrameGateReason.values.byName(
        message['gateReason']! as String,
      );
      return EngineResult.success(
        CameraFrameObservation(
          detectedMarkerIds: (message['detectedMarkerIds']! as List<Object?>)
              .cast<int>(),
          registrationPoints: points,
          pageAreaRatio: message['pageAreaRatio'] as double?,
          perspectiveRatio: message['perspectiveRatio'] as double?,
          minimumMarkerSidePixels:
              message['minimumMarkerSidePixels'] as double?,
          brightness: message['brightness']! as double,
          sharpness: message['sharpness']! as double,
          frameSize: ImageSize(width: frame.width, height: frame.height),
          analysisFrameSize: ImageSize(
            width: message['analysisWidth']! as int,
            height: message['analysisHeight']! as int,
          ),
          analysisScaleX: message['analysisScaleX']! as double,
          analysisScaleY: message['analysisScaleY']! as double,
          timings: _readWorkerTimings(message, roundTripStopwatch.elapsed),
          sensorOrientationDegrees: frame.sensorOrientationDegrees,
          deviceOrientation: frame.deviceOrientation,
          resolvedPageId: message['resolvedPageId'] == null
              ? null
              : PageId(message['resolvedPageId']! as String),
          pageResolutionErrorCode:
              message['pageResolutionErrorCode'] as String?,
          document: document,
          documentQuality: DocumentQuality(
            brightness: message['brightness']! as double,
            sharpness: message['sharpness']! as double,
          ),
          documentStability: DocumentStability(
            isStable: message['documentStable']! as bool,
            stableFrameCount: message['documentStableFrames']! as int,
            motion: message['documentMotion']! as double,
          ),
          gateResult: LiveFrameGateResult(
            reason: gateReason,
            shouldRunAruco: message['arucoRan']! as bool,
            fallbackProbe: message['fallbackProbe']! as bool,
          ),
          arucoRan: message['arucoRan']! as bool,
          documentDetectionFailed: message['documentDetectionFailed']! as bool,
          documentDetectionError: message['documentDetectionError'] as String?,
        ),
      );
    } on Object catch (error) {
      return _failure(
        workerReady
            ? 'CAMERA_FRAME_ANALYSIS_RECOVERABLE'
            : 'CAMERA_ANALYSIS_BACKEND_UNAVAILABLE',
        workerReady
            ? 'One camera analysis frame was malformed and was skipped.'
            : 'The background camera analysis worker could not start.',
        {'cause': error.toString()},
      );
    } finally {
      response?.close();
    }
  }

  Future<void> _ensureStarted() async {
    if (_commands != null) return;
    final ready = ReceivePort();
    _isolate = await Isolate.spawn(_cameraWorkerMain, ready.sendPort);
    _commands = await ready.first as SendPort;
    ready.close();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final commands = _commands;
    if (commands != null) {
      final response = ReceivePort();
      commands.send({'dispose': true, 'reply': response.sendPort});
      await response.first;
      response.close();
    }
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _commands = null;
  }

  EngineResult<CameraFrameObservation> _failure(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );
}

void _cameraWorkerMain(SendPort ready) {
  final commands = ReceivePort();
  final state = _CameraWorkerState();
  ready.send(commands.sendPort);
  commands.listen((dynamic rawMessage) {
    final message = (rawMessage as Map<Object?, Object?>);
    final reply = message['reply']! as SendPort;
    if (message['dispose'] == true) {
      state.dispose();
      reply.send(true);
      commands.close();
      return;
    }
    try {
      reply.send(_analyzeInWorker(message, state));
    } on Object catch (error) {
      reply.send({
        'ok': false,
        'code': 'CAMERA_FRAME_ANALYSIS_RECOVERABLE',
        'message': 'One camera analysis frame failed and was skipped.',
        'cause': error.toString(),
      });
    }
  });
}

Map<Object?, Object?> _analyzeInWorker(
  Map<Object?, Object?> task,
  _CameraWorkerState state,
) {
  final workerStopwatch = Stopwatch()..start();
  final preparationStopwatch = Stopwatch()..start();
  final width = task['width']! as int;
  final height = task['height']! as int;
  final bytesPerRow = task['bytesPerRow']! as int;
  final bytesPerPixel = task['bytesPerPixel']! as int;
  final source = (task['luma']! as TransferableTypedData)
      .materialize()
      .asUint8List();
  final documentGateEnabled = task['documentGateEnabled']! as bool;
  final gatePrepared = prepareCameraAnalysisImage(
    source: source,
    width: width,
    height: height,
    bytesPerRow: bytesPerRow,
    bytesPerPixel: bytesPerPixel,
    maximumDimension: documentGateEnabled
        ? task['documentGateMaxDimension']! as int
        : task['analysisMaxDimension']! as int,
  );
  preparationStopwatch.stop();
  final documentStopwatch = Stopwatch()..start();
  final documentAttempt = documentGateEnabled
      ? detectDocumentBestEffort(
          detector: state.documentDetector,
          pixels: gatePrepared.pixels,
          width: gatePrepared.analysisSize.width,
          height: gatePrepared.analysisSize.height,
          cannyLowThreshold: task['documentCannyLowThreshold']! as double,
          cannyHighThreshold: task['documentCannyHighThreshold']! as double,
          polygonEpsilonRatio: task['documentPolygonEpsilonRatio']! as double,
        )
      : const DocumentDetectionAttempt();
  documentStopwatch.stop();
  final detectedInAnalysis = documentAttempt.document;

  final qualityStopwatch = Stopwatch()..start();
  DocumentQuality quality;
  String? documentDetectionError = documentAttempt.error;
  try {
    quality = _measureDocumentQuality(gatePrepared, detectedInAnalysis);
  } on Object catch (error) {
    // Document-local quality is optional. Whole-frame quality keeps the
    // authoritative ArUco fallback available for this frame.
    quality = _measureDocumentQuality(gatePrepared, null);
    documentDetectionError ??= _shortWorkerDiagnostic(error);
  }
  qualityStopwatch.stop();
  final sharpnessStopwatch = Stopwatch()
    ..start()
    ..stop();

  final stabilityStopwatch = Stopwatch()..start();
  final normalizedDocument = _normalizedDocument(
    detectedInAnalysis,
    gatePrepared.analysisSize,
  );
  final stability = state.stabilityTrackerFor(task).update(normalizedDocument);
  stabilityStopwatch.stop();
  final frameIndex = state.nextFrameIndex();
  final fallbackDue =
      (frameIndex - 1) % (task['arucoProbeEveryNFrames']! as int) == 0;
  final config = _workerConfig(task);
  final gate = const LiveFrameGate().evaluate(
    config: config,
    document: normalizedDocument,
    quality: quality,
    stability: stability,
    fallbackProbeDue: fallbackDue,
  );

  var detectedMarkerIds = <int>[];
  var registrationPoints = <ImagePoint>[];
  double? pageAreaRatio;
  double? perspectiveRatio;
  double? minimumMarkerSidePixels;
  String? resolvedPageId;
  String? pageResolutionErrorCode;
  var arucoPrepared = gatePrepared;
  final arucoStopwatch = Stopwatch();
  final geometryStopwatch = Stopwatch();
  if (gate.shouldRunAruco) {
    if ((task['analysisMaxDimension']! as int) !=
        (documentGateEnabled
            ? task['documentGateMaxDimension']! as int
            : task['analysisMaxDimension']! as int)) {
      preparationStopwatch.start();
      arucoPrepared = prepareCameraAnalysisImage(
        source: source,
        width: width,
        height: height,
        bytesPerRow: bytesPerRow,
        bytesPerPixel: bytesPerPixel,
        maximumDimension: task['analysisMaxDimension']! as int,
      );
      preparationStopwatch.stop();
    }
    arucoStopwatch.start();
    final detectionResult = state.detector.detectGray(
      pixels: arucoPrepared.pixels,
      width: arucoPrepared.analysisSize.width,
      height: arucoPrepared.analysisSize.height,
    );
    arucoStopwatch.stop();
    if (detectionResult.isFailure) {
      return {
        'ok': false,
        'code': detectionResult.error.code,
        'message': detectionResult.error.message,
        'cause': detectionResult.error.details,
      };
    }
    geometryStopwatch.start();
    final sourceDetection = remapArucoDetectionToSource(
      detectionResult.value,
      arucoPrepared.sourceSize,
    );
    final resolver = state.resolverFor(
      (task['pageMarkerSignatures']! as List<Object?>)
          .cast<Map<Object?, Object?>>(),
    );
    EngineResult<ResolvedPageMarkerSignature>? resolution;
    if (resolver != null) {
      resolution = resolver.resolve(
        sourceDetection.markers.map((marker) => marker.id),
      );
    }
    final geometry = calculateCameraMarkerGeometry(
      sourceDetection: sourceDetection,
      markerIds:
          resolution?.valueOrNull?.markerIds.values ??
          (task['markerIds']! as List<Object?>).cast<int>(),
    );
    detectedMarkerIds = geometry.detectedMarkerIds;
    registrationPoints = geometry.registrationPoints;
    pageAreaRatio = geometry.pageAreaRatio;
    perspectiveRatio = geometry.perspectiveRatio;
    minimumMarkerSidePixels = geometry.minimumMarkerSidePixels;
    resolvedPageId = resolution?.valueOrNull?.pageId.value;
    pageResolutionErrorCode = resolution?.errorOrNull?.code;
    geometryStopwatch.stop();
  }
  final sourceDocument = _remapDocument(
    detectedInAnalysis,
    gatePrepared.sourceSize,
    gatePrepared.analysisSize,
  );
  workerStopwatch.stop();
  return {
    'ok': true,
    'detectedMarkerIds': detectedMarkerIds,
    'resolvedPageId': resolvedPageId,
    'pageResolutionErrorCode': pageResolutionErrorCode,
    'registrationPoints': [
      for (final point in registrationPoints) [point.x, point.y],
    ],
    'pageAreaRatio': pageAreaRatio,
    'perspectiveRatio': perspectiveRatio,
    'minimumMarkerSidePixels': minimumMarkerSidePixels,
    'brightness': quality.brightness,
    'sharpness': quality.sharpness,
    'analysisWidth': arucoPrepared.analysisSize.width,
    'analysisHeight': arucoPrepared.analysisSize.height,
    'analysisScaleX': arucoPrepared.analysisScaleX,
    'analysisScaleY': arucoPrepared.analysisScaleY,
    'documentCorners': [
      for (final point
          in sourceDocument?.geometry.corners ?? const <ImagePoint>[])
        [point.x, point.y],
    ],
    'documentAreaRatio': sourceDocument?.geometry.areaRatio,
    'documentPerspectiveRatio': sourceDocument?.geometry.perspectiveRatio,
    'documentCentroidX': sourceDocument?.geometry.centroid.x,
    'documentCentroidY': sourceDocument?.geometry.centroid.y,
    'documentConfidence': sourceDocument?.confidence,
    'documentStable': stability.isStable,
    'documentStableFrames': stability.stableFrameCount,
    'documentMotion': stability.motion,
    'gateReason': gate.reason.name,
    'arucoRan': gate.shouldRunAruco,
    'fallbackProbe': gate.fallbackProbe,
    'documentDetectionFailed': documentDetectionError != null,
    'documentDetectionError': documentDetectionError,
    'preparationUs': preparationStopwatch.elapsedMicroseconds,
    'documentDetectionUs': documentStopwatch.elapsedMicroseconds,
    'qualityEvaluationUs': qualityStopwatch.elapsedMicroseconds,
    'stabilityEvaluationUs': stabilityStopwatch.elapsedMicroseconds,
    'sharpnessUs': sharpnessStopwatch.elapsedMicroseconds,
    'arucoUs': arucoStopwatch.elapsedMicroseconds,
    'geometryUs': geometryStopwatch.elapsedMicroseconds,
    'workerUs': workerStopwatch.elapsedMicroseconds,
  };
}

final class _CameraWorkerState {
  final OpenCvArucoDetector detector = OpenCvArucoDetector();
  final OpenCvDocumentDetector documentDetector =
      const OpenCvDocumentDetector();
  String? _signatureKey;
  PageMarkerSignatureResolver? _resolver;
  FrameStabilityTracker? _stabilityTracker;
  double? _stabilityThreshold;
  int? _minimumStableFrames;
  int _frameIndex = 0;

  int nextFrameIndex() => ++_frameIndex;

  FrameStabilityTracker stabilityTrackerFor(Map<Object?, Object?> task) {
    final threshold = task['documentStabilityThreshold']! as double;
    final frames = task['minimumStableFrames']! as int;
    if (_stabilityTracker == null ||
        _stabilityThreshold != threshold ||
        _minimumStableFrames != frames) {
      _stabilityThreshold = threshold;
      _minimumStableFrames = frames;
      _stabilityTracker = FrameStabilityTracker(
        maximumMotion: threshold,
        minimumStableFrames: frames,
      );
    }
    return _stabilityTracker!;
  }

  PageMarkerSignatureResolver? resolverFor(
    List<Map<Object?, Object?>> signatureData,
  ) {
    if (signatureData.isEmpty) {
      _signatureKey = '';
      _resolver = null;
      return null;
    }
    final key = signatureData
        .map((data) => '${data['pageId']}:${data['ids']}')
        .join('|');
    if (_signatureKey == key) return _resolver;
    _signatureKey = key;
    _resolver = PageMarkerSignatureResolver(
      signatureData.map(
        (data) => PageMarkerSignature(
          pageId: PageId(data['pageId']! as String),
          markerIds: _markerIds((data['ids']! as List<Object?>).cast<int>()),
        ),
      ),
    );
    return _resolver;
  }

  void dispose() {
    detector.dispose();
    _stabilityTracker = null;
    _resolver = null;
    _signatureKey = null;
  }
}

MarkerIds _markerIds(List<int> ids) {
  if (ids.length != 4) throw ArgumentError('Four marker IDs are required.');
  return MarkerIds(
    topLeft: ids[0],
    topRight: ids[1],
    bottomLeft: ids[2],
    bottomRight: ids[3],
  );
}

CameraAnalysisTimings _readWorkerTimings(
  Map<Object?, Object?> message,
  Duration roundTripDuration,
) {
  final workerDuration = Duration(microseconds: message['workerUs']! as int);
  final overheadMicroseconds =
      roundTripDuration.inMicroseconds - workerDuration.inMicroseconds;
  return CameraAnalysisTimings(
    isolateOverheadDuration: Duration(
      microseconds: overheadMicroseconds < 0 ? 0 : overheadMicroseconds,
    ),
    preparationDuration: Duration(
      microseconds: message['preparationUs']! as int,
    ),
    documentDetectionDuration: Duration(
      microseconds: message['documentDetectionUs']! as int,
    ),
    qualityEvaluationDuration: Duration(
      microseconds: message['qualityEvaluationUs']! as int,
    ),
    stabilityEvaluationDuration: Duration(
      microseconds: message['stabilityEvaluationUs']! as int,
    ),
    sharpnessDuration: Duration(microseconds: message['sharpnessUs']! as int),
    arucoDetectionDuration: Duration(microseconds: message['arucoUs']! as int),
    geometryDuration: Duration(microseconds: message['geometryUs']! as int),
    workerDuration: workerDuration,
    totalDuration: roundTripDuration,
  );
}

CameraEngineConfig _workerConfig(Map<Object?, Object?> task) =>
    CameraEngineConfig(
      analysisMaxDimension: task['analysisMaxDimension']! as int,
      documentGateEnabled: task['documentGateEnabled']! as bool,
      documentGateMaxDimension: task['documentGateMaxDimension']! as int,
      minimumDocumentAreaRatio: task['minimumDocumentAreaRatio']! as double,
      maximumDocumentPerspectiveRatio:
          task['maximumDocumentPerspectiveRatio']! as double,
      documentStabilityThreshold: task['documentStabilityThreshold']! as double,
      arucoProbeEveryNFrames: task['arucoProbeEveryNFrames']! as int,
      minimumStableFrames: task['minimumStableFrames']! as int,
      stabilityWindowSize: task['minimumStableFrames']! as int,
      minimumBrightness: task['minimumBrightness']! as double,
      maximumBrightness: task['maximumBrightness']! as double,
      minimumSharpness: task['minimumSharpness']! as double,
      documentCannyLowThreshold: task['documentCannyLowThreshold']! as double,
      documentCannyHighThreshold: task['documentCannyHighThreshold']! as double,
      documentPolygonEpsilonRatio:
          task['documentPolygonEpsilonRatio']! as double,
    );

DocumentQuality _measureDocumentQuality(
  PreparedCameraAnalysisImage image,
  DetectedDocument? document,
) {
  final geometry = document?.geometry;
  if (geometry == null) {
    return DocumentQuality(
      brightness: image.brightness,
      sharpness: _laplacianVariance(
        image.pixels,
        image.analysisSize.width,
        image.analysisSize.height,
      ),
    );
  }
  final xs = geometry.corners.map((point) => point.x);
  final ys = geometry.corners.map((point) => point.y);
  final left = xs
      .reduce((a, b) => a < b ? a : b)
      .floor()
      .clamp(1, image.analysisSize.width - 2);
  final right = xs
      .reduce((a, b) => a > b ? a : b)
      .ceil()
      .clamp(1, image.analysisSize.width - 2);
  final top = ys
      .reduce((a, b) => a < b ? a : b)
      .floor()
      .clamp(1, image.analysisSize.height - 2);
  final bottom = ys
      .reduce((a, b) => a > b ? a : b)
      .ceil()
      .clamp(1, image.analysisSize.height - 2);
  var count = 0;
  var sum = 0.0;
  var laplacianSum = 0.0;
  var laplacianSquaredSum = 0.0;
  final width = image.analysisSize.width;
  for (var y = top; y <= bottom; y += 2) {
    for (var x = left; x <= right; x += 2) {
      if (!_insideConvexQuad(x.toDouble(), y.toDouble(), geometry.corners)) {
        continue;
      }
      final index = y * width + x;
      final laplacian =
          4 * image.pixels[index] -
          image.pixels[index - 1] -
          image.pixels[index + 1] -
          image.pixels[index - width] -
          image.pixels[index + width];
      count++;
      sum += image.pixels[index];
      laplacianSum += laplacian;
      laplacianSquaredSum += laplacian * laplacian;
    }
  }
  if (count < 2) {
    return DocumentQuality(
      brightness: image.brightness,
      sharpness: _laplacianVariance(
        image.pixels,
        image.analysisSize.width,
        image.analysisSize.height,
      ),
    );
  }
  final mean = laplacianSum / count;
  return DocumentQuality(
    brightness: sum / count,
    sharpness: (laplacianSquaredSum - count * mean * mean) / (count - 1),
  );
}

bool _insideConvexQuad(double x, double y, List<ImagePoint> corners) {
  double? sign;
  for (var index = 0; index < 4; index++) {
    final a = corners[index];
    final b = corners[(index + 1) % 4];
    final cross = (b.x - a.x) * (y - a.y) - (b.y - a.y) * (x - a.x);
    if (cross.abs() < 0.000001) continue;
    sign ??= cross.sign;
    if (cross.sign != sign) return false;
  }
  return true;
}

DetectedDocument? _normalizedDocument(
  DetectedDocument? document,
  ImageSize size,
) {
  if (document == null) return null;
  final geometry = document.geometry;
  return DetectedDocument(
    geometry: DocumentGeometry(
      corners: [
        for (final point in geometry.corners)
          ImagePoint(point.x / size.width, point.y / size.height),
      ],
      areaRatio: geometry.areaRatio,
      centroid: ImagePoint(
        geometry.centroid.x / size.width,
        geometry.centroid.y / size.height,
      ),
      perspectiveRatio: geometry.perspectiveRatio,
    ),
    confidence: document.confidence,
  );
}

DetectedDocument? _remapDocument(
  DetectedDocument? document,
  ImageSize sourceSize,
  ImageSize analysisSize,
) {
  if (document == null) return null;
  final scaleX = sourceSize.width / analysisSize.width;
  final scaleY = sourceSize.height / analysisSize.height;
  final geometry = document.geometry;
  return DetectedDocument(
    geometry: DocumentGeometry(
      corners: [
        for (final point in geometry.corners)
          ImagePoint(point.x * scaleX, point.y * scaleY),
      ],
      areaRatio: geometry.areaRatio,
      centroid: ImagePoint(
        geometry.centroid.x * scaleX,
        geometry.centroid.y * scaleY,
      ),
      perspectiveRatio: geometry.perspectiveRatio,
    ),
    confidence: document.confidence,
  );
}

double _laplacianVariance(Uint8List pixels, int width, int height) {
  if (width < 3 || height < 3) return 0;
  var count = 0;
  var mean = 0.0;
  var squaredDifferenceSum = 0.0;
  for (var y = 1; y < height - 1; y += 2) {
    for (var x = 1; x < width - 1; x += 2) {
      final index = y * width + x;
      final laplacian =
          4 * pixels[index] -
          pixels[index - 1] -
          pixels[index + 1] -
          pixels[index - width] -
          pixels[index + width];
      count++;
      final delta = laplacian - mean;
      mean += delta / count;
      squaredDifferenceSum += delta * (laplacian - mean);
    }
  }
  return count > 1 ? squaredDifferenceSum / (count - 1) : 0;
}

String _shortWorkerDiagnostic(Object error) {
  final normalized = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  const maximumLength = 180;
  return normalized.length <= maximumLength
      ? normalized
      : '${normalized.substring(0, maximumLength - 1)}…';
}
