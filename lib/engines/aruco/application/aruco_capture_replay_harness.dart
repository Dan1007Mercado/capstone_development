import 'dart:collection';
import 'dart:typed_data';

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../layout/domain/page_layout.dart';
import '../../recognition/application/bubble_alignment_evidence.dart';
import '../domain/aruco_alignment_config.dart';
import '../domain/alignment_failure_diagnostics.dart';
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
    this.bubbleEvidenceEvaluator = const BubbleAlignmentEvidenceEvaluator(),
  });

  final ArucoVisionBackendFactory backendFactory;
  final ArucoVisionBackendDisposer? disposeBackend;
  final MarkerCorrespondenceService correspondenceService;
  final HomographyGeometryValidator geometryValidator;
  final BubbleAlignmentEvidenceEvaluator bubbleEvidenceEvaluator;

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
    final multiRun = _runCurrent(
      backend: multiBackend,
      encodedImage: encodedImage,
      page: page,
      config: currentMultiPointConfig ?? ArucoAlignmentConfig(),
    );
    final productionBackend = backendFactory();
    final production = _runCurrent(
      backend: productionBackend,
      encodedImage: encodedImage,
      page: page,
      config: currentMultiPointConfig ?? ArucoAlignmentConfig(),
    );
    return ArucoCaptureReplayResult(
      legacyFourPoint: legacy,
      currentFourPointCandidate: _candidateReplay(
        four,
        AlignmentHomographyMethod.fourPoint,
        page,
      ),
      currentMultiPointCandidate: _candidateReplay(
        multiRun,
        AlignmentHomographyMethod.multiPoint,
        page,
      ),
      productionSelection: production,
      productionBubbleEvidence: production.isSuccess
          ? bubbleEvidenceEvaluator.evaluate(
              production.value.canonicalPage,
              page,
            )
          : null,
      canonicalBubbleCenters: _canonicalBubbleCenters(page),
    );
  }

  EngineResult<HomographyCandidateReplay> _candidateReplay(
    EngineResult<PageAlignmentResult> result,
    AlignmentHomographyMethod method,
    PageLayout page,
  ) {
    if (result.isFailure) {
      final failure = AlignmentFailureDiagnostics.findInDetails(
        result.error.details,
      );
      if (failure == null) return EngineResult.failure(result.error);
      final attempt = method == AlignmentHomographyMethod.fourPoint
          ? failure.fourPoint
          : failure.multiPoint;
      final homography = attempt.homography;
      if (homography == null ||
          attempt.estimationStatus != HomographyEstimationStatus.succeeded) {
        return EngineResult.failure(result.error);
      }
      return EngineResult.success(
        HomographyCandidateReplay(
          candidate: _rejectedCandidate(attempt),
          selectedForWarp: false,
          homography: homography,
          canonicalPage: null,
          bubbleEvidence: null,
          actualSelectionReason: failure.selectionReason,
          actualFallbackReason: null,
          failureAttempt: attempt,
        ),
      );
    }
    final alignment = result.value;
    final candidate = method == AlignmentHomographyMethod.fourPoint
        ? alignment.diagnostics.fourPointCandidate
        : alignment.diagnostics.multiPointCandidate;
    if (candidate == null) {
      return EngineResult.failure(
        EngineError(
          code: 'ARUCO_REPLAY_CANDIDATE_UNAVAILABLE',
          message: 'The requested ${method.name} candidate was not estimated.',
        ),
      );
    }
    final selected = alignment.diagnostics.selectedHomographyMethod == method;
    return EngineResult.success(
      HomographyCandidateReplay(
        candidate: candidate,
        selectedForWarp: selected,
        homography: candidate.homography,
        canonicalPage: selected ? alignment.canonicalPage : null,
        bubbleEvidence: selected
            ? bubbleEvidenceEvaluator.evaluate(alignment.canonicalPage, page)
            : null,
        actualSelectionReason: alignment.diagnostics.selectionReason,
        actualFallbackReason: alignment.diagnostics.fallbackReason,
        failureAttempt: null,
      ),
    );
  }

  HomographyCandidateDiagnostics _rejectedCandidate(
    HomographyAttemptDiagnostics attempt,
  ) {
    final residuals = attempt.cornerResiduals;
    return HomographyCandidateDiagnostics(
      method: attempt.method,
      commonReprojectionErrors: residuals,
      meanCommonReprojectionError: attempt.meanResidual ?? _mean(residuals),
      medianCommonReprojectionError:
          attempt.medianResidual ?? _median(residuals),
      maxCommonReprojectionError:
          attempt.maximumResidual ?? _maximum(residuals),
      inlierCount: attempt.inlierCount,
      totalPointCount: residuals.length,
      accepted: false,
      acceptance: HomographyCandidateAcceptance.unsafe,
      duration: attempt.estimationDuration + attempt.validationDuration,
      homography: attempt.homography,
      inliersPerMarker: attempt.inliersPerMarker,
      inlierMask: attempt.inlierMask,
      geometryValidationFailure: attempt.geometryValidationResult == 'passed'
          ? null
          : attempt.geometryValidationResult,
      rejectionReason: attempt.rejectionReason ?? attempt.estimationFailureCode,
    );
  }

  double _mean(List<double> values) => values.isEmpty
      ? 0
      : values.reduce((left, right) => left + right) / values.length;

  double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.of(values)..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }

  double _maximum(List<double> values) => values.isEmpty
      ? 0
      : values.reduce((left, right) => left > right ? left : right);

  EngineResult<LegacyFourPointReplay> _legacyFourPoint(
    Uint8List encodedImage,
    PageLayout page,
    ArucoAlignmentConfig config,
  ) {
    final stopwatch = Stopwatch()..start();
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
      stopwatch.stop();
      return EngineResult.success(
        LegacyFourPointReplay(
          homography: estimate.homography,
          canonicalPage: warp.value.canonicalPage,
          detectedMarkers: session.detection.markers,
          fittingResiduals: fittingErrors,
          allCornerResiduals: allCornerErrors,
          bubbleEvidence: bubbleEvidenceEvaluator.evaluate(
            warp.value.canonicalPage,
            page,
          ),
          acceptedByLegacyFittingGate: fittingErrors.every(
            (error) => error <= config.maximumReprojectionErrorPixels,
          ),
          geometryValidationFailure: geometryFailure,
          processingDuration: stopwatch.elapsed,
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
    required this.currentFourPointCandidate,
    required this.currentMultiPointCandidate,
    required this.productionSelection,
    required this.productionBubbleEvidence,
    required Iterable<ImagePoint> canonicalBubbleCenters,
  }) : canonicalBubbleCenters = UnmodifiableListView(
         List.of(canonicalBubbleCenters),
       );

  final EngineResult<LegacyFourPointReplay> legacyFourPoint;
  final EngineResult<HomographyCandidateReplay> currentFourPointCandidate;
  final EngineResult<HomographyCandidateReplay> currentMultiPointCandidate;
  final EngineResult<PageAlignmentResult> productionSelection;
  final BubbleAlignmentEvidence? productionBubbleEvidence;
  final List<ImagePoint> canonicalBubbleCenters;
}

