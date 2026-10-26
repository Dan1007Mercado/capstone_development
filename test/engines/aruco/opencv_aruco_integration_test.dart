import 'dart:math' as math;
import 'dart:typed_data';

import 'package:capstone_development/core/geometry/physical_geometry.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/engines/aruco/application/aruco_alignment_engine.dart';
import 'package:capstone_development/engines/aruco/application/homography_geometry_validator.dart';
import 'package:capstone_development/engines/aruco/application/marker_correspondence_service.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_alignment_config.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_vision_backend.dart';
import 'package:capstone_development/engines/aruco/domain/detected_marker.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/aruco/infrastructure/opencv_aruco_vision_backend.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/layout/domain/layout_regions.dart';
import 'package:capstone_development/engines/pdf/infrastructure/opencv_4x4_50_marker_encoder.dart';
import 'package:capstone_development/engines/preprocessing/application/preprocessing_engine.dart';
import 'package:capstone_development/engines/preprocessing/infrastructure/dart_image_preprocessing_backend.dart';
import 'package:capstone_development/engines/recognition/application/bubble_measurement_engine.dart';
import 'package:capstone_development/engines/recognition/application/mark_classification_engine.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../layout/layout_test_fixtures.dart';

const _requireNativeOpenCv = bool.fromEnvironment('REQUIRE_NATIVE_OPENCV');

