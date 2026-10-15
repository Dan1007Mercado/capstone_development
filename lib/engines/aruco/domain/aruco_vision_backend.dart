import 'dart:typed_data';

import '../../../core/result/engine_result.dart';
import 'aruco_alignment_config.dart';
import 'detected_marker.dart';
import 'image_geometry.dart';
import 'page_alignment_result.dart';

abstract interface class ArucoVisionBackend {
  EngineResult<ArucoImageSession> open(
    Uint8List encodedImage,
    ArucoAlignmentConfig config,
  );
}

/// Owns a decoded native image until [dispose] is called.
abstract interface class ArucoImageSession {
  ArucoDetection get detection;
  ImageSize get sourceSize;
  ArucoBackendOpenTimings get openTimings;

  EngineResult<BackendRectification> rectify({
    required List<ImagePoint> sourcePoints,
    required List<ImagePoint> destinationPoints,
    required ImageSize outputSize,
  });

  void dispose();
}

final class BackendRectification {
  const BackendRectification({
    required this.canonicalPage,
    required this.homography,
    this.timings = const ArucoBackendRectificationTimings(),
  });

  final CanonicalPageImage canonicalPage;
  final HomographyMatrix homography;
  final ArucoBackendRectificationTimings timings;
}

final class ArucoBackendOpenTimings {
  const ArucoBackendOpenTimings({
    this.decode = Duration.zero,
    this.detection = Duration.zero,
  });

  final Duration decode;
  final Duration detection;
}

final class ArucoBackendRectificationTimings {
  const ArucoBackendRectificationTimings({
    this.homography = Duration.zero,
    this.warp = Duration.zero,
  });

  final Duration homography;
  final Duration warp;
}
