import 'dart:async';
import 'dart:typed_data';

import 'package:capstone_development/application/camera_scanner/application/camera_scanner_coordinator.dart';
import 'package:capstone_development/application/camera_scanner/domain/camera_scan_context.dart';
import 'package:capstone_development/application/camera_scanner/domain/camera_scan_ports.dart';
import 'package:capstone_development/application/camera_scanner/infrastructure/camera_scan_adapters.dart';
import 'package:capstone_development/core/geometry/page_spec.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_alignment_config.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/camera/domain/camera_models.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/preprocessing/application/preprocessing_engine.dart';
import 'package:capstone_development/engines/preprocessing/infrastructure/dart_image_preprocessing_backend.dart';
import 'package:capstone_development/engines/recognition/application/bubble_measurement_engine.dart';
import 'package:capstone_development/engines/recognition/application/mark_classification_engine.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification.dart';
import 'package:capstone_development/engines/scanner/application/offline_scanner_engine.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_stages.dart';
import 'package:capstone_development/engines/scanner/infrastructure/scanner_stage_adapters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

import '../../engines/layout/layout_test_fixtures.dart';

void main() {
  test(
    'fake high-quality camera still traverses the real P6-P9 pipeline',
    () async {
      final template = templateWithQuestions([
        choiceQuestion('question', optionCount: 3),
      ]);
      final page = buildLayout(
        template,
        config: testConfig(
          canonicalPageSpec: CanonicalPageSpec(
            widthPixels: 840,
            heightPixels: 1188,
          ),
          bubbleDiameterMm: 6,
          optionCellWidthMm: 20,
        ),
      ).pages.single;
      final alignment = _CanonicalAlignmentStage(
        _render(page, filledIndexes: const {1}),
      );
      final scanner = OfflineScannerEngine(
        alignment: alignment,
        preprocessing: const PreprocessingStageAdapter(
          PreprocessingEngine(backend: DartImagePreprocessingBackend()),
        ),
        measurement: const BubbleMeasurementStageAdapter(
          BubbleMeasurementEngine(),
        ),
        classification: const MarkClassificationStageAdapter(
          MarkClassificationEngine(),
        ),
      );
      final camera = _ReadyHighQualityCamera();
      final context = CameraScanContext(
        template: template,
        pageLayout: page,
        templateId: template.id,
        templateVersion: template.version,
        pageId: page.pageId,
        scannerConfig: ScannerConfig(),
      );
      final coordinator = CameraScannerCoordinator(
        camera: camera,
        imageLoader: const InMemoryCapturedImageBytesLoader(),
        scanner: OfflineScannerRunnerAdapter(scanner),
        context: context,
      );

      expect((await coordinator.initialize()).isSuccess, isTrue);
      final result = await coordinator.captureAndScan();

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      expect(alignment.receivedBytes, camera.highQualityBytes);
      expect(result.value.templateId, template.id);
      expect(result.value.templateVersion, template.version);
      expect(result.value.pageId, page.pageId);
      expect(result.value.questions.single.state, MarkState.marked);
      expect(result.value.questions.single.selectedOptionIds, [
        page.bubbleRegions[1].optionId,
      ]);
      await coordinator.dispose();
    },
  );
}

final class _ReadyHighQualityCamera implements CameraScanCamera {
  final StreamController<CameraEngineState> _states =
      StreamController<CameraEngineState>.broadcast();
  CameraEngineState _state = const CameraEngineState.uninitialized();
  final Uint8List highQualityBytes = Uint8List.fromList(
    List<int>.generate(2048, (index) => index % 256),
  );

  @override
  CameraEngineState get state => _state;

  @override
  Stream<CameraEngineState> get states => _states.stream;

  @override
  Future<EngineResult<bool>> initialize() async {
    _publish(_readyState(CameraLifecycleState.ready));
    return EngineResult.success(true);
  }

  @override
  Future<EngineResult<bool>> startAnalysis() async {
    _publish(_readyState(CameraLifecycleState.analyzing));
    return EngineResult.success(true);
  }