void main() {
  late PageLayout page;
  late TemplateDefinition template;
  late image.Image frontal;
  late bool backendAvailable;
  String? unavailableReason;

  setUpAll(() {
    template = fullTemplate();
    page = buildLayout(template).pages.single;
    frontal = _renderSyntheticPage(page);
    final backend = OpenCvArucoVisionBackend();
    final probe = backend.open(
      Uint8List.fromList(image.encodePng(frontal)),
      ArucoAlignmentConfig(),
    );
    backendAvailable = probe.isSuccess;
    if (probe.isSuccess) {
      probe.value.dispose();
    } else {
      unavailableReason = '${probe.error.code}: ${probe.error.message}';
    }
    backend.dispose();
  });

  test('native OpenCV runtime availability gate', () {
    if (!backendAvailable && _requireNativeOpenCv) {
      fail(
        'Native OpenCV is required but unavailable: '
        '${unavailableReason ?? 'unknown native loading failure'}',
      );
    }
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    expect(backendAvailable, isTrue);
  });

  test('clean frontal page detects and aligns all four markers', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final result = _align(frontal, page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(result.value.observations, hasLength(4));
    expect(result.value.diagnostics.expectedMarkerIds.toSet(), {
      10,
      11,
      12,
      13,
    });
    expect(result.value.diagnostics.maxReprojectionError, lessThan(0.01));
  });

  test('native detector corner order matches all 16 published corners', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final backend = OpenCvArucoVisionBackend();
    final opened = backend.open(
      Uint8List.fromList(image.encodePng(frontal)),
      ArucoAlignmentConfig(finalMarkerDetectionMaxDimension: null),
    );
    expect(opened.isSuccess, isTrue, reason: opened.errorOrNull?.toString());
    final session = opened.value;
    try {
      expect(session.detection.markers.map((marker) => marker.id).toSet(), {
        for (final region in page.markerRegions) region.markerId,
      });
      expect(session.detection.markers, hasLength(4));
      final errors = _cornerOrderingErrors(
        page: page,
        detected: session.detection.markers,
        canonicalToSource: HomographyMatrix(const [1, 0, 0, 0, 1, 0, 0, 0, 1]),
      );
      expect(errors, hasLength(16));
      expect(errors, everyElement(lessThan(2.5)));
    } finally {
      session.dispose();
      backend.dispose();
    }
  });

  test('native packet markers never replace registration marker roles', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final withIdentity = image.Image.from(frontal);
    for (var index = 0; index < 4; index++) {
      _drawMarker(
        withIdentity,
        markerId: index + 1,
        left: withIdentity.width ~/ 2 - 150 + index * 80,
        top: withIdentity.height ~/ 2,
        size: 64,
      );
    }
    final result = _align(withIdentity, page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(
      result.value.observations
          .map((item) => item.expectedRegion.markerId)
          .toSet(),
      {for (final region in page.markerRegions) region.markerId},
    );
    expect(result.value.detectedMarkers, hasLength(8));
  });

  for (final angle in [90, 180, 270]) {
    test('page rotated $angle degrees aligns by semantic marker IDs', () {
      if (!backendAvailable) {
        markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
        return;
      }
      final result = _align(image.copyRotate(frontal, angle: angle), page);

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      expect(result.value.observations, hasLength(4));
    });
  }

  test('moderate perspective page aligns', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final perspective = _perspectiveWarp(frontal, [
      ImagePoint(45, 70),
      ImagePoint(frontal.width - 75, 25),
      ImagePoint(frontal.width - 25, frontal.height - 65),
      ImagePoint(70, frontal.height - 20),
    ]);
    final result = _align(perspective, page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(result.value.observations, hasLength(4));
  });

  test(
    'perspective detector order and bubble landmarks match ground truth',
    () {
      if (!backendAvailable) {
        markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
        return;
      }
      final fixture = _perspectiveFixture(frontal, [
        ImagePoint(45, 70),
        ImagePoint(frontal.width - 75, 25),
        ImagePoint(frontal.width - 25, frontal.height - 65),
        ImagePoint(70, frontal.height - 20),
      ]);
      final result = _align(fixture.raster, page);

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      final cornerErrors = _cornerOrderingErrors(
        page: page,
        detected: result.value.detectedMarkers,
        canonicalToSource: fixture.canonicalToSource,
      );
      expect(cornerErrors, everyElement(lessThan(4.0)));

      final landmarkErrors = [
        for (final bubble in page.bubbleRegions)
          _canonicalBubbleCenter(bubble, page).distanceTo(
            result.value.homography.project(
              fixture.canonicalToSource.project(
                _canonicalBubbleCenter(bubble, page),
              ),
            ),
          ),
      ];
      final statistics = ReprojectionStatistics(landmarkErrors);
      expect(statistics.mean, lessThan(2.0));
      expect(statistics.percentile95, lessThan(3.0));
      expect(statistics.maximum, lessThan(4.0));
      expect(result.value.diagnostics.processingDuration, isNot(Duration.zero));
    },
  );

  test('four-point and multi-point accuracy use identical ground truth landmarks', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final fixture = _perspectiveFixture(frontal, [
      ImagePoint(45, 70),
      ImagePoint(frontal.width - 75, 25),
      ImagePoint(frontal.width - 25, frontal.height - 65),
      ImagePoint(70, frontal.height - 20),
    ]);
    final config = ArucoAlignmentConfig(finalMarkerDetectionMaxDimension: null);
    final production = _align(fixture.raster, page);
    expect(
      production.isSuccess,
      isTrue,
      reason: production.errorOrNull?.toString(),
    );
    final backend = OpenCvArucoVisionBackend();
    final opened = backend.open(
      Uint8List.fromList(image.encodePng(fixture.raster)),
      config,
    );
    expect(opened.isSuccess, isTrue, reason: opened.errorOrNull?.toString());
    final session = opened.value;
    try {
      final correspondences = const MarkerCorrespondenceService().build(
        detection: session.detection,
        page: page,
        config: config,
      );
      expect(
        correspondences.isSuccess,
        isTrue,
        reason: correspondences.errorOrNull?.toString(),
      );
      final set = correspondences.value;
      final four = session.estimateHomography(
        sourcePoints: set.baselineSourcePoints,
        destinationPoints: set.baselineDestinationPoints,
        method: HomographyEstimationMethod.fourPoint,
        ransacReprojectionThresholdPixels:
            config.multipointRansacReprojectionThresholdPixels,
        maximumIterations: config.multipointMaximumIterations,
        confidence: config.multipointConfidence,
      );
      final multi = session.estimateHomography(
        sourcePoints: set.allSourcePoints,
        destinationPoints: set.allDestinationPoints,
        method: HomographyEstimationMethod.multiPointRansac,
        ransacReprojectionThresholdPixels:
            config.multipointRansacReprojectionThresholdPixels,
        maximumIterations: config.multipointMaximumIterations,
        confidence: config.multipointConfidence,
      );
      expect(four.isSuccess, isTrue, reason: four.errorOrNull?.toString());
      expect(multi.isSuccess, isTrue, reason: multi.errorOrNull?.toString());
      final fourAccuracy = ReprojectionStatistics(
        _landmarkErrors(page, fixture.canonicalToSource, four.value.homography),
      );
      final multiAccuracy = ReprojectionStatistics(
        _landmarkErrors(
          page,
          fixture.canonicalToSource,
          multi.value.homography,
        ),
      );
      final crossValidation = _leaveOneMarkerOut(
        session: session,
        correspondences: set.allCornerCorrespondences,
        page: page,
        config: config,
      );
      expect(fourAccuracy.maximum, lessThan(5));
      expect(multiAccuracy.maximum, lessThan(5));
      expect(multiAccuracy.mean, lessThanOrEqualTo(fourAccuracy.mean + 1));
      expect(crossValidation.statistics.maximum, lessThan(4));

      final diagnostics = production.value.diagnostics;
      final p1521EstimatedHomographyCost =
          four.value.duration +
          multi.value.duration +
          crossValidation.estimationDuration;
      // These metrics are emitted only when the native gate executes. They
      // compare both production candidates against identical independent
      // bubble landmarks and isolate the removed P15.2.1 CV estimate cost.
      // ignore: avoid_print
      print(
        'P15_2_2_NATIVE_METRICS '
        'fourMean=${fourAccuracy.mean} '
        'fourP95=${fourAccuracy.percentile95} '
        'fourMax=${fourAccuracy.maximum} '
        'multiMean=${multiAccuracy.mean} '
        'multiP95=${multiAccuracy.percentile95} '
        'multiMax=${multiAccuracy.maximum} '
        'meanDifference=${multiAccuracy.mean - fourAccuracy.mean} '
        'crossValidationMean=${crossValidation.statistics.mean} '
        'crossValidationP95=${crossValidation.statistics.percentile95} '
        'crossValidationMax=${crossValidation.statistics.maximum} '
        'crossValidationWallUs=${crossValidation.wallDuration.inMicroseconds} '
        'p15_2_1EstimatedHomographyUs=${p1521EstimatedHomographyCost.inMicroseconds} '
        'p15_2_2FourPointUs=${diagnostics.fourPointHomographyDuration.inMicroseconds} '
        'p15_2_2MultiPointUs=${diagnostics.multiPointHomographyDuration.inMicroseconds} '
        'p15_2_2CandidateValidationUs=${diagnostics.candidateValidationDuration.inMicroseconds} '
        'p15_2_2WarpUs=${diagnostics.warpDuration.inMicroseconds} '
        'p15_2_2TotalAlignmentUs=${diagnostics.processingDuration.inMicroseconds}',
      );
    } finally {
      session.dispose();
      backend.dispose();
    }
  });

  test('rotated detector corners retain marker-local published ordering', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final rotated = image.copyRotate(frontal, angle: 90);
    final result = _align(rotated, page);
    final canonicalToSource = HomographyMatrix([
      0,
      -1,
      frontal.height - 1.0,
      1,
      0,
      0,
      0,
      0,
      1,
    ]);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(
      _cornerOrderingErrors(
        page: page,
        detected: result.value.detectedMarkers,
        canonicalToSource: canonicalToSource,
      ),
      everyElement(lessThan(4.0)),
    );
  });

  test('mild directional shadow preserves marker identity and alignment', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final shaded = _applyDirectionalShadow(frontal);
    final result = _align(shaded, page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(result.value.diagnostics.detectedMarkerIds.toSet(), {
      10,
      11,
      12,
      13,
    });
    expect(result.value.diagnostics.maxReprojectionError, lessThan(0.01));
  });

  test('translated complete page aligns inside a larger source image', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final canvas = image.Image(
      width: frontal.width + 160,
      height: frontal.height + 120,
      numChannels: 3,
    );
    image.fill(canvas, color: image.ColorRgb8(255, 255, 255));
    image.compositeImage(canvas, frontal, dstX: 70, dstY: 50);
    final result = _align(canvas, page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
  });

  test('moderate scale reduction aligns', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final scaled = image.copyResize(
      frontal,
      width: (frontal.width * 0.65).round(),
      interpolation: image.Interpolation.linear,
    );
    final result = _align(scaled, page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
  });

  test(
    'readable transformed sheets preserve marked and numeric OMR results',
    () {
      if (!backendAvailable) {
        markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
        return;
      }
      final firstQuestion = page.questionRegions.first;
      final numericQuestion = page.questionRegions.singleWhere(
        (question) => question.questionType == QuestionType.numericGrid,
      );
      final filled = <int>{
        page.bubbleRegions.indexWhere(
          (bubble) =>
              bubble.questionId == firstQuestion.questionId &&
              bubble.optionId == firstQuestion.bubbleRegions.first.optionId,
        ),
        for (var index = 0; index < page.bubbleRegions.length; index++)
          if (page.bubbleRegions[index].questionId ==
                  numericQuestion.questionId &&
              page.bubbleRegions[index].numericDigitValue == 2)
            index,
      };
      final marked = _renderSyntheticPage(page, filledBubbleIndexes: filled);
      final perspective = _perspectiveFixture(marked, [
        ImagePoint(40, 65),
        ImagePoint(marked.width - 70, 25),
        ImagePoint(marked.width - 25, marked.height - 60),
        ImagePoint(65, marked.height - 20),
      ]).raster;
      final fixtures = <String, image.Image>{
        'uniformScale': image.copyResize(
          marked,
          width: (marked.width * 0.72).round(),
          interpolation: image.Interpolation.linear,
        ),
        'nonuniformScale': image.copyResize(
          marked,
          width: (marked.width * 0.78).round(),
          height: (marked.height * 0.68).round(),
          interpolation: image.Interpolation.linear,
        ),
        'moderatePerspective': perspective,
        'directionalShadow': _applyDirectionalShadow(marked),
      };

      for (final entry in fixtures.entries) {
        final aligned = _align(entry.value, page);
        expect(
          aligned.isSuccess,
          isTrue,
          reason: '${entry.key}: ${aligned.errorOrNull}',
        );
        final classification = _classifyCanonical(
          aligned.value.canonicalPage,
          template,
          page,
        );
        expect(
          classification.isSuccess,
          isTrue,
          reason: '${entry.key}: ${classification.errorOrNull}',
        );
        final first = classification.value.questions.singleWhere(
          (question) => question.questionId == firstQuestion.questionId,
        );
        expect(first.state, MarkState.marked, reason: entry.key);
        expect(first.selectedOptionIds, [
          firstQuestion.bubbleRegions.first.optionId,
        ]);
        final numeric = classification.value.questions.singleWhere(
          (question) => question.questionId == numericQuestion.questionId,
        );
        expect(numeric.state, MarkState.marked, reason: entry.key);
        expect(
          numeric.numericSelection!.completeDigitString,
          List.filled(numeric.numericSelection!.columns.length, 2).join(),
          reason: entry.key,
        );
      }
    },
  );

  test('one erased marker returns required-marker-missing', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final missing = image.Image.from(frontal);
    _eraseRegion(missing, page, page.markerRegions.first.physicalBounds);
    final result = _align(missing, page);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'ARUCO_REQUIRED_MARKER_MISSING');
  });

  test('duplicate required marker returns ambiguity failure', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final duplicate = image.Image.from(frontal);
    _drawMarker(
      duplicate,
      markerId: page.markerRegions.first.markerId,
      left: duplicate.width ~/ 2 - 50,
      top: duplicate.height ~/ 2 - 50,
      size: 100,
    );
    final result = _align(duplicate, page);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'ARUCO_REQUIRED_MARKER_DUPLICATE');
  });

  test('severe degenerate perspective fails safely', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final degenerate = _perspectiveWarp(frontal, [
      ImagePoint(200, 700),
      ImagePoint(frontal.width - 200, 705),
      ImagePoint(frontal.width - 180, 735),
      ImagePoint(180, 730),
    ]);
    final result = _align(degenerate, page);

    expect(result.isFailure, isTrue);
  });

  test('canonical output dimensions exactly match PageLayout', () {
    if (!backendAvailable) {
      markTestSkipped(unavailableReason ?? 'Native OpenCV unavailable.');
      return;
    }
    final result = _align(frontal, page);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(
      result.value.canonicalPage.size,
      ImageSize(
        width: page.canonicalPageSpec.widthPixels,
        height: page.canonicalPageSpec.heightPixels,
      ),
    );
    expect(result.value.canonicalPage.pngBytes, isEmpty);
    expect(
      result.value.canonicalPage.grayscaleBytes,
      hasLength(
        page.canonicalPageSpec.widthPixels *
            page.canonicalPageSpec.heightPixels,
      ),
    );
    expect(result.value.diagnostics.decodeDuration, isNot(Duration.zero));
    expect(result.value.diagnostics.detectionDuration, isNot(Duration.zero));
  });
}

