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

  EngineResult<BackendHomographyEstimate> estimateHomography({
    required List<ImagePoint> sourcePoints,
    required List<ImagePoint> destinationPoints,
    required HomographyEstimationMethod method,
    required double ransacReprojectionThresholdPixels,
    required int maximumIterations,
    required double confidence,
  });

  EngineResult<BackendWarp> warp({
    required HomographyMatrix homography,
    required ImageSize outputSize,
  });

  void dispose();
}

enum HomographyEstimationMethod { fourPoint, multiPointRansac }

final class BackendHomographyEstimate {
  BackendHomographyEstimate({
    required this.homography,
    required Iterable<bool> inliers,
    this.duration = Duration.zero,
  }) : inliers = List<bool>.unmodifiable(inliers);

  final HomographyMatrix homography;
  final List<bool> inliers;
  final Duration duration;
}

final class BackendWarp {
  const BackendWarp({
    required this.canonicalPage,
    this.duration = Duration.zero,
  });

  final CanonicalPageImage canonicalPage;
  final Duration duration;
}

final class ArucoBackendOpenTimings {
  const ArucoBackendOpenTimings({
    this.decode = Duration.zero,
    this.detectionPreparation = Duration.zero,
    this.detection = Duration.zero,
    this.coordinateRemap = Duration.zero,
    this.detectionSize,
    this.detectionScaleX = 1,
    this.detectionScaleY = 1,
  });

  final Duration decode;
  final Duration detectionPreparation;
  final Duration detection;
  final Duration coordinateRemap;
  final ImageSize? detectionSize;
  final double detectionScaleX;
  final double detectionScaleY;
}
