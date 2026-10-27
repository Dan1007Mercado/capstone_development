// Dedicated P15.6 replay experiment; never called by production scanning.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:capstone_development/application/published_templates/published_template_artifact_codec.dart';
import 'package:capstone_development/application/real_scanner/scan_acceptance_policy.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/engines/aruco/application/aruco_capture_replay_harness.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_alignment_config.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_detector_profile.dart';
import 'package:capstone_development/engines/aruco/infrastructure/opencv_aruco_detector.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/infrastructure/opencv_aruco_vision_backend.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessing_backend.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessing_config.dart';
import 'package:capstone_development/engines/preprocessing/infrastructure/opencv_preprocessing_backend.dart';
import 'package:capstone_development/engines/preprocessing/infrastructure/dart_image_preprocessing_backend.dart';
import 'package:capstone_development/engines/recognition/application/bubble_alignment_evidence.dart';
import 'package:capstone_development/engines/scanner/application/offline_scanner_engine.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_config.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_diagnostic_snapshot.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_stages.dart';
import 'package:capstone_development/engines/scanner/infrastructure/offline_scanner_composition.dart';

void main(List<String> args) {
  final input = Directory(args[0]);
  final output = Directory(args[1])..createSync(recursive: true);
  final fullResolution = args.contains('full-resolution');
  final noRefinement = args.contains('no-refinement');
  try {
    final manifestText = File(
      '${input.path}/published_manifest.json',
    ).readAsStringSync();
    final manifest = jsonDecode(manifestText) as Map<String, dynamic>;
    final encoded = (manifest['artifact'] as Map).cast<String, Object?>();
    final hash = sha256.convert(utf8.encode(jsonEncode(encoded))).toString();
    if (hash != manifest['artifactSha256']) {
      throw StateError('Artifact hash mismatch');
    }
    final artifact = const PublishedTemplateArtifactCodec().decode(encoded);
    final page = artifact.layout.pages.single;
    final files =
        Directory('${input.path}/images')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.jpg'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final inputs = <Map<String, Object?>>[];
    File(
      '${output.path}/native_parity.json',
    ).writeAsStringSync(jsonEncode(_nativeParity()));
    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final bytes = file.readAsBytesSync();
      final decoded = image.decodeJpg(bytes)!;
      inputs.add({
        'file': name,
        'sha256': sha256.convert(bytes).toString(),
        'width': decoded.width,
        'height': decoded.height,
        'captureTimestamp': decoded.exif.exifIfd[0x9003]?.toString(),
        'captureOffset': decoded.exif.exifIfd[0x9011]?.toString(),
        'orientation': decoded.exif.imageIfd[0x0112]?.toString(),
        'templateId': artifact.template.id.value,
        'version': artifact.template.version.value,
      });
      final replay =
          ArucoCaptureReplayHarness(
            backendFactory: () => OpenCvArucoVisionBackend(
              detector: OpenCvArucoDetector(
                profile: ArucoDetectorProfile(
                  cornerRefinement: noRefinement
                      ? ArucoCornerRefinement.none
                      : ArucoCornerRefinement.subpixel,
                ),
              ),
            ),
            disposeBackend: (b) => (b as OpenCvArucoVisionBackend).dispose(),
          ).run(
            bytes,
            page,
            legacyConfig: ArucoAlignmentConfig(
              enableMultipointHomography: false,
              finalMarkerDetectionMaxDimension: fullResolution ? null : 1400,
            ),
            currentFourPointConfig: ArucoAlignmentConfig(
              enableMultipointHomography: false,
              finalMarkerDetectionMaxDimension: fullResolution ? null : 1400,
            ),
            currentMultiPointConfig: ArucoAlignmentConfig(
              selectionPolicy:
                  HomographySelectionPolicy.validatedMultiPointPreference,
              finalMarkerDetectionMaxDimension: fullResolution ? null : 1400,
            ),
            productionConfig: ArucoAlignmentConfig(
              finalMarkerDetectionMaxDimension: fullResolution ? null : 1400,
            ),
          );
      final report = <String, Object?>{
        'input': inputs.last,
        'artifactSha256': hash,
        'fullResolutionDetection': fullResolution,
        'noCornerRefinement': noRefinement,
        'multiPointEstimate': replay.currentMultiPointCandidate.isSuccess
            ? {
                'homography':
                    replay.currentMultiPointCandidate.value.homography?.values,
                'accepted':
                    replay.currentMultiPointCandidate.value.candidate.accepted,
                'rejection': replay
                    .currentMultiPointCandidate
                    .value
                    .candidate
                    .rejectionReason,
              }
            : {'error': replay.currentMultiPointCandidate.error.toString()},
        'fourPoint': {},
        'multiPointPreference': {},
        'production': replay.productionSelection.isSuccess
            ? {
                'method': replay
                    .productionSelection
                    .value
                    .diagnostics
                    .selectedHomographyMethod
                    .name,
                'alignmentMs':
                    replay
                        .productionSelection
                        .value
                        .diagnostics
                        .processingDuration
                        .inMicroseconds /
                    1000,
                'homography':
                    replay.productionSelection.value.homography.values,
              }
            : {'error': replay.productionSelection.error.toString()},
      };
      for (final entry in {
        'fourPoint': replay.currentFourPointSelection,
        'multiPointPreference': replay.currentMultiPointSelection,
      }.entries) {
        if (entry.value.isFailure) {
          report[entry.key] = {
            'error': entry.value.error.toString(),
            'details': entry.value.error.details,
          };
          continue;
        }
        final alignment = entry.value.value;
        final observed = _ObservedPreprocessing();
        final backend = OpenCvArucoVisionBackend();
        try {
          final stages = OfflineScannerComposition.create(
            refineBubbleRegistration: false,
            alignmentBackend: backend,
            preprocessingBackend: observed,
          );
          final scanner = OfflineScannerEngine(
            alignment: _FixedAlignment(alignment),
            preprocessing: stages.preprocessing,
            measurement: stages.measurement,
            classification: stages.classification,
          );
          ScannerDiagnosticSnapshot? snapshot;
          final result = scanner.scan(
            encodedImage: bytes,
            template: artifact.template,
            pageLayout: page,
            config: ScannerConfig(),
            diagnosticSink: (s) => snapshot = s,
          );
          if (result.isFailure) {
            report[entry.key] = {
              'error': result.error.toString(),
              'details': result.error.details,
            };
            continue;
          }
          final s = snapshot!;
          final evidence = const BubbleAlignmentEvidenceEvaluator().evaluate(
            alignment.canonicalPage,
            page,
          );
          final timing = result.value.diagnostics.preprocessing.stageDurations;
          report[entry.key] = {
            'snapshot': s.toJson(),
            'bufferHashes': {
              'canonical': sha256.convert(s.canonicalImageBytes).toString(),
              'normalized': sha256
                  .convert(observed.output!.normalizedGrayscale.pixels)
                  .toString(),
              'binary': sha256
                  .convert(observed.output!.binary.pixels)
                  .toString(),
            },
            'detectedMarkers': [
              for (final marker in alignment.detectedMarkers)
                {
                  'id': marker.id,
                  'corners': [
                    for (final point in marker.corners)
                      {'x': point.x, 'y': point.y},
                  ],
                },
            ],
            'alignmentMs':
                alignment.diagnostics.processingDuration.inMicroseconds / 1000,
            'downstreamOnlyMs':
                result
                    .value
                    .diagnostics
                    .totalProcessingDuration
                    .inMicroseconds /
                1000,
            'acceptance': const ScanAcceptancePolicy()
                .evaluate(result.value)
                .decision
                .name,
            'preprocessingMs': {
              'denoise': timing.denoise.inMicroseconds / 1000,
              'normalization':
                  timing.illuminationNormalization.inMicroseconds / 1000,
              'threshold': timing.thresholding.inMicroseconds / 1000,
              'statistics': timing.statistics.inMicroseconds / 1000,
            },
            'selectedAnswers': [
              for (final q in result.value.questions)
                {
                  'number': q.questionNumber,
                  'state': q.state.name,
                  'options': q.selectedOptionIds.map((id) => id.value).toList(),
                },
            ],
            'outlineEvidence': {
              'status': evidence.status.name,
              'meanDisplacement': evidence.meanCenterDisplacementPixels,
              'p95Displacement': evidence.percentile95CenterDisplacementPixels,
              'regional': evidence.regionalMeanDisplacementPixels,
              'observations': [
                for (final o in evidence.observations)
                  {
                    'question': o.questionId,
                    'target': o.targetLabel,
                    'expectedX': o.expectedCenterX,
                    'expectedY': o.expectedCenterY,
                    'observedX': o.observedCenterX,
                    'observedY': o.observedCenterY,
                    'radius': o.observedRadiusPixels,
                    'displacement': o.centerDisplacementPixels,
                    'confident': o.confident,
                    'contrast': o.ringContrast,
                  },
              ],
            },
          };
          final prefix = '${output.path}/${name}_${entry.key}';
          _writeImages(prefix, s, observed.output!);
          if (name == 'unmarked.jpg' && entry.key == 'fourPoint') {
            report['inputTransferExperiment'] = _transferExperiment(s);
          }
        } finally {
          backend.dispose();
        }
      }
      File(
        '${output.path}/$name.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
      stdout.writeln('P156_DONE $name');
    }
    File(
      '${output.path}/inputs.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(inputs));
    File(
      '${output.path}/DONE',
    ).writeAsStringSync('Native replay completed; see per-image reports.');
  } on Object catch (error, stack) {
    File('${output.path}/ERROR').writeAsStringSync('$error\n$stack');
    rethrow;
  }
}

Map<String, Object?> _nativeParity() {
  final owner = Uint8List.fromList(List.generate(90, (i) => i * 17 % 256));
  final bytes = Uint8List.sublistView(owner, 3, 80);
  final canonical = CanonicalPageImage.ownedGrayscale(
    size: ImageSize(width: 7, height: 11),
    grayscaleBytes: bytes,
  );
  final results = <Map<String, Object?>>[];
  for (final config in const [
    PreprocessingConfig(minimumIntensityStdDev: 0),
    PreprocessingConfig(
      enableDenoise: false,
      enableIlluminationNormalization: false,
      minimumIntensityStdDev: 0,
    ),
  ]) {
    final native = const OpenCvPreprocessingBackend()
        .process(canonical, config)
        .value;
    final reference = const DartImagePreprocessingBackend()
        .process(canonical, config)
        .value;
    var maxDifference = 0;
    var binaryDifferences = 0;
    for (var i = 0; i < bytes.length; i++) {
      final difference =
          (native.normalizedGrayscale.pixels[i] -
                  reference.normalizedGrayscale.pixels[i])
              .abs();
      if (difference > maxDifference) {
        maxDifference = difference;
      }
      if (native.binary.pixels[i] != reference.binary.pixels[i]) {
        binaryDifferences++;
      }
    }
    if (maxDifference > 1 || binaryDifferences != 0) {
      throw StateError('Native parity failed');
    }
    results.add({
      'normalization': config.enableIlluminationNormalization,
      'maximumNormalizedDifference': maxDifference,
      'binaryDifferences': binaryDifferences,
    });
  }
  return {
    'passed': true,
    'width': 7,
    'height': 11,
    'ownerOffset': 3,
    'cases': results,
  };
}

List<Map<String, Object?>> _transferExperiment(ScannerDiagnosticSnapshot s) {
  final samples = <Map<String, Object?>>[];
  for (var repeat = 0; repeat < 5; repeat++) {
    final timer = Stopwatch()..start();
    final first = cv.Mat.fromList(
      s.canonicalSize.height,
      s.canonicalSize.width,
      cv.MatType.CV_8UC1,
      s.canonicalImageBytes,
    );
    timer.stop();
    final fromListMs = timer.elapsedMicroseconds / 1000;
    timer.reset();
    timer.start();
    final vector = cv.VecU8.fromList(s.canonicalImageBytes);
    final second = cv.Mat.fromVec(
      vector,
      rows: s.canonicalSize.height,
      cols: s.canonicalSize.width,
      type: cv.MatType.CV_8UC1,
    );
    vector.dispose();
    timer.stop();
    final firstHash = sha256.convert(first.data).toString();
    final secondHash = sha256.convert(second.data).toString();
    samples.add({
      'fromListMs': fromListMs,
      'typedVectorMs': timer.elapsedMicroseconds / 1000,
      'equal': firstHash == secondHash,
      'sha256': firstHash,
    });
    first.dispose();
    second.dispose();
  }
  return samples;
}

void _writeImages(
  String prefix,
  ScannerDiagnosticSnapshot s,
  BackendPreprocessingOutput p,
) {
  image.Image gray(Uint8List bytes) => image.Image.fromBytes(
    width: s.canonicalSize.width,
    height: s.canonicalSize.height,
    bytes: bytes.buffer,
    numChannels: 1,
  );
  final raw = gray(s.canonicalImageBytes);
  final normalized = gray(p.normalizedGrayscale.pixels);
  final binaryBytes = Uint8List.fromList(
    p.binary.pixels.map((v) => v == 1 ? 0 : 255).toList(),
  );
  final binary = gray(binaryBytes);
  for (final entry in {
    'canonical': raw,
    'normalized': normalized,
    'binary': binary,
  }.entries) {
    File(
      '${prefix}_${entry.key}.png',
    ).writeAsBytesSync(image.encodePng(entry.value));
  }
  final overlay = raw.convert(numChannels: 3);
  final mask = binary.convert(numChannels: 3);
  for (final m in s.measurements.measurements) {
    final roi = m.roi;
    for (final spec in [
      (roi.printedRadius, image.ColorRgb8(255, 0, 0)),
      (roi.interiorRadius, image.ColorRgb8(0, 255, 0)),
      (roi.centerExclusionRadius, image.ColorRgb8(255, 0, 255)),
      (roi.baselineOuterRadius, image.ColorRgb8(0, 180, 255)),
    ]) {
      image.drawCircle(
        overlay,
        x: roi.center.x.round(),
        y: roi.center.y.round(),
        radius: spec.$1.round(),
        color: spec.$2,
      );
    }
    for (
      var y = (roi.center.y - roi.interiorRadius - 1).floor();
      y <= (roi.center.y + roi.interiorRadius + 1).ceil();
      y++
    ) {
      for (
        var x = (roi.center.x - roi.interiorRadius - 1).floor();
        x <= (roi.center.x + roi.interiorRadius + 1).ceil();
        x++
      ) {
        if (roi.containsInteriorPixel(x, y)) {
          mask.setPixelRgb(
            x,
            y,
            p.binary.at(x, y) ? 255 : 0,
            p.binary.at(x, y) ? 0 : 140,
            80,
          );
        }
      }
    }
  }
  File('${prefix}_roi.png').writeAsBytesSync(image.encodePng(overlay));
  File('${prefix}_sampled_pixels.png').writeAsBytesSync(image.encodePng(mask));
}

final class _ObservedPreprocessing implements PreprocessingBackend {
  BackendPreprocessingOutput? output;
  @override
  EngineResult<BackendPreprocessingOutput> process(
    CanonicalPageImage page,
    PreprocessingConfig config,
  ) {
    final result = const OpenCvPreprocessingBackend().process(page, config);
    output = result.valueOrNull;
    return result;
  }
}

final class _FixedAlignment implements ScannerAlignmentStage {
  const _FixedAlignment(this.result);
  final PageAlignmentResult result;
  @override
  EngineResult<PageAlignmentResult> align(
    Uint8List bytes,
    PageLayout page,
    ArucoAlignmentConfig config,
  ) => EngineResult.success(result);
}