EngineResult<PageAlignmentResult> _align(image.Image source, PageLayout page) {
  final backend = OpenCvArucoVisionBackend();
  try {
    return ArucoAlignmentEngine(
      backend: backend,
    ).align(Uint8List.fromList(image.encodePng(source)), page);
  } finally {
    backend.dispose();
  }
}

image.Image _renderSyntheticPage(
  PageLayout page, {
  Set<int> filledBubbleIndexes = const {},
}) {
  final output = image.Image(
    width: page.canonicalPageSpec.widthPixels,
    height: page.canonicalPageSpec.heightPixels,
    numChannels: 3,
  );
  image.fill(output, color: image.ColorRgb8(255, 255, 255));
  for (var index = 0; index < page.bubbleRegions.length; index++) {
    final bubble = page.bubbleRegions[index];
    final center = _canonicalBubbleCenter(bubble, page);
    final radius = math.max(
      2,
      (bubble.normalizedBounds.width.value * output.width / 2).round(),
    );
    image.fillCircle(
      output,
      x: center.x.round(),
      y: center.y.round(),
      radius: radius,
      color: image.ColorRgb8(20, 20, 20),
    );
    image.fillCircle(
      output,
      x: center.x.round(),
      y: center.y.round(),
      radius: radius - 1,
      color: image.ColorRgb8(245, 245, 245),
    );
    if (filledBubbleIndexes.contains(index)) {
      image.fillCircle(
        output,
        x: center.x.round(),
        y: center.y.round(),
        radius: math.max(1, (radius * 0.65).round()),
        color: image.ColorRgb8(20, 20, 20),
      );
    }
  }
  for (final marker in page.markerRegions) {
    final bounds = marker.physicalBounds;
    final left = _physicalX(bounds.left.millimeters, page);
    final top = _physicalY(bounds.top.millimeters, page);
    final right = _physicalX(bounds.right.millimeters, page);
    final bottom = _physicalY(bounds.bottom.millimeters, page);
    _drawMarker(
      output,
      markerId: marker.markerId,
      left: left,
      top: top,
      size: math.min(right - left, bottom - top),
    );
  }
  return output;
}

