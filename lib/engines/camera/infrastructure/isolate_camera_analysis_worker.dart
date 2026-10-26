import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../../core/errors/engine_error.dart';
import '../../../core/ids/identifiers.dart';
import '../../../core/result/engine_result.dart';
import '../../aruco/domain/image_geometry.dart';
import '../../aruco/domain/page_marker_signature_resolver.dart';
import '../../aruco/infrastructure/opencv_aruco_detector.dart';
import '../../layout/domain/layout_config.dart';
import '../application/document_tracker.dart';
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
        'paperEdgeVisualizationEnabled': config.paperEdgeVisualizationEnabled,
        'paperEdgeMaxDimension': config.paperEdgeMaxDimension,
        'paperEdgeDetectionIntervalFrames':
            config.paperEdgeDetectionIntervalFrames,
        'paperEdgeCannyLowThreshold': config.paperEdgeCannyLowThreshold,
        'paperEdgeCannyHighThreshold': config.paperEdgeCannyHighThreshold,
        'paperEdgePolygonEpsilonRatio': config.paperEdgePolygonEpsilonRatio,
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
          documentFresh: message['documentFresh']! as bool,
          documentTrackingPhase: DocumentTrackingPhase.values.byName(
            message['documentTrackingPhase']! as String,
          ),
          documentTemporaryMissCount:
              message['documentTemporaryMissCount']! as int,
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
  void resetTracking() {
    _commands?.send({'resetTracking': true});
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
    final message = rawMessage as Map<Object?, Object?>;
    if (message['resetTracking'] == true) {
      state.resetTracking();
      return;
    }
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
  final prepared = prepareCameraAnalysisImage(
    source: source,
    width: width,
    height: height,
    bytesPerRow: bytesPerRow,
    bytesPerPixel: bytesPerPixel,
    maximumDimension: task['analysisMaxDimension']! as int,
  );
  preparationStopwatch.stop();

  final sharpnessStopwatch = Stopwatch()..start();
  final sharpness = _laplacianVariance(
    prepared.pixels,
    prepared.analysisSize.width,
    prepared.analysisSize.height,
  );
  sharpnessStopwatch.stop();

  // ArUco is authoritative and gets an opportunity on every accepted frame.
  // Optional paper-edge work happens only after this complete marker pass.
  final arucoStopwatch = Stopwatch()..start();
  final detectionResult = state.detector.detectGray(
    pixels: prepared.pixels,
    width: prepared.analysisSize.width,
    height: prepared.analysisSize.height,
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

  final geometryStopwatch = Stopwatch()..start();
  final sourceDetection = remapArucoDetectionToSource(
    detectionResult.value,
    prepared.sourceSize,
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
  geometryStopwatch.stop();

  final documentStopwatch = Stopwatch();
  final trackingStopwatch = Stopwatch();
  String? documentDetectionError;
  DocumentTrackingUpdate tracking;
  final frameIndex = state.nextFrameIndex();
  final visualizationEnabled = task['paperEdgeVisualizationEnabled']! as bool;
  final detectionDue =
      visualizationEnabled &&
      (frameIndex - 1) % (task['paperEdgeDetectionIntervalFrames']! as int) ==
          0;
  if (detectionDue) {
    var paperPrepared = prepared;
    final paperMaxDimension = task['paperEdgeMaxDimension']! as int;
    if (paperMaxDimension != task['analysisMaxDimension']! as int) {
      preparationStopwatch.start();
      paperPrepared = prepareCameraAnalysisImage(
        source: source,
        width: width,
        height: height,
        bytesPerRow: bytesPerRow,
        bytesPerPixel: bytesPerPixel,
        maximumDimension: paperMaxDimension,
      );
      preparationStopwatch.stop();
    }
    documentStopwatch.start();
    final attempt = detectDocumentBestEffort(
      detector: state.documentDetector,
      pixels: paperPrepared.pixels,
      width: paperPrepared.analysisSize.width,
      height: paperPrepared.analysisSize.height,
      cannyLowThreshold: task['paperEdgeCannyLowThreshold']! as double,
      cannyHighThreshold: task['paperEdgeCannyHighThreshold']! as double,
      polygonEpsilonRatio: task['paperEdgePolygonEpsilonRatio']! as double,
    );
    documentStopwatch.stop();
    documentDetectionError = attempt.error;
    trackingStopwatch.start();
    tracking = state.documentTracker.update(
      _remapDocument(
        attempt.document,
        paperPrepared.sourceSize,
        paperPrepared.analysisSize,
      ),
    );
    trackingStopwatch.stop();
  } else if (visualizationEnabled) {
    tracking = state.documentTracker.retain();
  } else {
    state.documentTracker.reset();
    tracking = const DocumentTrackingUpdate.searching();
  }

  workerStopwatch.stop();
  return {
    'ok': true,
    'detectedMarkerIds': geometry.detectedMarkerIds,
    'resolvedPageId': resolution?.valueOrNull?.pageId.value,
    'pageResolutionErrorCode': resolution?.errorOrNull?.code,
    'registrationPoints': [
      for (final point in geometry.registrationPoints) [point.x, point.y],
    ],
    'pageAreaRatio': geometry.pageAreaRatio,
    'perspectiveRatio': geometry.perspectiveRatio,
    'minimumMarkerSidePixels': geometry.minimumMarkerSidePixels,
    'brightness': prepared.brightness,
    'sharpness': sharpness,
    'analysisWidth': prepared.analysisSize.width,
    'analysisHeight': prepared.analysisSize.height,
    'analysisScaleX': prepared.analysisScaleX,
    'analysisScaleY': prepared.analysisScaleY,
    'documentCorners': [
      for (final point
          in tracking.document?.geometry.corners ?? const <ImagePoint>[])
        [point.x, point.y],
    ],
    'documentAreaRatio': tracking.document?.geometry.areaRatio,
    'documentPerspectiveRatio': tracking.document?.geometry.perspectiveRatio,
    'documentCentroidX': tracking.document?.geometry.centroid.x,
    'documentCentroidY': tracking.document?.geometry.centroid.y,
    'documentConfidence': tracking.document?.confidence,
    'documentFresh': tracking.isFresh,
    'documentTrackingPhase': tracking.phase.name,
    'documentTemporaryMissCount': tracking.temporaryMissCount,
    'documentDetectionFailed': documentDetectionError != null,
    'documentDetectionError': documentDetectionError,
    'preparationUs': preparationStopwatch.elapsedMicroseconds,
    'paperEdgeDetectionUs': documentStopwatch.elapsedMicroseconds,
    'paperEdgeTrackingUs': trackingStopwatch.elapsedMicroseconds,
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
  final DocumentTracker documentTracker = DocumentTracker();
  String? _signatureKey;
  PageMarkerSignatureResolver? _resolver;
  int _frameIndex = 0;

  int nextFrameIndex() => ++_frameIndex;

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
    documentTracker.reset();
    _resolver = null;
    _signatureKey = null;
  }

  void resetTracking() {
    documentTracker.reset();
    _frameIndex = 0;
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
    paperEdgeDetectionDuration: Duration(
      microseconds: message['paperEdgeDetectionUs']! as int,
    ),
    paperEdgeTrackingDuration: Duration(
      microseconds: message['paperEdgeTrackingUs']! as int,
    ),
    sharpnessDuration: Duration(microseconds: message['sharpnessUs']! as int),
    arucoDetectionDuration: Duration(microseconds: message['arucoUs']! as int),
    geometryDuration: Duration(microseconds: message['geometryUs']! as int),
    workerDuration: workerDuration,
    totalDuration: roundTripDuration,
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
