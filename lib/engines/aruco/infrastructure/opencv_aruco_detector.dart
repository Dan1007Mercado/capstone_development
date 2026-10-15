import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../domain/detected_marker.dart';
import '../domain/image_geometry.dart';

/// Shared DICT_4X4_50 detection boundary for encoded-image and camera paths.
final class OpenCvArucoDetector {
  cv.ArucoDictionary? _dictionary;
  cv.ArucoDetectorParameters? _parameters;
  cv.ArucoDetector? _detector;
  bool _disposed = false;

  EngineResult<ArucoDetection> detectGray({
    required Uint8List pixels,
    required int width,
    required int height,
  }) {
    if (width <= 0 || height <= 0 || pixels.length != width * height) {
      return _failure(
        'ARUCO_IMAGE_INVALID',
        'Grayscale pixels must exactly match the supplied dimensions.',
        {'width': width, 'height': height, 'byteLength': pixels.length},
      );
    }

    cv.Mat? gray;
    try {
      gray = cv.Mat.fromList(height, width, cv.MatType.CV_8UC1, pixels);
      return detectMat(gray);
    } on Object catch (error) {
      return _detectionFailure(error);
    } finally {
      gray?.dispose();
    }
  }

  EngineResult<ArucoDetection> detectMat(cv.Mat image) {
    cv.VecVecPoint2f? corners;
    cv.VecI32? ids;
    cv.VecVecPoint2f? rejected;
    try {
      if (_disposed) {
        return _failure(
          'ARUCO_BACKEND_UNAVAILABLE',
          'The OpenCV ArUco detector has already been disposed.',
        );
      }
      _ensureInitialized();
      final detection = _detector!.detectMarkers(image);
      corners = detection.$1;
      ids = detection.$2;
      rejected = detection.$3;
      if (corners.length != ids.length) {
        return _failure(
          'ARUCO_DETECTION_FAILED',
          'OpenCV returned inconsistent marker IDs and corners.',
        );
      }

      final idValues = ids.toList();
      final markers = <DetectedMarker>[];
      for (var index = 0; index < idValues.length; index++) {
        final points = corners[index];
        if (points.length != 4) {
          return _failure(
            'ARUCO_DETECTION_FAILED',
            'OpenCV returned a marker without four corners.',
            {'markerId': idValues[index]},
          );
        }
        markers.add(
          DetectedMarker(
            id: idValues[index],
            topLeft: ImagePoint(points[0].x, points[0].y),
            topRight: ImagePoint(points[1].x, points[1].y),
            bottomRight: ImagePoint(points[2].x, points[2].y),
            bottomLeft: ImagePoint(points[3].x, points[3].y),
          ),
        );
      }
      return EngineResult.success(
        ArucoDetection(
          sourceSize: ImageSize(width: image.width, height: image.height),
          markers: markers,
        ),
      );
    } on Object catch (error) {
      return _detectionFailure(error);
    } finally {
      rejected?.dispose();
      ids?.dispose();
      corners?.dispose();
    }
  }

  void _ensureInitialized() {
    if (_detector != null) return;
    cv.ArucoDictionary? dictionary;
    cv.ArucoDetectorParameters? parameters;
    try {
      dictionary = cv.ArucoDictionary.predefined(
        cv.PredefinedDictionaryType.DICT_4X4_50,
      );
      parameters = cv.ArucoDetectorParameters.empty();
      final detector = cv.ArucoDetector.create(dictionary, parameters);
      _dictionary = dictionary;
      _parameters = parameters;
      _detector = detector;
    } catch (_) {
      parameters?.dispose();
      dictionary?.dispose();
      rethrow;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _detector?.dispose();
    _parameters?.dispose();
    _dictionary?.dispose();
    _detector = null;
    _parameters = null;
    _dictionary = null;
  }

  EngineResult<ArucoDetection> _detectionFailure(Object error) => _failure(
    isBackendUnavailable(error)
        ? 'ARUCO_BACKEND_UNAVAILABLE'
        : 'ARUCO_DETECTION_FAILED',
    isBackendUnavailable(error)
        ? 'OpenCV ArUco native symbols are unavailable.'
        : 'OpenCV could not detect markers in the source image.',
    {'cause': error.toString()},
  );

  static bool isBackendUnavailable(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('symbol') ||
        text.contains('dynamic library') ||
        text.contains('failed to load');
  }

  EngineResult<ArucoDetection> _failure(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );
}