EngineResult<PageClassificationResult> _classifyCanonical(
  CanonicalPageImage canonical,
  TemplateDefinition template,
  PageLayout page,
) {
  final preprocessed = const PreprocessingEngine(
    backend: DartImagePreprocessingBackend(),
  ).process(canonical);
  if (preprocessed.isFailure) {
    return EngineResult.failure(preprocessed.error);
  }
  final measured = const BubbleMeasurementEngine().measure(
    page,
    preprocessed.value,
  );
  if (measured.isFailure) return EngineResult.failure(measured.error);
  return const MarkClassificationEngine().classify(
    template,
    page,
    measured.value,
  );
}

image.Image _applyDirectionalShadow(image.Image source) {
  final shaded = image.Image.from(source);
  for (var y = 0; y < shaded.height; y++) {
    for (var x = 0; x < shaded.width; x++) {
      final pixel = shaded.getPixel(x, y);
      final factor = 0.58 + 0.42 * x / math.max(1, shaded.width - 1);
      shaded.setPixelRgb(
        x,
        y,
        (pixel.r * factor).round(),
        (pixel.g * factor).round(),
        (pixel.b * factor).round(),
      );
    }
  }
  return shaded;
}

void _drawMarker(
  image.Image target, {
  required int markerId,
  required int left,
  required int top,
  required int size,
}) {
  final matrix = const OpenCvDictionary4x4MarkerEncoder().encode(markerId);
  image.fillRect(
    target,
    x1: left,
    y1: top,
    x2: left + size - 1,
    y2: top + size - 1,
    color: image.ColorRgb8(255, 255, 255),
  );
  for (var row = 0; row < matrix.totalModules; row++) {
    for (var column = 0; column < matrix.totalModules; column++) {
      if (!matrix.modules[row][column]) continue;
      final x1 = left + (column * size / matrix.totalModules).round();
      final y1 = top + (row * size / matrix.totalModules).round();
      final x2 = left + ((column + 1) * size / matrix.totalModules).round() - 1;
      final y2 = top + ((row + 1) * size / matrix.totalModules).round() - 1;
      image.fillRect(
        target,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        color: image.ColorRgb8(0, 0, 0),
      );
    }
  }
}