  @override
  Future<EngineResult<bool>> stopAnalysis() async {
    _publish(_readyState(CameraLifecycleState.ready));
    return EngineResult.success(true);
  }

  @override
  Future<EngineResult<CapturedPageImage>> capture() async =>
      EngineResult.success(
        CapturedPageImage(
          encodedBytes: highQualityBytes,
          timestamp: DateTime.utc(2026),
          sensorOrientationDegrees: 90,
          deviceOrientation: CameraDeviceOrientation.portraitUp,
          orientationAppliedByBackend: true,
          width: 4000,
          height: 3000,
        ),
      );

  @override
  Future<EngineResult<bool>> suspend() async {
    _publish(const CameraEngineState.uninitialized());
    return EngineResult.success(true);
  }

  @override
  Future<void> dispose() async {
    await _states.close();
  }

  void _publish(CameraEngineState state) {
    _state = state;
    _states.add(state);
  }
}

CameraEngineState _readyState(CameraLifecycleState lifecycle) =>
    CameraEngineState(
      lifecycle: lifecycle,
      diagnostics: const CameraDiagnostics(),
      readiness: const CaptureReadiness(
        status: CaptureReadinessStatus.ready,
        stableFrameCount: 3,
        requiredStableFrameCount: 3,
      ),
    );

final class _CanonicalAlignmentStage implements ScannerAlignmentStage {
  _CanonicalAlignmentStage(this.canonical);

  final CanonicalPageImage canonical;
  Uint8List? receivedBytes;

  @override
  EngineResult<PageAlignmentResult> align(
    Uint8List encodedImage,
    PageLayout page,
    ArucoAlignmentConfig config,
  ) {
    receivedBytes = Uint8List.fromList(encodedImage);
    return EngineResult.success(
      PageAlignmentResult(
        canonicalPage: canonical,
        homography: HomographyMatrix(const [1, 0, 0, 0, 1, 0, 0, 0, 1]),
        observations: const [],
        correspondences: const [],
        diagnostics: PageAlignmentDiagnostics(
          expectedMarkerIds: page.markerRegions.map(
            (region) => region.markerId,
          ),
          detectedMarkerIds: page.markerRegions.map(
            (region) => region.markerId,
          ),
          sourceMarkerSideLengths: const [10, 10, 10, 10],
          sourceRegistrationPoints: const [],
          destinationRegistrationPoints: const [],
          registrationQuality: const RegistrationQuality(
            quadrilateralAreaRatio: 0.8,
            minimumMarkerSidePixels: 10,
            maximumPerspectiveRatio: 1,
          ),
          reprojectionErrors: const [0, 0, 0, 0],
          meanReprojectionError: 0,
          maxReprojectionError: 0,
          processingDuration: Duration.zero,
        ),
      ),
    );
  }
}

CanonicalPageImage _render(PageLayout page, {required Set<int> filledIndexes}) {
  final width = page.canonicalPageSpec.widthPixels;
  final height = page.canonicalPageSpec.heightPixels;
  final canvas = image.Image(width: width, height: height, numChannels: 3);
  image.fill(canvas, color: image.ColorRgb8(245, 245, 245));
  for (var index = 0; index < page.bubbleRegions.length; index++) {
    final bubble = page.bubbleRegions[index];
    final centerX = (bubble.normalizedCenter.x.value * width).round();
    final centerY = (bubble.normalizedCenter.y.value * height).round();
    final radius = (bubble.normalizedBounds.width.value * width / 2).round();
    image.fillCircle(
      canvas,
      x: centerX,
      y: centerY,
      radius: radius,
      color: image.ColorRgb8(20, 20, 20),
    );
    image.fillCircle(
      canvas,
      x: centerX,
      y: centerY,
      radius: radius - 1,
      color: image.ColorRgb8(245, 245, 245),
    );
    if (filledIndexes.contains(index)) {
      image.fillCircle(
        canvas,
        x: centerX,
        y: centerY,
        radius: (radius * 0.65).round(),
        color: image.ColorRgb8(20, 20, 20),
      );
    }
  }
  return CanonicalPageImage(
    size: ImageSize(width: width, height: height),
    pngBytes: image.encodePng(canvas),
  );
}
