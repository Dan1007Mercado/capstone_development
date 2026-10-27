import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;

import '../application/real_scanner/failed_scan_replay_bundle.dart';
import '../core/errors/engine_error.dart';
import '../engines/aruco/application/aruco_capture_replay_harness.dart';
import '../engines/aruco/domain/alignment_failure_diagnostics.dart';
import '../engines/aruco/domain/aruco_alignment_config.dart';
import '../engines/aruco/domain/image_geometry.dart';
import '../engines/aruco/domain/page_alignment_result.dart';
import '../engines/aruco/infrastructure/opencv_aruco_vision_backend.dart';
import '../engines/preprocessing/infrastructure/opencv_preprocessing_backend.dart';
import '../engines/recognition/application/bubble_alignment_evidence.dart';
import '../engines/scanner/infrastructure/offline_scanner_composition.dart';
import '../engines/scanner/domain/scanner_config.dart';
import '../engines/scanner/domain/scanner_config_codec.dart';

typedef FailedScanReplayExecutor =
    Future<FailedScanReplayOutput> Function(Uint8List bundleBytes);

final class FailedScanReplayOutput {
  const FailedScanReplayOutput({
    required this.reportJson,
    required this.exportZip,
    required this.summaries,
  });

  final String reportJson;
  final Uint8List exportZip;
  final List<String> summaries;
}

Future<FailedScanReplayOutput> runFailedScanReplay(
  Uint8List bundleBytes,
) async {
  final output = await compute(_runReplayWorker, bundleBytes);
  return FailedScanReplayOutput(
    reportJson: output['reportJson']! as String,
    exportZip: output['exportZip']! as Uint8List,
    summaries: (output['summaries']! as List).cast<String>(),
  );
}