void _eraseRegion(
  image.Image target,
  PageLayout page,
  PhysicalRect physicalBounds,
) {
  image.fillRect(
    target,
    x1: _physicalX(physicalBounds.left.millimeters, page) - 2,
    y1: _physicalY(physicalBounds.top.millimeters, page) - 2,
    x2: _physicalX(physicalBounds.right.millimeters, page) + 2,
    y2: _physicalY(physicalBounds.bottom.millimeters, page) + 2,
    color: image.ColorRgb8(255, 255, 255),
  );
}

image.Image _perspectiveWarp(
  image.Image source,
  List<ImagePoint> destination,
) => _perspectiveFixture(source, destination).raster;

_PerspectiveFixture _perspectiveFixture(
  image.Image source,
  List<ImagePoint> destination,
) {
  final sourceMat = cv.Mat.fromList(
    source.height,
    source.width,
    cv.MatType.CV_8UC3,
    source.getBytes(order: image.ChannelOrder.bgr),
  );
  final sourceVector = cv.VecPoint2f.generate(4, (index) {
    final points = [
      ImagePoint(0, 0),
      ImagePoint(source.width - 1, 0),
      ImagePoint(source.width - 1, source.height - 1),
      ImagePoint(0, source.height - 1),
    ];
    return cv.Point2f(points[index].x, points[index].y);
  });
  final destinationVector = cv.VecPoint2f.generate(
    4,
    (index) => cv.Point2f(destination[index].x, destination[index].y),
  );
  final homography = cv.getPerspectiveTransform2f(
    sourceVector,
    destinationVector,
  );
  final canonicalToSource = HomographyMatrix(
    homography.toList().expand((row) => row).map((value) => value.toDouble()),
  );
  final border = cv.Scalar.all(255);
  final warped = cv.warpPerspective(sourceMat, homography, (
    source.width,
    source.height,
  ), borderValue: border);
  try {
    final (success, bytes) = cv.imencode('.png', warped);
    if (!success) throw StateError('Synthetic perspective encoding failed.');
    return _PerspectiveFixture(
      raster: image.decodePng(bytes)!,
      canonicalToSource: canonicalToSource,
    );
  } finally {
    warped.dispose();
    border.dispose();
    homography.dispose();
    destinationVector.dispose();
    sourceVector.dispose();
    sourceMat.dispose();
  }
}