final class HomographyCandidateReplay {
  const HomographyCandidateReplay({
    required this.candidate,
    required this.selectedForWarp,
    required this.homography,
    required this.canonicalPage,
    required this.bubbleEvidence,
    required this.actualSelectionReason,
    required this.actualFallbackReason,
    required this.failureAttempt,
  });

  final HomographyCandidateDiagnostics candidate;
  final bool selectedForWarp;
  final HomographyMatrix? homography;
  final CanonicalPageImage? canonicalPage;
  final BubbleAlignmentEvidence? bubbleEvidence;
  final String? actualSelectionReason;
  final String? actualFallbackReason;
  final HomographyAttemptDiagnostics? failureAttempt;
}

final class LegacyFourPointReplay {
  LegacyFourPointReplay({
    required this.homography,
    required this.canonicalPage,
    required Iterable<DetectedMarker> detectedMarkers,
    required Iterable<double> fittingResiduals,
    required Iterable<double> allCornerResiduals,
    required this.bubbleEvidence,
    required this.acceptedByLegacyFittingGate,
    required this.geometryValidationFailure,
    required this.processingDuration,
  }) : detectedMarkers = UnmodifiableListView(List.of(detectedMarkers)),
       fittingResiduals = UnmodifiableListView(List.of(fittingResiduals)),
       allCornerResiduals = UnmodifiableListView(List.of(allCornerResiduals));

  final HomographyMatrix homography;
  final CanonicalPageImage canonicalPage;
  final List<DetectedMarker> detectedMarkers;
  final List<double> fittingResiduals;
  final List<double> allCornerResiduals;
  final BubbleAlignmentEvidence bubbleEvidence;
  final bool acceptedByLegacyFittingGate;
  final String? geometryValidationFailure;
  final Duration processingDuration;
}
