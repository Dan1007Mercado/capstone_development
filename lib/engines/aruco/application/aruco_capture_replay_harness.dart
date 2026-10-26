import 'dart:collection';
import 'dart:typed_data';

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../layout/domain/page_layout.dart';
import '../domain/aruco_alignment_config.dart';
import '../domain/aruco_vision_backend.dart';
import '../domain/detected_marker.dart';
import '../domain/image_geometry.dart';
import '../domain/page_alignment_result.dart';
import 'aruco_alignment_engine.dart';
import 'homography_geometry_validator.dart';
import 'marker_correspondence_service.dart';

typedef ArucoVisionBackendFactory = ArucoVisionBackend Function();
typedef ArucoVisionBackendDisposer = void Function(ArucoVisionBackend backend);

/// Development-only comparison harness. Each path decodes the same captured
/// still independently; it is intentionally not used by production scanning.
final class ArucoCaptureReplayHarness {
  const ArucoCaptureReplayHarness({
    required this.backendFactory,
    this.disposeBackend,
    this.correspondenceService = const MarkerCorrespondenceService(),
    this.geometryValidator = const HomographyGeometryValidator(),
  });

  final ArucoVisionBackendFactory backendFactory;
  final ArucoVisionBackendDisposer? disposeBackend;
  final MarkerCorrespondenceService correspondenceService;
  final HomographyGeometryValidator geometryValidator;

  ArucoCaptureReplayResult run(
    Uint8List encodedImage,
    PageLayout page, {
    ArucoAlignmentConfig? legacyConfig,
    ArucoAlignmentConfig? currentFourPointConfig,
    ArucoAlignmentConfig? currentMultiPointConfig,
  }) {
    final legacy = _legacyFourPoint(
      encodedImage,
      page,
      legacyConfig ?? ArucoAlignmentConfig(enableMultipointHomography: false),
    );
    final fourBackend = backendFactory();
    final four = _runCurrent(
      backend: fourBackend,
      encodedImage: encodedImage,
      page: page,
      config:
          currentFourPointConfig ??
          ArucoAlignmentConfig(enableMultipointHomography: false),
    );
    final multiBackend = backendFactory();
    final multi = _runCurrent(
      backend: multiBackend,
      encodedImage: encodedImage,
      page: page,
      config: currentMultiPointConfig ?? ArucoAlignmentConfig(),
    );
    return ArucoCaptureReplayResult(
      legacyFourPoint: legacy,
      currentFourPoint: four,
      currentMultiPoint: multi,
      canonicalBubbleCenters: _canonicalBubbleCenters(page),
    );
  }

  EngineResult<LegacyFourPointReplay> _legacyFourPoint(
    Uint8List encodedImage,
    PageLayout page,
    ArucoAlignmentConfig config,
  ) {
    final backend = backendFactory();
    final opened = backend.open(encodedImage, config);
    if (opened.isFailure) {
      disposeBackend?.call(backend);
      return EngineResult.failure(opened.error);
    }
    final session = opened.value;
    try {
      final built = correspondenceService.build(
        detection: session.detection,
        page: page,
        config: config,
      );
      if (built.isFailure) return EngineResult.failure(built.error);
      final correspondences = built.value;
      final estimated = session.estimateHomography(
        sourcePoints: correspondences.baselineSourcePoints,
        destinationPoints: correspondences.baselineDestinationPoints,
        method: HomographyEstimationMethod.fourPoint,
        ransacReprojectionThresholdPixels:
            config.multipointRansacReprojectionThresholdPixels,
        maximumIterations: config.multipointMaximumIterations,
        confidence: config.multipointConfidence,
      );
      if (estimated.isFailure) return EngineResult.failure(estimated.error);
      final estimate = estimated.value;
      final fittingErrors = [
        for (final item in correspondences.baselineCorrespondences)
          _error(estimate.homography, item.sourcePoint, item.destinationPoint),
      ];
      final allCornerErrors = [
        for (final item in correspondences.allCornerCorrespondences)
          _error(estimate.homography, item.sourcePoint, item.destinationPoint),
      ];
      final geometryFailure = geometryValidator.validationFailure(
        matrix: estimate.homography,
        page: page,
        sourceSize: session.sourceSize,
        config: config,
      );
      final warp = session.warp(
        homography: estimate.homography,
        outputSize: ImageSize(
          width: page.canonicalPageSpec.widthPixels,
          height: page.canonicalPageSpec.heightPixels,
        ),
      );
      if (warp.isFailure) return EngineResult.failure(warp.error);
      return EngineResult.success(
        LegacyFourPointReplay(
          homography: estimate.homography,
          canonicalPage: warp.value.canonicalPage,
          detectedMarkers: session.detection.markers,
          fittingResiduals: fittingErrors,
          allCornerResiduals: allCornerErrors,
          acceptedByPreMultipointFittingGate:
              fittingErrors.every(
                (error) => error <= config.maximumReprojectionErrorPixels,
              ) &&
              geometryFailure == null,
          geometryValidationFailure: geometryFailure,
        ),
      );
    } on Object catch (error) {
      return EngineResult.failure(
        EngineError(
          code: 'ARUCO_REPLAY_FAILED',
          message: 'The legacy four-point replay could not be completed.',
          details: {'cause': error.toString()},
        ),
      );
    } finally {
      session.dispose();
      disposeBackend?.call(backend);
    }
  }

