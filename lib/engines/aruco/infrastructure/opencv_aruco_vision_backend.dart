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
import 'opencv_aruco_detector.dart';

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
    OpenCvArucoDetector? detector;
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

      detector = OpenCvArucoDetector();
      final detection = detector.detectMat(decodedMat);
      if (detection.isFailure) {
        return EngineResult.failure(detection.error);
      }

      final session = _OpenCvArucoImageSession(
        image: image,
        detection: detection.value,
      );
      transferImageOwnership = true;
      return EngineResult.success(session);
    } on Object catch (error) {
      return _failure(
        OpenCvArucoDetector.isBackendUnavailable(error)
            ? 'ARUCO_BACKEND_UNAVAILABLE'
            : 'ARUCO_DETECTION_FAILED',
        OpenCvArucoDetector.isBackendUnavailable(error)
            ? 'OpenCV ArUco native symbols are unavailable.'
            : 'OpenCV could not detect markers in the source image.',
        {'cause': error.toString()},
      );
    } finally {
      detector?.dispose();
      if (!transferImageOwnership) image?.dispose();
    }
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
