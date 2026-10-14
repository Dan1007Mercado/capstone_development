import 'dart:typed_data';

import 'package:image/image.dart' as image_codec;
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../core/errors/engine_error.dart';
import '../../../core/protocol/aruco_dictionary.dart';
import '../../../core/result/engine_result.dart';
import '../domain/aruco_alignment_config.dart';
import '../domain/aruco_vision_backend.dart';
import '../domain/detected_marker.dart';
import '../domain/image_geometry.dart';
import '../domain/page_alignment_result.dart';

/// Native OpenCV backend. Returned sessions own one decoded Mat until disposed.
final class OpenCvArucoVisionBackend implements ArucoVisionBackend {
  const OpenCvArucoVisionBackend();

  @override
  EngineResult<ArucoImageSession> open(
    Uint8List encodedImage,
    ArucoAlignmentConfig config,
  ) {
    if (config.dictionary != ArucoDictionary.openCv4x4_50) {
      return _failure(
        'ARUCO_BACKEND_UNAVAILABLE',
        'The OpenCV backend supports only DICT_4X4_50.',
      );
    }

    cv.Mat? image;
    cv.ArucoDictionary? dictionary;
    cv.ArucoDetectorParameters? parameters;
    cv.ArucoDetector? detector;
    cv.VecVecPoint2f? corners;
    cv.VecI32? ids;
    cv.VecVecPoint2f? rejected;
    var transferImageOwnership = false;
    try {
      final decoded = image_codec.decodeImage(encodedImage);
      if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
        return _failure(
          'ARUCO_IMAGE_INVALID',
          'Source bytes are not a decodable static image.',
        );
      }
      final decodedMat = cv.Mat.fromList(
        decoded.height,
        decoded.width,
        cv.MatType.CV_8UC3,
        decoded.getBytes(order: image_codec.ChannelOrder.bgr),
      );
      image = decodedMat;

      dictionary = cv.ArucoDictionary.predefined(
        cv.PredefinedDictionaryType.DICT_4X4_50,
      );
      parameters = cv.ArucoDetectorParameters.empty();
      detector = cv.ArucoDetector.create(dictionary, parameters);
      final detection = detector.detectMarkers(decodedMat);
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

      final session = _OpenCvArucoImageSession(
        image: image,
        detection: ArucoDetection(
          sourceSize: ImageSize(
            width: decodedMat.width,
            height: decodedMat.height,
          ),
          markers: markers,
        ),
      );
      transferImageOwnership = true;
      return EngineResult.success(session);
    } on Object catch (error) {
      return _failure(
        _isBackendUnavailable(error)
            ? 'ARUCO_BACKEND_UNAVAILABLE'
            : 'ARUCO_DETECTION_FAILED',
        _isBackendUnavailable(error)
            ? 'OpenCV ArUco native symbols are unavailable.'
            : 'OpenCV could not detect markers in the source image.',
        {'cause': error.toString()},
      );
    } finally {
      rejected?.dispose();
      ids?.dispose();
      corners?.dispose();
      detector?.dispose();
      parameters?.dispose();
      dictionary?.dispose();
      if (!transferImageOwnership) image?.dispose();
    }
  }

  static bool _isBackendUnavailable(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('symbol') ||
        text.contains('dynamic library') ||
        text.contains('failed to load');
  }

  EngineResult<ArucoImageSession> _failure(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );
}

final class _OpenCvArucoImageSession implements ArucoImageSession {
  _OpenCvArucoImageSession({required cv.Mat image, required this.detection})
    : _image = image;

  cv.Mat? _image;

  @override
  final ArucoDetection detection;

  @override
  EngineResult<BackendRectification> rectify({
    required List<ImagePoint> sourcePoints,
    required List<ImagePoint> destinationPoints,
    required ImageSize outputSize,
  }) {
    if (_image == null) {
      return _failure(
        'ARUCO_BACKEND_UNAVAILABLE',
        'The OpenCV image session has already been disposed.',
      );
    }
    if (sourcePoints.length != 4 || destinationPoints.length != 4) {
      return _failure(
        'ARUCO_HOMOGRAPHY_FAILED',
        'Exactly four point correspondences are required.',
      );
    }

    cv.VecPoint2f? sourceVector;
    cv.VecPoint2f? destinationVector;
    cv.Mat? homography;
    cv.Mat? warped;
    cv.Scalar? border;
    try {
      sourceVector = cv.VecPoint2f.generate(
        sourcePoints.length,
        (index) => cv.Point2f(sourcePoints[index].x, sourcePoints[index].y),
      );
      destinationVector = cv.VecPoint2f.generate(
        destinationPoints.length,
        (index) =>
            cv.Point2f(destinationPoints[index].x, destinationPoints[index].y),
      );
      homography = cv.getPerspectiveTransform2f(
        sourceVector,
        destinationVector,
      );
      final matrixValues = homography
          .toList()
          .expand((row) => row)
          .map((value) => value.toDouble())
          .toList(growable: false);
      final matrix = HomographyMatrix(matrixValues);
      border = cv.Scalar.all(255);
      warped = cv.warpPerspective(_image!, homography, (
        outputSize.width,
        outputSize.height,
      ), borderValue: border);
      if (warped.isEmpty ||
          warped.width != outputSize.width ||
          warped.height != outputSize.height) {
        return _failure(
          'ARUCO_HOMOGRAPHY_FAILED',
          'OpenCV did not produce the requested canonical dimensions.',
        );
      }
      final (encoded, pngBytes) = cv.imencode('.png', warped);
      if (!encoded || pngBytes.isEmpty) {
        return _failure(
          'ARUCO_HOMOGRAPHY_FAILED',
          'OpenCV could not encode the canonical page.',
        );
      }
      return EngineResult.success(
        BackendRectification(
          canonicalPage: CanonicalPageImage(
            size: outputSize,
            pngBytes: pngBytes,
          ),
          homography: matrix,
        ),
      );
    } on Object catch (error) {
      return _failure(
        'ARUCO_HOMOGRAPHY_FAILED',
        'OpenCV could not compute or apply the page homography.',
        {'cause': error.toString()},
      );
    } finally {
      warped?.dispose();
      border?.dispose();
      homography?.dispose();
      destinationVector?.dispose();
      sourceVector?.dispose();
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    _image = null;
  }

  EngineResult<BackendRectification> _failure(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );
}
