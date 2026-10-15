import 'dart:typed_data';
import 'dart:math' as math;

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
  OpenCvArucoVisionBackend({OpenCvArucoDetector? detector})
    : _detector = detector ?? OpenCvArucoDetector();

  final OpenCvArucoDetector _detector;
  bool _disposed = false;

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

    if (_disposed) {
      return _failure(
        'ARUCO_BACKEND_UNAVAILABLE',
        'The OpenCV ArUco backend has already been disposed.',
      );
    }
    cv.Mat? image;
    cv.Mat? detectionImage;
    var transferImageOwnership = false;
    try {
      final decodeStopwatch = Stopwatch()..start();
      final decodedMat = cv.imdecode(encodedImage, cv.IMREAD_GRAYSCALE);
      decodeStopwatch.stop();
      if (decodedMat.isEmpty ||
          decodedMat.width <= 0 ||
          decodedMat.height <= 0) {
        decodedMat.dispose();
        return _failure(
          'ARUCO_IMAGE_INVALID',
          'Source bytes are not a decodable static image.',
        );
      }
      image = decodedMat;

      final preparationStopwatch = Stopwatch()..start();
      final detectionSize = finalDetectionSize(
        ImageSize(width: decodedMat.width, height: decodedMat.height),
        config.finalMarkerDetectionMaxDimension,
      );
      if (detectionSize.width == decodedMat.width &&
          detectionSize.height == decodedMat.height) {
        detectionImage = decodedMat;
      } else {
        detectionImage = cv.resize(decodedMat, (
          detectionSize.width,
          detectionSize.height,
        ), interpolation: cv.INTER_AREA);
      }
      preparationStopwatch.stop();
      final detectionStopwatch = Stopwatch()..start();
      final detection = _detector.detectMat(detectionImage);
      detectionStopwatch.stop();
      if (detection.isFailure) {
        return EngineResult.failure(detection.error);
      }

      final remapStopwatch = Stopwatch()..start();
      final remappedDetection = remapDetectionToSource(
        detection.value,
        ImageSize(width: decodedMat.width, height: decodedMat.height),
      );
      remapStopwatch.stop();

      final session = _OpenCvArucoImageSession(
        image: image,
        detection: remappedDetection,
        openTimings: ArucoBackendOpenTimings(
          decode: decodeStopwatch.elapsed,
          detectionPreparation: preparationStopwatch.elapsed,
          detection: detectionStopwatch.elapsed,
          coordinateRemap: remapStopwatch.elapsed,
          detectionSize: detectionSize,
          detectionScaleX: decodedMat.width / detectionSize.width,
          detectionScaleY: decodedMat.height / detectionSize.height,
        ),
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
      if (!identical(detectionImage, image)) detectionImage?.dispose();
      if (!transferImageOwnership) image?.dispose();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _detector.dispose();
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
  _OpenCvArucoImageSession({
    required cv.Mat image,
    required this.detection,
    required this.openTimings,
  }) : _image = image;

  cv.Mat? _image;

  @override
  final ArucoDetection detection;

  @override
  final ArucoBackendOpenTimings openTimings;

  @override
  ImageSize get sourceSize =>
      ImageSize(width: _image?.width ?? 0, height: _image?.height ?? 0);

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
      final homographyStopwatch = Stopwatch()..start();
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
      homographyStopwatch.stop();
      final warpStopwatch = Stopwatch()..start();
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
      final grayscaleBytes = Uint8List.fromList(warped.data);
      warpStopwatch.stop();
      return EngineResult.success(
        BackendRectification(
          canonicalPage: CanonicalPageImage.ownedGrayscale(
            size: outputSize,
            grayscaleBytes: grayscaleBytes,
          ),
          homography: matrix,
          timings: ArucoBackendRectificationTimings(
            homography: homographyStopwatch.elapsed,
            warp: warpStopwatch.elapsed,
          ),
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

ImageSize finalDetectionSize(ImageSize source, int? maximumDimension) {
  if (maximumDimension == null ||
      math.max(source.width, source.height) <= maximumDimension) {
    return source;
  }
  final scale = maximumDimension / math.max(source.width, source.height);
  return ImageSize(
    width: math.max(1, (source.width * scale).round()),
    height: math.max(1, (source.height * scale).round()),
  );
}

ArucoDetection remapDetectionToSource(
  ArucoDetection detection,
  ImageSize sourceSize,
) {
  if (detection.sourceSize == sourceSize) return detection;
  final scaleX = sourceSize.width / detection.sourceSize.width;
  final scaleY = sourceSize.height / detection.sourceSize.height;
  ImagePoint point(ImagePoint value) =>
      ImagePoint(value.x * scaleX, value.y * scaleY);
  return ArucoDetection(
    sourceSize: sourceSize,
    markers: detection.markers.map(
      (marker) => DetectedMarker(
        id: marker.id,
        topLeft: point(marker.corner(MarkerCorner.topLeft)),
        topRight: point(marker.corner(MarkerCorner.topRight)),
        bottomRight: point(marker.corner(MarkerCorner.bottomRight)),
        bottomLeft: point(marker.corner(MarkerCorner.bottomLeft)),
      ),
    ),
  );
}