Map<String, Object?> _runReplayWorker(Uint8List bundleBytes) {
  final bundle = const FailedScanReplayBundleCodec().decode(bundleBytes);
  final recorded = _runOne(
    bundle,
    bundle.scannerConfig.alignment,
    label: 'recorded-resolution',
  );
  final full = _runOne(
    bundle,
    _withDetectionLimit(bundle.scannerConfig.alignment, null),
    label: 'full-resolution',
  );
  final overlays = <String, Uint8List>{...recorded.overlays, ...full.overlays};
  final report = <String, Object?>{
    'schemaVersion': 1,
    'bundle': {
      'templateId': bundle.template.id.value,
      'templateVersion': bundle.template.version.value,
      'pageId': bundle.pageId.value,
      'capturedAtUtc': bundle.capturedAtUtc.toIso8601String(),
      'originalFailure': {
        'code': bundle.failure.code,
        'message': bundle.failure.message,
        'details': bundle.failure.details,
      },
    },
    'runs': [recorded.report, full.report],
    'export': {
      'capturedImageIncluded': false,
      'overlayFiles': overlays.keys.toList(growable: false),
    },
  };
  final reportJson = const JsonEncoder.withIndent('  ').convert(report);
  final archive = Archive()
    ..addFile(ArchiveFile.string('replay_report.json', reportJson));
  for (final entry in overlays.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  final zip = ZipEncoder().encode(archive);
  if (zip == null) throw StateError('Unable to encode replay diagnostics ZIP.');
  final summaries = [recorded.summary, full.summary];
  debugPrint('Failed-scan replay: ${summaries.join(' | ')}');
  return {
    'reportJson': reportJson,
    'exportZip': Uint8List.fromList(zip),
    'summaries': summaries,
  };
}

_ReplayRun _runOne(
  FailedScanReplayBundle bundle,
  ArucoAlignmentConfig config, {
  required String label,
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
  final four = result.currentFourPointCandidate.valueOrNull;
  final multi = result.currentMultiPointCandidate.valueOrNull;
  final overlays = _renderOverlays(bundle, result, label);
  final omr = _scanOmr(bundle, config);
  final productionFailure = production.isFailure
      ? AlignmentFailureDiagnostics.findInDetails(production.error.details)
      : null;
  final report = <String, Object?>{
    'label': label,
    'detectionMaxDimension': config.finalMarkerDetectionMaxDimension,
    'legacyFourPointDiagnostic': result.legacyFourPoint.isSuccess
        ? {
            'acceptedByLegacyFittingGate':
                result.legacyFourPoint.value.acceptedByLegacyFittingGate,
            'homography': result.legacyFourPoint.value.homography.values,
            'fittingResiduals': result.legacyFourPoint.value.fittingResiduals,
            'allCornerResiduals':
                result.legacyFourPoint.value.allCornerResiduals,
            'geometryFailure':
                result.legacyFourPoint.value.geometryValidationFailure,
          }
        : _error(result.legacyFourPoint.error),
    'fourPointCandidate': four == null
        ? _error(result.currentFourPointCandidate.error)
        : _candidate(four),
    'multiPointCandidate': multi == null
        ? _error(result.currentMultiPointCandidate.error)
        : _candidate(multi),
    'productionSelection': production.isSuccess
        ? {
            'accepted': true,
            'selectedMethod':
                production.value.diagnostics.selectedHomographyMethod.name,
            'selectionReason': production.value.diagnostics.selectionReason,
            'fallbackReason': production.value.diagnostics.fallbackReason,
            'homography': production.value.homography.values,
            'sourceSize': _size(production.value.diagnostics.sourceSize),
            'detectionSize': _size(production.value.diagnostics.detectionSize),
            'detectionScaleX': production.value.diagnostics.detectionScaleX,
            'detectionScaleY': production.value.diagnostics.detectionScaleY,
          }
        : {
            ..._error(production.error),
            'alignmentFailureDiagnostics': productionFailure?.toMap(),
          },
    'productionOmr': omr,
    'overlays': overlays.keys.toList(growable: false),
  };
  String disposition(HomographyCandidateReplay? value) => value == null
      ? 'unavailable'
      : value.candidate.accepted
      ? 'accepted'
      : 'rejected:${value.candidate.rejectionReason ?? 'unspecified'}';
  return _ReplayRun(
    report: report,
    overlays: overlays,
    summary:
        '$label four=${disposition(four)}, multi=${disposition(multi)}, '
        'production=${production.isSuccess ? 'accepted' : production.error.code}, '
        'omr=${omr['accepted'] == true ? omr['pageState'] : omr['errorCode']}',
  );
}

Map<String, Object?> _scanOmr(
  FailedScanReplayBundle bundle,
  ArucoAlignmentConfig alignment,
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
    final scan = result.value;
    return {
      'accepted': true,
      'correctness': 'OMR_CORRECTNESS_UNVERIFIED_NO_GROUND_TRUTH',
      'pageState': scan.pageState.name,
      'reviewReasons': scan.reviewReasons.map((value) => value.name).toList(),
      'summary': {
        'totalQuestions': scan.summary.totalQuestions,
        'marked': scan.summary.marked,
        'blank': scan.summary.blank,
        'multiple': scan.summary.multiple,
        'ambiguous': scan.summary.ambiguous,
        'invalid': scan.summary.invalid,
        'requiredBlank': scan.summary.requiredBlank,
        'measuredBubbles': scan.summary.measuredBubbles,
      },
      'questions': [
        for (final question in scan.questions)
          {
            'questionId': question.questionId.value,
            'questionNumber': question.questionNumber,
            'state': question.state.name,
            'selectedOptionIds': question.selectedOptionIds
                .map((value) => value.value)
                .toList(),
            'numericSelection': question.numericSelection?.completeDigitString,
            'reason': question.diagnostics.reason.name,
          },
      ],
    };
  } finally {
    backend.dispose();
  }
}

Map<String, Object?> _candidate(HomographyCandidateReplay value) => {
  'estimated': true,
  'accepted': value.candidate.accepted,
  'acceptance': value.candidate.acceptance.name,
  'method': value.candidate.method.name,
  'selectedForWarp': value.selectedForWarp,
  'homography': value.homography?.values,
  'rejectionReason': value.candidate.rejectionReason,
  'geometryFailure': value.candidate.geometryValidationFailure,
  'residuals': value.candidate.commonReprojectionErrors,
  'meanResidual': value.candidate.meanCommonReprojectionError,
  'medianResidual': value.candidate.medianCommonReprojectionError,
  'maximumResidual': value.candidate.maxCommonReprojectionError,
  'inlierMask': value.candidate.inlierMask,
  'inlierCount': value.candidate.inlierCount,
  'totalPointCount': value.candidate.totalPointCount,
  'inlierRatio': value.candidate.inlierRatio,
  'inliersPerMarker': value.candidate.inliersPerMarker,
  'actualSelectionReason': value.actualSelectionReason,
  'actualFallbackReason': value.actualFallbackReason,
  'failureAttempt': value.failureAttempt?.toMap(),
  'bubbleEvidence': _evidence(value.bubbleEvidence),
};

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

Map<String, Uint8List> _renderOverlays(
  FailedScanReplayBundle bundle,
  ArucoCaptureReplayResult result,
  String label,
) {
  final decoded = image.decodeImage(bundle.encodedImage);
  if (decoded == null) return const {};
  final overlays = <String, Uint8List>{};

  void render(String candidateName, HomographyMatrix homography) {
    final canvas = image.Image.from(decoded);
    final inverse = homography.inverse();
    for (final marker in bundle.page.markerRegions) {
      final bounds = marker.normalizedMarkerBounds;
      final projected = [
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
      ].map(inverse.project).toList(growable: false);
      for (var index = 0; index < projected.length; index++) {
        final start = projected[index];
        final end = projected[(index + 1) % projected.length];
        image.drawLine(
          canvas,
          x1: start.x.round(),
          y1: start.y.round(),
          x2: end.x.round(),
          y2: end.y.round(),
          color: image.ColorRgb8(0, 255, 255),
          thickness: 4,
        );
      }
      image.drawString(
        canvas,
        'marker ${marker.markerId}',
        font: image.arial14,
        x: projected.first.x.round() + 8,
        y: projected.first.y.round() + 8,
        color: image.ColorRgb8(255, 255, 255),
      );
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
    overlays['${label}_$candidateName.png'] = Uint8List.fromList(
      image.encodePng(canvas),
    );
  }

  void renderIfProjectable(String name, HomographyMatrix? homography) {
    if (homography == null) return;
    try {
      render(name, homography);
    } on StateError {
      // The estimate remains in JSON even when it cannot be inverted safely.
    }
  }

  renderIfProjectable(
    'four_point_projection',
    result.currentFourPointCandidate.valueOrNull?.homography,
  );
  renderIfProjectable(
    'multi_point_projection',
    result.currentMultiPointCandidate.valueOrNull?.homography,
  );
  return overlays;
}

Map<String, Object?> _error(EngineError error) => {
  'accepted': false,
  'errorCode': error.code,
  'message': error.message,
  'details': error.details,
};

Map<String, int>? _size(ImageSize? value) =>
    value == null ? null : {'width': value.width, 'height': value.height};

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

final class _ReplayRun {
  const _ReplayRun({
    required this.report,
    required this.overlays,
    required this.summary,
  });

  final Map<String, Object?> report;
  final Map<String, Uint8List> overlays;
  final String summary;
}
