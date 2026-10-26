import 'dart:convert';
import 'dart:io';

import 'package:capstone_development/application/real_scanner/failed_scan_replay_bundle.dart';
import 'package:capstone_development/application/real_scanner/physical_validation_recorder.dart';
import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/engines/aruco/application/aruco_capture_replay_harness.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_alignment_config.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/aruco/infrastructure/opencv_aruco_vision_backend.dart';
import 'package:capstone_development/engines/recognition/application/bubble_alignment_evidence.dart';
import 'package:capstone_development/engines/recognition/application/bubble_alignment_ground_truth.dart';
import 'package:capstone_development/engines/preprocessing/infrastructure/opencv_preprocessing_backend.dart';
import 'package:capstone_development/engines/scanner/infrastructure/offline_scanner_composition.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config_codec.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config.dart';

void main(List<String> arguments) {
  final parsed = _Arguments.parse(arguments);
  if (parsed.bundlePath == null) {
    stderr.writeln(
      'Usage: dart run tool/replay_failed_scan.dart --bundle <capture.zip> '
      '[--json] [--compare-resolution] '
      '[--ground-truth annotations.json] '
      '[--expected-answers answers.json]',
    );
    exitCode = 64;
    return;
  }
  try {
    final bundleBytes = File(parsed.bundlePath!).readAsBytesSync();
    final bundle = const FailedScanReplayBundleCodec().decode(bundleBytes);
    final baseConfig = bundle.scannerConfig.alignment;
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
    final report = <String, Object?>{
      'bundle': {
        'templateId': bundle.template.id.value,
        'templateVersion': bundle.template.version.value,
        'pageId': bundle.pageId.value,
        'capturedAtUtc': bundle.capturedAtUtc.toIso8601String(),
        'originalFailure': bundle.failure.code,
      },
      'runs': [
        _run(
          bundle,
          baseConfig,
          label: 'recorded-config',
          groundTruth: groundTruth,
          expected: expected,
        ),
        if (parsed.compareResolution)
          _run(
            bundle,
            _withDetectionLimit(baseConfig, null),
            label: 'full-resolution',
            groundTruth: groundTruth,
            expected: expected,
          ),
      ],
    };
    stdout.writeln(
      parsed.json
          ? jsonEncode(report)
          : const JsonEncoder.withIndent('  ').convert(report),
    );
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

Map<String, Object?> _run(
  FailedScanReplayBundle bundle,
  ArucoAlignmentConfig config, {
  required String label,
  required List<BubbleGroundTruthAnnotation> groundTruth,
  required PhysicalValidationPlan? expected,
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
        currentMultiPointConfig: config,
      );
  final production = result.productionSelection;
  if (production.isFailure &&
      production.error.code == 'ARUCO_BACKEND_UNAVAILABLE') {
    throw StateError('${production.error.code}: ${production.error.message}');
  }
  final omr = _scanOmr(bundle, config, expected);
  return {
    'label': label,
    'detectionMaxDimension': config.finalMarkerDetectionMaxDimension,
    'A_legacyFourPoint': result.legacyFourPoint.isSuccess
        ? {
            'acceptedByLegacyFittingGate':
                result.legacyFourPoint.value.acceptedByLegacyFittingGate,
            'geometryFailure':
                result.legacyFourPoint.value.geometryValidationFailure,
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
  };
}

Map<String, Object?> _candidate(
  HomographyCandidateReplay value,
  FailedScanReplayBundle bundle,
  List<BubbleGroundTruthAnnotation> groundTruth,
) => {
  'estimated': true,
  'method': value.candidate.method.name,
  'accepted': value.candidate.accepted,
  'rejectionReason': value.candidate.rejectionReason,
  'geometryFailure': value.candidate.geometryValidationFailure,
  'residuals': value.candidate.commonReprojectionErrors,
  'inlierMask': value.candidate.inlierMask,
  'inliersPerMarker': value.candidate.inliersPerMarker,
  'inlierRatio': value.candidate.inlierRatio,
  'selectedForWarp': value.selectedForWarp,
  'actualSelectionReason': value.actualSelectionReason,
  'actualFallbackReason': value.actualFallbackReason,
  'durationMs': value.candidate.duration.inMicroseconds / 1000,
  'bubbleEvidence': _evidence(value.bubbleEvidence),
  'groundTruth': value.homography == null
      ? null
      : _groundTruth(bundle, value.homography!, groundTruth),
};

Map<String, Object?>? _groundTruth(
  FailedScanReplayBundle bundle,
  HomographyMatrix homography,
  List<BubbleGroundTruthAnnotation> annotations,
) {
  if (annotations.isEmpty) return null;
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
        'correctness': 'UNVERIFIED_NO_EXPECTED_ANSWERS',
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
    required this.json,
    required this.compareResolution,
    required this.verbose,
  });

  final String? bundlePath;
  final String? groundTruthPath;
  final String? expectedAnswersPath;
  final bool json;
  final bool compareResolution;
  final bool verbose;

  factory _Arguments.parse(List<String> values) {
    String? bundle;
    String? groundTruth;
    String? expectedAnswers;
    for (var index = 0; index < values.length; index++) {
      if (values[index] == '--bundle' && index + 1 < values.length) {
        bundle = values[++index];
      } else if (values[index] == '--ground-truth' &&
          index + 1 < values.length) {
        groundTruth = values[++index];
      } else if (values[index] == '--expected-answers' &&
          index + 1 < values.length) {
        expectedAnswers = values[++index];
      }
    }
    return _Arguments(
      bundlePath: bundle,
      groundTruthPath: groundTruth,
      expectedAnswersPath: expectedAnswers,
      json: values.contains('--json'),
      compareResolution: values.contains('--compare-resolution'),
      verbose: values.contains('--verbose'),
    );
  }
}