List<double> _cornerOrderingErrors({
  required PageLayout page,
  required List<DetectedMarker> detected,
  required HomographyMatrix canonicalToSource,
}) {
  const service = MarkerCorrespondenceService();
  final detectedById = {for (final marker in detected) marker.id: marker};
  return [
    for (final region in page.markerRegions)
      for (final corner in MarkerCorner.values)
        detectedById[region.markerId]!
            .corner(corner)
            .distanceTo(
              canonicalToSource.project(
                service.physicalMarkerCornerToCanonical(region, corner, page),
              ),
            ),
  ];
}

ImagePoint _canonicalBubbleCenter(BubbleRegion bubble, PageLayout page) =>
    ImagePoint(
      bubble.physicalCenter.x.millimeters /
          page.pageSpec.size.width.millimeters *
          page.canonicalPageSpec.widthPixels,
      bubble.physicalCenter.y.millimeters /
          page.pageSpec.size.height.millimeters *
          page.canonicalPageSpec.heightPixels,
    );

List<double> _landmarkErrors(
  PageLayout page,
  HomographyMatrix canonicalToSource,
  HomographyMatrix sourceToCanonical,
) => [
  for (final bubble in page.bubbleRegions)
    _canonicalBubbleCenter(bubble, page).distanceTo(
      sourceToCanonical.project(
        canonicalToSource.project(_canonicalBubbleCenter(bubble, page)),
      ),
    ),
];

