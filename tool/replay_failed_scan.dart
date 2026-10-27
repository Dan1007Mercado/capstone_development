import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:capstone_development/application/real_scanner/failed_scan_replay_bundle.dart';
import 'package:capstone_development/application/real_scanner/physical_validation_recorder.dart';
import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/engines/aruco/application/aruco_capture_replay_harness.dart';
import 'package:capstone_development/engines/aruco/application/marker_correspondence_service.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_alignment_config.dart';
import 'package:capstone_development/engines/aruco/domain/detected_marker.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/aruco/infrastructure/opencv_aruco_vision_backend.dart';
import 'package:capstone_development/engines/recognition/application/bubble_alignment_evidence.dart';
import 'package:capstone_development/engines/recognition/application/bubble_alignment_ground_truth.dart';
import 'package:capstone_development/engines/preprocessing/infrastructure/opencv_preprocessing_backend.dart';
import 'package:capstone_development/engines/scanner/infrastructure/offline_scanner_composition.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config_codec.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config.dart';
import 'package:image/image.dart' as image;

void main(List<String> arguments) {
  final parsed = _Arguments.parse(arguments);
  if (parsed.bundlePath == null) {
    stderr.writeln(
      'Usage: dart run tool/replay_failed_scan.dart --bundle <capture.zip> '
      '[--json] [--compare-resolution] '
      '[--ground-truth annotations.json] '
      '[--expected-answers answers.json] [--output-dir diagnostics]',
    );
    exitCode = 64;
    return;
  }
  try {
    final bundleBytes = File(parsed.bundlePath!).readAsBytesSync();
    final bundle = const FailedScanReplayBundleCodec().decode(bundleBytes);
    final baseConfig = _withSelectionPolicy(
      bundle.scannerConfig.alignment,
      HomographySelectionPolicy.fourPointBaseline,
    );
    final groundTruth = parsed.groundTruthPath == null
        ? const <BubbleGroundTruthAnnotation>[]
        : _loadGroundTruth(parsed.groundTruthPath!);
    final expected = parsed.expectedAnswersPath == null
        ? null
        : PhysicalValidationPlan.fromJson(
            (jsonDecode(File(parsed.expectedAnswersPath!).readAsStringSync())
                    as Map)
                .cast<String, Object?>(),
          );
    final recordedRun = _run(
      bundle,
      baseConfig,
      label: 'p15.4-four-point-baseline',
      groundTruth: groundTruth,
      expected: expected,
      outputDirectory: parsed.outputDirectory,
    );
    final fullResolutionRun = parsed.compareResolution
        ? _run(
            bundle,
            _withDetectionLimit(baseConfig, null),
            label: 'full-resolution',
            groundTruth: groundTruth,
            expected: expected,
            outputDirectory: parsed.outputDirectory,
          )
        : null;
    final report = <String, Object?>{
      'bundle': {
        'templateId': bundle.template.id.value,
        'templateVersion': bundle.template.version.value,
        'pageId': bundle.pageId.value,
        'capturedAtUtc': bundle.capturedAtUtc.toIso8601String(),
        'originalFailure': bundle.failure.code,
        'pdfGeometryVerification': _verifyPdfGeometry(
          bundle,
          baseConfig,
          outputDirectory: parsed.outputDirectory,
          maximumErrorPixels: parsed.pdfMaximumErrorPixels,
        ),
      },
      'runs': [recordedRun, ?fullResolutionRun],
      if (fullResolutionRun != null)
        'resolutionComparison': _compareResolutionRuns(
          recordedRun,
          fullResolutionRun,
        ),
    };
    final formatted = parsed.json
        ? jsonEncode(report)
        : const JsonEncoder.withIndent('  ').convert(report);
    if (parsed.outputDirectory case final output?) {
      final directory = Directory(output)..createSync(recursive: true);
      File(
        '${directory.path}${Platform.pathSeparator}replay_report.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    }
    stdout.writeln(formatted);
  } on Object catch (error, stack) {
    stderr.writeln('Replay failed: $error');
    if (error.toString().contains('ARUCO_BACKEND_UNAVAILABLE') ||
        error.toString().contains('native symbols')) {
      stderr.writeln(
        'OpenCV native symbols are unavailable on this host. Run from a '
        'Flutter/OpenCV-enabled desktop build or execute the native tests on '
        'the configured Android device; this is not a passing replay.',
      );
    }
    if (parsed.verbose) stderr.writeln(stack);
    exitCode = 1;
  }
}

Map<String, Object?> _verifyPdfGeometry(
  FailedScanReplayBundle bundle,
  ArucoAlignmentConfig config, {
  required String? outputDirectory,
  required double maximumErrorPixels,
}) {
  final pdf = bundle.publishedPdfBytes;
  if (pdf == null) {
    return const {'status': 'EXACT_ORIGINAL_PDF_UNAVAILABLE'};
  }
  final temporary = Directory.systemTemp.createTempSync('talaanscan_pdf_');
  try {
    final pdfPath = '${temporary.path}${Platform.pathSeparator}published.pdf';
    final prefix = '${temporary.path}${Platform.pathSeparator}page';
    File(pdfPath).writeAsBytesSync(pdf);
    ProcessResult rasterized;
    try {
      rasterized = Process.runSync('pdftoppm', [
        '-png',
        '-f',
        '${bundle.page.pageIndex + 1}',
        '-l',
        '${bundle.page.pageIndex + 1}',
        '-singlefile',
        '-r',
        '300',
        pdfPath,
        prefix,
      ]);
    } on ProcessException catch (error) {
      return {
        'status': 'PDF_RASTERIZER_UNAVAILABLE',
        'message': error.message,
        'requiredExecutable': 'pdftoppm',
      };
    }
    if (rasterized.exitCode != 0) {
      return {
        'status': 'PDF_RASTERIZATION_FAILED',
        'exitCode': rasterized.exitCode,
        'stderr': '${rasterized.stderr}',
      };
    }
    final rasterFile = File('$prefix.png');
    if (!rasterFile.existsSync()) {
      return const {'status': 'PDF_RASTERIZATION_OUTPUT_MISSING'};
    }
    final rasterBytes = rasterFile.readAsBytesSync();
    if (outputDirectory case final output?) {
      final destination = File(
        '$output${Platform.pathSeparator}published_page_${bundle.page.pageIndex + 1}_300dpi.png',
      );
      destination.parent.createSync(recursive: true);
      destination.writeAsBytesSync(rasterBytes);
    }
    final backend = OpenCvArucoVisionBackend();
    final opened = backend.open(rasterBytes, _withDetectionLimit(config, null));
    if (opened.isFailure) {
      backend.dispose();
      return {
        'status': opened.error.code == 'ARUCO_BACKEND_UNAVAILABLE'
            ? 'NATIVE_OPENCV_UNAVAILABLE'
            : 'PDF_MARKER_DETECTION_FAILED',
        'error': _error(opened.error),
      };
    }
    final session = opened.value;
    try {
      final correspondences = const MarkerCorrespondenceService().build(
        detection: session.detection,
        page: bundle.page,
        config: _withDetectionLimit(config, null),
      );
      if (correspondences.isFailure) {
        return {
          'status': 'PDF_MARKER_CORRESPONDENCE_FAILED',
          'error': _error(correspondences.error),
        };
      }
      final scaleX =
          session.sourceSize.width / bundle.page.canonicalPageSpec.widthPixels;
      final scaleY =
          session.sourceSize.height /
          bundle.page.canonicalPageSpec.heightPixels;
      final errors = <Map<String, Object?>>[];
      for (final item in correspondences.value.allCornerCorrespondences) {
        final expectedX = item.destinationPoint.x * scaleX;
        final expectedY = item.destinationPoint.y * scaleY;
        final dx = item.sourcePoint.x - expectedX;
        final dy = item.sourcePoint.y - expectedY;
        errors.add({
          'markerId': item.markerId,
          'corner': item.sourceCorner.name,
          'detected': {'x': item.sourcePoint.x, 'y': item.sourcePoint.y},
          'layoutExpected': {'x': expectedX, 'y': expectedY},
          'errorPixels': math.sqrt(dx * dx + dy * dy),
        });
      }
      final maximum = errors
          .map((value) => value['errorPixels']! as double)
          .reduce((a, b) => a > b ? a : b);
      return {
        'status': maximum <= maximumErrorPixels
            ? 'PDF_GEOMETRY_MATCHES_LAYOUT'
            : 'PDF_GEOMETRY_MISMATCH',
        'rasterDpi': 300,
        'sourceSize': _size(session.sourceSize),
        'scaleFromCanonical': {'x': scaleX, 'y': scaleY},
        'maximumAllowedErrorPixels': maximumErrorPixels,
        'maximumErrorPixels': maximum,
        'markerCornerErrors': errors,
      };
    } finally {
      session.dispose();
      backend.dispose();
    }
  } finally {
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
  }
}

Map<String, Object?> _compareResolutionRuns(
  Map<String, Object?> recorded,
  Map<String, Object?> fullResolution,
) {
  final first = _detectedCornerMap(recorded);
  final second = _detectedCornerMap(fullResolution);
  final shared = first.keys.toSet().intersection(second.keys.toSet()).toList()
    ..sort();
  final differences = <Map<String, Object?>>[];
  for (final key in shared) {
    final a = first[key]!;
    final b = second[key]!;
    final dx = b.$1 - a.$1;
    final dy = b.$2 - a.$2;
    differences.add({
      'markerCorner': key,
      'recorded': {'x': a.$1, 'y': a.$2},
      'fullResolution': {'x': b.$1, 'y': b.$2},
      'deltaX': dx,
      'deltaY': dy,
      'distancePixels': math.sqrt(dx * dx + dy * dy),
    });
  }
  return {
    'coordinateSpace': 'original captured-image pixels',
    'sharedCornerCount': shared.length,
    'cornerDifferences': differences,
    'maximumDifferencePixels': differences.isEmpty
        ? null
        : differences
              .map((item) => item['distancePixels']! as double)
              .reduce((a, b) => a > b ? a : b),
  };
}

Map<String, (double, double)> _detectedCornerMap(Map<String, Object?> run) {
  final production = run['D_actualProductionSelection'] as Map;
  final markers = production['detectedMarkers'];
  if (markers is List) {
    const names = ['topLeft', 'topRight', 'bottomRight', 'bottomLeft'];
    return {
      for (final marker in markers)
        for (var index = 0; index < (marker as Map)['corners'].length; index++)
          '${marker['id']}:${names[index]}': (
            (((marker['corners'] as List)[index] as Map)['x'] as num)
                .toDouble(),
            (((marker['corners'] as List)[index] as Map)['y'] as num)
                .toDouble(),
          ),
    };
  }
  Object? current = production['details'];
  while (current is Map) {
    final diagnostics = current['alignmentFailureDiagnostics'];
    if (diagnostics is Map && diagnostics['detectedCorners'] is List) {
      return {
        for (final item in diagnostics['detectedCorners'] as List)
          '${(item as Map)['id']}:${item['corner']}': (
            (item['x'] as num).toDouble(),
            (item['y'] as num).toDouble(),
          ),
      };
    }
    current = current['causeDetails'];
  }
  return {};
}

Map<String, Object?> _run(
  FailedScanReplayBundle bundle,
  ArucoAlignmentConfig config, {
  required String label,
  required List<BubbleGroundTruthAnnotation> groundTruth,
  required PhysicalValidationPlan? expected,
  required String? outputDirectory,
}) {
  final result =
      ArucoCaptureReplayHarness(
        backendFactory: OpenCvArucoVisionBackend.new,
        disposeBackend: (backend) {
          if (backend is OpenCvArucoVisionBackend) backend.dispose();
        },
      ).run(
        bundle.encodedImage,
        bundle.page,
        legacyConfig: _withMultipoint(config, false),
        currentFourPointConfig: _withMultipoint(config, false),
        currentMultiPointConfig: _withSelectionPolicy(
          _withMultipoint(config, true),
          HomographySelectionPolicy.validatedMultiPointPreference,
        ),
        productionConfig: config,
      );
  final production = result.productionSelection;
  if (production.isFailure &&
      production.error.code == 'ARUCO_BACKEND_UNAVAILABLE') {
    throw StateError('${production.error.code}: ${production.error.message}');
  }
  final omr = _scanOmr(bundle, config, expected);
  final overlays = outputDirectory == null
      ? const <String>[]
      : _writeOverlays(bundle, result, label, outputDirectory, config);
  return {
    'label': label,
    'detectionMaxDimension': config.finalMarkerDetectionMaxDimension,
    'A_legacyDiagnosticSimulationFourPoint': result.legacyFourPoint.isSuccess
        ? {
            'label': 'legacy diagnostic simulation; not production validation',
            'homography': result.legacyFourPoint.value.homography.values,
            'acceptedByLegacyFittingGate':
                result.legacyFourPoint.value.acceptedByLegacyFittingGate,
            'geometryFailure':
                result.legacyFourPoint.value.geometryValidationFailure,
            'durationMs':
                result.legacyFourPoint.value.processingDuration.inMicroseconds /
                1000,
            'fittingResiduals': result.legacyFourPoint.value.fittingResiduals,
            'allCornerResiduals':
                result.legacyFourPoint.value.allCornerResiduals,
            'bubbleEvidence': _evidence(
              result.legacyFourPoint.value.bubbleEvidence,
            ),
            'groundTruth': _groundTruth(
              bundle,
              result.legacyFourPoint.value.homography,
              groundTruth,
            ),
          }
        : _error(result.legacyFourPoint.error),
    'B_currentFourPointCandidate': result.currentFourPointCandidate.isSuccess
        ? _candidate(
            result.currentFourPointCandidate.value,
            bundle,
            groundTruth,
          )
        : _error(result.currentFourPointCandidate.error),
    'C_current16PointRansacCandidate':
        result.currentMultiPointCandidate.isSuccess
        ? _candidate(
            result.currentMultiPointCandidate.value,
            bundle,
            groundTruth,
          )
        : _error(result.currentMultiPointCandidate.error),
    'D_actualProductionSelection': production.isSuccess
        ? {
            'accepted': true,
            'selectedMethod':
                production.value.diagnostics.selectedHomographyMethod.name,
            'selectionReason': production.value.diagnostics.selectionReason,
            'fallbackReason': production.value.diagnostics.fallbackReason,
            'sourceSize': _size(production.value.diagnostics.sourceSize),
            'detectionSize': _size(production.value.diagnostics.detectionSize),
            'detectionScaleX': production.value.diagnostics.detectionScaleX,
            'detectionScaleY': production.value.diagnostics.detectionScaleY,
            'markerSideLengths':
                production.value.diagnostics.sourceMarkerSideLengths,
            'detectedMarkers': [
              for (final marker in production.value.detectedMarkers)
                {
                  'id': marker.id,
                  'corners': [
                    for (final corner in marker.corners)
                      {'x': corner.x, 'y': corner.y},
                  ],
                  'sideLengths': marker.sideLengths,
                },
            ],
            'effectiveThresholds': {
              'reprojectionPixels':
                  production.value.diagnostics.effectiveReprojectionErrorPixels,
              'ransacPixels': production
                  .value
                  .diagnostics
                  .effectiveRansacReprojectionThresholdPixels,
              'rejectedCornerPixels': production
                  .value
                  .diagnostics
                  .effectiveRejectedCornerErrorPixels,
              'localizationScale':
                  production.value.diagnostics.reprojectionScaleFactor,
            },
            'durationMs':
                production.value.diagnostics.processingDuration.inMicroseconds /
                1000,
            'bubbleEvidence': _evidence(result.productionBubbleEvidence),
            'groundTruth': _groundTruth(
              bundle,
              production.value.homography,
              groundTruth,
            ),
          }
        : _error(production.error),
    'productionOmr': omr,
    'overlays': overlays,
  };
}

List<String> _writeOverlays(
  FailedScanReplayBundle bundle,
  ArucoCaptureReplayResult result,
  String label,
  String outputDirectory,
  ArucoAlignmentConfig config,
) {
  final decoded = image.decodeImage(bundle.encodedImage);
  if (decoded == null) return const [];
  final directory = Directory(outputDirectory)..createSync(recursive: true);
  final overlays = <String>[];
  void render(String method, HomographyMatrix homography) {
    final canvas = image.Image.from(decoded);
    final inverse = homography.inverse();
    final legacy = result.legacyFourPoint.valueOrNull;
    final built = legacy == null
        ? null
        : const MarkerCorrespondenceService().build(
            detection: ArucoDetection(
              sourceSize: ImageSize(
                width: decoded.width,
                height: decoded.height,
              ),
              markers: legacy.detectedMarkers,
            ),
            page: bundle.page,
            config: config,
          );
    if (built?.isSuccess == true) {
      for (final correspondence in built!.value.allCornerCorrespondences) {
        final observed = correspondence.sourcePoint;
        final predicted = inverse.project(correspondence.destinationPoint);
        image.drawLine(
          canvas,
          x1: observed.x.round(),
          y1: observed.y.round(),
          x2: predicted.x.round(),
          y2: predicted.y.round(),
          color: image.ColorRgb8(255, 64, 64),
          thickness: 3,
        );
        image.drawCircle(
          canvas,
          x: observed.x.round(),
          y: observed.y.round(),
          radius: 8,
          color: image.ColorRgb8(255, 230, 0),
        );
        image.drawCircle(
          canvas,
          x: predicted.x.round(),
          y: predicted.y.round(),
          radius: 5,
          color: image.ColorRgb8(0, 255, 255),
        );
        image.drawString(
          canvas,
          '${correspondence.markerId}:${correspondence.sourceCorner.name} ${observed.distanceTo(predicted).toStringAsFixed(1)}px',
          font: image.arial14,
          x: observed.x.round() + 10,
          y: observed.y.round() + 10,
          color: image.ColorRgb8(255, 255, 255),
        );
      }
    } else {
      for (final marker in bundle.page.markerRegions) {
        final bounds = marker.normalizedMarkerBounds;
        final canonicalCorners = [
          ImagePoint(
            bounds.left.value * bundle.page.canonicalPageSpec.widthPixels,
            bounds.top.value * bundle.page.canonicalPageSpec.heightPixels,
          ),
          ImagePoint(
            bounds.right.value * bundle.page.canonicalPageSpec.widthPixels,
            bounds.top.value * bundle.page.canonicalPageSpec.heightPixels,
          ),
          ImagePoint(
            bounds.right.value * bundle.page.canonicalPageSpec.widthPixels,
            bounds.bottom.value * bundle.page.canonicalPageSpec.heightPixels,
          ),
          ImagePoint(
            bounds.left.value * bundle.page.canonicalPageSpec.widthPixels,
            bounds.bottom.value * bundle.page.canonicalPageSpec.heightPixels,
          ),
        ];
        for (final corner in canonicalCorners) {
          final projected = inverse.project(corner);
          image.drawCircle(
            canvas,
            x: projected.x.round(),
            y: projected.y.round(),
            radius: 5,
            color: image.ColorRgb8(0, 255, 255),
          );
          image.drawString(
            canvas,
            '${marker.markerId}',
            font: image.arial14,
            x: projected.x.round() + 8,
            y: projected.y.round() + 8,
            color: image.ColorRgb8(255, 255, 255),
          );
        }
      }
    }
    for (final center in result.canonicalBubbleCenters) {
      final projected = inverse.project(center);
      image.drawCircle(
        canvas,
        x: projected.x.round(),
        y: projected.y.round(),
        radius: 4,
        color: image.ColorRgb8(0, 255, 80),
      );
    }
    final path =
        '${directory.path}${Platform.pathSeparator}${label}_$method.png';
    File(path).writeAsBytesSync(image.encodePng(canvas));
    overlays.add(path);
  }

  void renderIfProjectable(String method, HomographyMatrix homography) {
    try {
      render(method, homography);
    } on StateError {
      // Rejected numerical estimates remain in JSON but cannot safely produce
      // source-space projections.
    }
  }

  if (result.legacyFourPoint.valueOrNull?.homography case final homography?) {
    renderIfProjectable('legacy_four_point', homography);
  }
  if (result.currentFourPointCandidate.valueOrNull?.homography
      case final homography?) {
    renderIfProjectable('current_four_point', homography);
  }
  if (result.currentMultiPointCandidate.valueOrNull?.homography
      case final homography?) {
    renderIfProjectable('current_16_point_ransac', homography);
  }
  if (result.productionSelection.isSuccess) {
    renderIfProjectable(
      'production_selected',
      result.productionSelection.value.homography,
    );
  }
  return overlays;
}

Map<String, Object?> _candidate(
  HomographyCandidateReplay value,
  FailedScanReplayBundle bundle,
  List<BubbleGroundTruthAnnotation> groundTruth,
) => {
  'estimated': true,
  'method': value.candidate.method.name,
  'homography': value.homography?.values,
  'accepted': value.candidate.accepted,
  'acceptance': value.candidate.acceptance.name,
  'rejectionReason': value.candidate.rejectionReason,
  'geometryFailure': value.candidate.geometryValidationFailure,
  'residuals': value.candidate.commonReprojectionErrors,
  'inlierMask': value.candidate.inlierMask,
  'inliersPerMarker': value.candidate.inliersPerMarker,
  'inlierRatio': value.candidate.inlierRatio,
  'selectedForWarp': value.selectedForWarp,
  'actualSelectionReason': value.actualSelectionReason,
  'actualFallbackReason': value.actualFallbackReason,
  'estimationStatus': value.failureAttempt?.estimationStatus.name,
  'validationStatus': value.failureAttempt?.validationStatus.name,
  'effectiveThresholds': value.failureAttempt == null
      ? null
      : {
          'reprojectionPixels':
              value.failureAttempt!.effectiveReprojectionThresholdPixels,
          'ransacPixels': value.failureAttempt!.effectiveRansacThresholdPixels,
          'rejectedCornerPixels':
              value.failureAttempt!.effectiveRejectedCornerThresholdPixels,
        },
  'durationMs': value.candidate.duration.inMicroseconds / 1000,
  'bubbleEvidence': _evidence(value.bubbleEvidence),
  'groundTruth': value.homography == null
      ? null
      : _groundTruth(bundle, value.homography!, groundTruth),
};

Map<String, Object?> _groundTruth(
  FailedScanReplayBundle bundle,
  HomographyMatrix homography,
  List<BubbleGroundTruthAnnotation> annotations,
) {
  if (annotations.isEmpty) {
    return const {'status': 'ACCURACY_UNVERIFIED_NO_GROUND_TRUTH'};
  }
  final value = const BubbleAlignmentGroundTruthEvaluator().evaluate(
    page: bundle.page,
    homography: homography,
    annotations: annotations,
  );
  return {
    'units': 'canonical pixels',
    'complete': value.complete,
    'missingTargets': value.missingTargets,
    'meanDisplacement': value.mean,
    'medianDisplacement': value.median,
    'p95Displacement': value.percentile95,
    'maximumDisplacement': value.maximum,
    'regionalMeanDisplacement': value.regionalMeanDisplacementPixels,
  };
}

Map<String, Object?> _scanOmr(
  FailedScanReplayBundle bundle,
  ArucoAlignmentConfig alignment,
  PhysicalValidationPlan? expected,
) {
  final backend = OpenCvArucoVisionBackend();
  try {
    final result =
        OfflineScannerComposition.create(
          alignmentBackend: backend,
          preprocessingBackend: const OpenCvPreprocessingBackend(),
        ).scan(
          encodedImage: bundle.encodedImage,
          template: bundle.template,
          pageLayout: bundle.page,
          config: _withAlignment(bundle.scannerConfig, alignment),
        );
    if (result.isFailure) return _error(result.error);
    if (expected == null) {
      return {
        'accepted': true,
        'correctness': 'OMR_CORRECTNESS_UNVERIFIED',
        'states': [
          for (final question in result.value.questions) question.state.name,
        ],
      };
    }
    final report = PhysicalValidationReport.record(
      plan: expected,
      results: [result.value],
    );
    return {'accepted': true, 'correctness': report.toJson()};
  } finally {
    backend.dispose();
  }
}

Map<String, Object?>? _evidence(BubbleAlignmentEvidence? value) => value == null
    ? null
    : {
        'status': value.status.name,
        'reason': value.inconclusiveReason,
        'meanCenterDisplacementPixels': value.meanCenterDisplacementPixels,
        'p95CenterDisplacementPixels':
            value.percentile95CenterDisplacementPixels,
        'meanRadiusErrorPixels': value.meanRadiusErrorPixels,
        'meanRingContrast': value.meanRingContrast,
        'observedCoverage': value.observedCoverage,
        'confidenceScore': value.confidenceScore,
        'regionalMeanDisplacementPixels': value.regionalMeanDisplacementPixels,
      };

Map<String, Object?> _error(Object error) => error is EngineError
    ? {
        'accepted': false,
        'errorCode': error.code,
        'message': error.message,
        'details': error.details,
      }
    : {'accepted': false, 'error': '$error'};

Map<String, int>? _size(dynamic value) => value == null
    ? null
    : {'width': value.width as int, 'height': value.height as int};

ArucoAlignmentConfig _withMultipoint(ArucoAlignmentConfig value, bool enabled) {
  final encoded = const ScannerConfigCodec().encode(
    ScannerConfig(alignment: value),
  );
  final alignment = (encoded['alignment'] as Map).cast<String, Object?>();
  alignment['enableMultipointHomography'] = enabled;
  return const ScannerConfigCodec().decode(encoded).alignment;
}

ArucoAlignmentConfig _withDetectionLimit(
  ArucoAlignmentConfig value,
  int? limit,
) {
  final encoded = const ScannerConfigCodec().encode(
    ScannerConfig(alignment: value),
  );
  final alignment = (encoded['alignment'] as Map).cast<String, Object?>();
  alignment['finalMarkerDetectionMaxDimension'] = limit;
  return const ScannerConfigCodec().decode(encoded).alignment;
}

ArucoAlignmentConfig _withSelectionPolicy(
  ArucoAlignmentConfig value,
  HomographySelectionPolicy policy,
) {
  final encoded = const ScannerConfigCodec().encode(
    ScannerConfig(alignment: value),
  );
  final alignment = (encoded['alignment'] as Map).cast<String, Object?>();
  alignment['selectionPolicy'] = policy.name;
  return const ScannerConfigCodec().decode(encoded).alignment;
}

ScannerConfig _withAlignment(
  ScannerConfig original,
  ArucoAlignmentConfig alignment,
) {
  final encoded = const ScannerConfigCodec().encode(original);
  encoded['alignment'] = const ScannerConfigCodec().encode(
    ScannerConfig(alignment: alignment),
  )['alignment'];
  return const ScannerConfigCodec().decode(encoded);
}

List<BubbleGroundTruthAnnotation> _loadGroundTruth(String path) {
  final decoded = jsonDecode(File(path).readAsStringSync());
  final list = decoded is List
      ? decoded
      : (decoded as Map)['annotations'] as List;
  return [
    for (final value in list)
      BubbleGroundTruthAnnotation.fromJson(
        (value as Map).cast<String, Object?>(),
      ),
  ];
}

final class _Arguments {
  const _Arguments({
    this.bundlePath,
    this.groundTruthPath,
    this.expectedAnswersPath,
    this.outputDirectory,
    required this.pdfMaximumErrorPixels,
    required this.json,
    required this.compareResolution,
    required this.verbose,
  });

  final String? bundlePath;
  final String? groundTruthPath;
  final String? expectedAnswersPath;
  final String? outputDirectory;
  final double pdfMaximumErrorPixels;
  final bool json;
  final bool compareResolution;
  final bool verbose;

  factory _Arguments.parse(List<String> values) {
    String? bundle;
    String? groundTruth;
    String? expectedAnswers;
    String? outputDirectory;
    var pdfMaximumErrorPixels = 3.0;
    for (var index = 0; index < values.length; index++) {
      if (values[index] == '--bundle' && index + 1 < values.length) {
        bundle = values[++index];
      } else if (values[index] == '--ground-truth' &&
          index + 1 < values.length) {
        groundTruth = values[++index];
      } else if (values[index] == '--expected-answers' &&
          index + 1 < values.length) {
        expectedAnswers = values[++index];
      } else if (values[index] == '--output-dir' && index + 1 < values.length) {
        outputDirectory = values[++index];
      } else if (values[index] == '--pdf-max-error' &&
          index + 1 < values.length) {
        pdfMaximumErrorPixels = double.parse(values[++index]);
      }
    }
    return _Arguments(
      bundlePath: bundle,
      groundTruthPath: groundTruth,
      expectedAnswersPath: expectedAnswers,
      outputDirectory: outputDirectory,
      pdfMaximumErrorPixels: pdfMaximumErrorPixels,
      json: values.contains('--json'),
      compareResolution: values.contains('--compare-resolution'),
      verbose: values.contains('--verbose'),
    );
  }
}
