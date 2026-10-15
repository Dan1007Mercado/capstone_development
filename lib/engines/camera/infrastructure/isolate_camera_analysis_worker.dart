import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../aruco/domain/image_geometry.dart';
import '../../aruco/infrastructure/opencv_aruco_detector.dart';
import '../domain/camera_backend.dart';
import '../domain/camera_engine_config.dart';
import '../domain/camera_models.dart';
import 'camera_analysis_geometry.dart';

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
    try {
      await _ensureStarted();
      response = ReceivePort();
      _commands!.send({
        'reply': response.sendPort,
        'luma': TransferableTypedData.fromList([frame.lumaBytes]),
        'width': frame.width,
        'height': frame.height,
        'bytesPerRow': frame.bytesPerRow,
        'bytesPerPixel': frame.bytesPerPixel,
        'analysisMaxDimension': config.analysisMaxDimension,
        'markerIds': config.markerIds.values,
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
        ),
      );
    } on Object catch (error) {
      return _failure(
        'CAMERA_ANALYSIS_FAILED',
        'Background camera analysis failed.',
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
  final detector = OpenCvArucoDetector();
  ready.send(commands.sendPort);
  commands.listen((dynamic rawMessage) {
    final message = (rawMessage as Map<Object?, Object?>);
    final reply = message['reply']! as SendPort;
    if (message['dispose'] == true) {
      detector.dispose();
      reply.send(true);
      commands.close();
      return;
    }
    try {
      reply.send(_analyzeInWorker(message, detector));
    } on Object catch (error) {
      reply.send({
        'ok': false,
        'code': 'CAMERA_ANALYSIS_FAILED',
        'message': 'Background camera analysis failed.',
        'cause': error.toString(),
      });
    }
  });
}

Map<Object?, Object?> _analyzeInWorker(
  Map<Object?, Object?> task,
  OpenCvArucoDetector detector,
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
  final arucoStopwatch = Stopwatch()..start();
  final detectionResult = detector.detectGray(
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
  final geometry = calculateCameraMarkerGeometry(
    sourceDetection: sourceDetection,
    markerIds: (task['markerIds']! as List<Object?>).cast<int>(),
  );
  geometryStopwatch.stop();
  workerStopwatch.stop();
  return {
    'ok': true,
    'detectedMarkerIds': geometry.detectedMarkerIds,
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
    'preparationUs': preparationStopwatch.elapsedMicroseconds,
    'sharpnessUs': sharpnessStopwatch.elapsedMicroseconds,
    'arucoUs': arucoStopwatch.elapsedMicroseconds,
    'geometryUs': geometryStopwatch.elapsedMicroseconds,
    'workerUs': workerStopwatch.elapsedMicroseconds,
  };
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
    sharpnessDuration: Duration(microseconds: message['sharpnessUs']! as int),
    arucoDetectionDuration: Duration(microseconds: message['arucoUs']! as int),
    geometryDuration: Duration(microseconds: message['geometryUs']! as int),
    workerDuration: workerDuration,
    totalDuration: roundTripDuration,
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