_CrossValidationMetrics _leaveOneMarkerOut({
  required ArucoImageSession session,
  required List<MarkerCorrespondence> correspondences,
  required PageLayout page,
  required ArucoAlignmentConfig config,
}) {
  final wallStopwatch = Stopwatch()..start();
  final errors = <double>[];
  var estimationDuration = Duration.zero;
  const geometryValidator = HomographyGeometryValidator();
  for (final marker in page.markerRegions) {
    final training = correspondences
        .where((item) => item.markerId != marker.markerId)
        .toList(growable: false);
    final heldOut = correspondences
        .where((item) => item.markerId == marker.markerId)
        .toList(growable: false);
    if (training.length != 12 || heldOut.length != 4) {
      throw StateError('Invalid leave-one-marker-out partition.');
    }
    final estimate = session.estimateHomography(
      sourcePoints: training.map((item) => item.sourcePoint).toList(),
      destinationPoints: training.map((item) => item.destinationPoint).toList(),
      method: HomographyEstimationMethod.multiPointRansac,
      ransacReprojectionThresholdPixels:
          config.multipointRansacReprojectionThresholdPixels,
      maximumIterations: config.multipointMaximumIterations,
      confidence: config.multipointConfidence,
    );
    if (estimate.isFailure) {
      throw StateError(
        'Leave-one-marker-out estimate failed: ${estimate.error.code}',
      );
    }
    estimationDuration += estimate.value.duration;
    final stabilityFailure = geometryValidator.validationFailure(
      matrix: estimate.value.homography,
      page: page,
      sourceSize: session.sourceSize,
      config: config,
    );
    if (stabilityFailure != null) {
      throw StateError(
        'Leave-one-marker-out estimate is unstable: $stabilityFailure',
      );
    }
    for (final correspondence in heldOut) {
      errors.add(
        estimate.value.homography
            .project(correspondence.sourcePoint)
            .distanceTo(correspondence.destinationPoint),
      );
    }
  }
  wallStopwatch.stop();
  return _CrossValidationMetrics(
    statistics: ReprojectionStatistics(errors),
    estimationDuration: estimationDuration,
    wallDuration: wallStopwatch.elapsed,
  );
}

final class _CrossValidationMetrics {
  const _CrossValidationMetrics({
    required this.statistics,
    required this.estimationDuration,
    required this.wallDuration,
  });

  final ReprojectionStatistics statistics;
  final Duration estimationDuration;
  final Duration wallDuration;
}

final class _PerspectiveFixture {
  const _PerspectiveFixture({
    required this.raster,
    required this.canonicalToSource,
  });

  final image.Image raster;
  final HomographyMatrix canonicalToSource;
}

int _physicalX(double millimeters, PageLayout page) =>
    (millimeters /
            page.pageSpec.size.width.millimeters *
            page.canonicalPageSpec.widthPixels)
        .round();

int _physicalY(double millimeters, PageLayout page) =>
    (millimeters /
            page.pageSpec.size.height.millimeters *
            page.canonicalPageSpec.heightPixels)
        .round();
