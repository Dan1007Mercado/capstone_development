import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../aruco/application/marker_correspondence_service.dart';
import '../../aruco/domain/aruco_alignment_config.dart';
import '../../aruco/domain/detected_marker.dart';
import '../../aruco/domain/image_geometry.dart';
import '../../aruco/infrastructure/opencv_aruco_vision_backend.dart';
import '../../layout/domain/layout_regions.dart';
import '../domain/camera_backend.dart';
import '../domain/camera_engine_config.dart';
import '../domain/camera_models.dart';

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
    try {
      await _ensureStarted();
      final response = ReceivePort();
      _commands!.send({
        'reply': response.sendPort,
        'luma': TransferableTypedData.fromList([frame.lumaBytes]),
        'width': frame.width,
        'height': frame.height,
        'bytesPerRow': frame.bytesPerRow,
        'bytesPerPixel': frame.bytesPerPixel,
        'markerIds': config.markerIds.values,
        'minimumMarkerSidePixels': config.minimumMarkerSidePixels,
        'minimumPageAreaRatio': config.minimumPageAreaRatio,
        'maximumPerspectiveRatio': config.maximumPerspectiveRatio,
      });
      final message = await response.first as Map<Object?, Object?>;
      response.close();
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
        ),
      );
    } on Object catch (error) {
      return _failure(
        'CAMERA_ANALYSIS_FAILED',
        'Background camera analysis failed.',
        {'cause': error.toString()},
      );
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
  ready.send(commands.sendPort);
  commands.listen((dynamic rawMessage) {
    final message = (rawMessage as Map<Object?, Object?>);
    final reply = message['reply']! as SendPort;
    if (message['dispose'] == true) {
      reply.send(true);
      commands.close();
      return;
    }
    try {
      reply.send(_analyzeInWorker(message));
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

Map<Object?, Object?> _analyzeInWorker(Map<Object?, Object?> task) {
  final width = task['width']! as int;
  final height = task['height']! as int;
  final bytesPerRow = task['bytesPerRow']! as int;
  final bytesPerPixel = task['bytesPerPixel']! as int;
  final source = (task['luma']! as TransferableTypedData)
      .materialize()
      .asUint8List();
  final compact = Uint8List(width * height);
  var sum = 0.0;
  for (var y = 0; y < height; y++) {
    final sourceRow = y * bytesPerRow;
    final destinationRow = y * width;
    for (var x = 0; x < width; x++) {
      final value = source[sourceRow + x * bytesPerPixel];
      compact[destinationRow + x] = value;
      sum += value;
    }
  }
  final brightness = sum / compact.length;
  final sharpness = _laplacianVariance(compact, width, height);
  final grayscale = image.Image.fromBytes(
    width: width,
    height: height,
    bytes: compact.buffer,
    numChannels: 1,
  );
  final pngBytes = Uint8List.fromList(image.encodePng(grayscale));
  final backendResult = const OpenCvArucoVisionBackend().open(
    pngBytes,
    ArucoAlignmentConfig(
      minimumMarkerSidePixels: task['minimumMarkerSidePixels']! as double,
      minimumRegistrationAreaRatio: task['minimumPageAreaRatio']! as double,
      maximumExtremePerspectiveRatio:
          task['maximumPerspectiveRatio']! as double,
    ),
  );
  if (backendResult.isFailure) {
    return {
      'ok': false,
      'code': backendResult.error.code,
      'message': backendResult.error.message,
      'cause': backendResult.error.details,
    };
  }

  final session = backendResult.value;
  try {
    final markers = session.detection.markers;
    final detectedIds = markers.map((marker) => marker.id).toList()..sort();
    final markerIds = (task['markerIds']! as List<Object?>).cast<int>();
    final rolesById = <int, MarkerRole>{
      markerIds[0]: MarkerRole.topLeft,
      markerIds[1]: MarkerRole.topRight,
      markerIds[2]: MarkerRole.bottomLeft,
      markerIds[3]: MarkerRole.bottomRight,
    };
    final detectedById = <int, List<DetectedMarker>>{};
    for (final marker in markers) {
      detectedById.putIfAbsent(marker.id, () => []).add(marker);
    }
    const roleOrder = [
      MarkerRole.topLeft,
      MarkerRole.topRight,
      MarkerRole.bottomRight,
      MarkerRole.bottomLeft,
    ];
    final idByRole = {
      for (final entry in rolesById.entries) entry.value: entry.key,
    };
    final requiredMarkers = <DetectedMarker>[];
    final registrationPoints = <ImagePoint>[];
    for (final role in roleOrder) {
      final matches = detectedById[idByRole[role]];
      if (matches == null || matches.length != 1) {
        requiredMarkers.clear();
        registrationPoints.clear();
        break;
      }
      final marker = matches.single;
      requiredMarkers.add(marker);
      registrationPoints.add(
        marker.corner(DetectedRegistrationCorner.forRole(role)),
      );
    }

    double? areaRatio;
    double? perspectiveRatio;
    double? minimumMarkerSide;
    if (registrationPoints.length == 4) {
      areaRatio = _polygonArea(registrationPoints).abs() / (width * height);
      final spans = <double>[
        for (var index = 0; index < 4; index++)
          registrationPoints[index].distanceTo(
            registrationPoints[(index + 1) % 4],
          ),
        registrationPoints[0].distanceTo(registrationPoints[2]),
        registrationPoints[1].distanceTo(registrationPoints[3]),
      ];
      perspectiveRatio = spans.reduce(math.max) / spans.reduce(math.min);
      minimumMarkerSide = requiredMarkers
          .map((marker) => marker.minimumSideLength)
          .reduce(math.min);
    }
    return {
      'ok': true,
      'detectedMarkerIds': detectedIds,
      'registrationPoints': [
        for (final point in registrationPoints) [point.x, point.y],
      ],
      'pageAreaRatio': areaRatio,
      'perspectiveRatio': perspectiveRatio,
      'minimumMarkerSidePixels': minimumMarkerSide,
      'brightness': brightness,
      'sharpness': sharpness,
    };
  } finally {
    session.dispose();
  }
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

double _polygonArea(List<ImagePoint> points) {
  var twiceArea = 0.0;
  for (var index = 0; index < points.length; index++) {
    final current = points[index];
    final next = points[(index + 1) % points.length];
    twiceArea += current.x * next.y - next.x * current.y;
  }
  return twiceArea / 2;
}
