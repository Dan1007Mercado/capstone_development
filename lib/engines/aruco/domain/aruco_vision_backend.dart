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
  });

  final CanonicalPageImage canonicalPage;
  final HomographyMatrix homography;
}