  EngineResult<PageAlignmentResult> _runCurrent({
    required ArucoVisionBackend backend,
    required Uint8List encodedImage,
    required PageLayout page,
    required ArucoAlignmentConfig config,
  }) {
    try {
      return ArucoAlignmentEngine(
        backend: backend,
        config: config,
      ).align(encodedImage, page);
    } finally {
      disposeBackend?.call(backend);
    }
  }

  double _error(
    HomographyMatrix matrix,
    ImagePoint source,
    ImagePoint target,
  ) => matrix.project(source).distanceTo(target);

  List<ImagePoint> _canonicalBubbleCenters(PageLayout page) => [
    for (final bubble in page.bubbleRegions)
      ImagePoint(
        bubble.normalizedBounds.left.value *
                page.canonicalPageSpec.widthPixels +
            bubble.normalizedBounds.width.value *
                page.canonicalPageSpec.widthPixels /
                2,
        bubble.normalizedBounds.top.value *
                page.canonicalPageSpec.heightPixels +
            bubble.normalizedBounds.height.value *
                page.canonicalPageSpec.heightPixels /
                2,
      ),
  ];
}

final class ArucoCaptureReplayResult {
  ArucoCaptureReplayResult({
    required this.legacyFourPoint,
    required this.currentFourPoint,
    required this.currentMultiPoint,
    required Iterable<ImagePoint> canonicalBubbleCenters,
  }) : canonicalBubbleCenters = UnmodifiableListView(
         List.of(canonicalBubbleCenters),
       );

  final EngineResult<LegacyFourPointReplay> legacyFourPoint;
  final EngineResult<PageAlignmentResult> currentFourPoint;
  final EngineResult<PageAlignmentResult> currentMultiPoint;
  final List<ImagePoint> canonicalBubbleCenters;
}

final class LegacyFourPointReplay {
  LegacyFourPointReplay({
    required this.homography,
    required this.canonicalPage,
    required Iterable<DetectedMarker> detectedMarkers,
    required Iterable<double> fittingResiduals,
    required Iterable<double> allCornerResiduals,
    required this.acceptedByPreMultipointFittingGate,
    required this.geometryValidationFailure,
  }) : detectedMarkers = UnmodifiableListView(List.of(detectedMarkers)),
       fittingResiduals = UnmodifiableListView(List.of(fittingResiduals)),
       allCornerResiduals = UnmodifiableListView(List.of(allCornerResiduals));

  final HomographyMatrix homography;
  final CanonicalPageImage canonicalPage;
  final List<DetectedMarker> detectedMarkers;
  final List<double> fittingResiduals;
  final List<double> allCornerResiduals;
  final bool acceptedByPreMultipointFittingGate;
  final String? geometryValidationFailure;
}
