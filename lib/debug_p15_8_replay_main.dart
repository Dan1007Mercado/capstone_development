// Dedicated native experiment; normal app entry point remains lib/main.dart.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'application/published_templates/published_template_artifact_codec.dart';
import 'application/real_scanner/scan_acceptance_policy.dart';
import 'engines/aruco/application/marker_correspondence_service.dart';
import 'engines/aruco/domain/aruco_alignment_config.dart';
import 'engines/aruco/domain/aruco_detector_profile.dart';
import 'engines/aruco/domain/aruco_vision_backend.dart';
import 'engines/aruco/domain/detected_marker.dart';
import 'engines/aruco/infrastructure/opencv_aruco_detector.dart';
import 'engines/aruco/infrastructure/opencv_aruco_vision_backend.dart';
import 'engines/preprocessing/infrastructure/opencv_preprocessing_backend.dart';
import 'engines/scanner/domain/scanner_config.dart';
import 'engines/scanner/domain/scanner_diagnostic_snapshot.dart';
import 'engines/scanner/infrastructure/offline_scanner_composition.dart';

const _input = '/data/user/0/com.example.capstone_development/files/p156-input';
const _output =
    '/sdcard/Android/data/com.example.capstone_development/files/p158';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Text('P15.8 matched native profile replay')),
    ),
  );
  unawaited(Isolate.run(_run));
}

void _run() {
  final output = Directory(_output)..createSync(recursive: true);
  try {
    final manifest =
        jsonDecode(File('$_input/published_manifest.json').readAsStringSync())
            as Map;
    final artifact = const PublishedTemplateArtifactCodec().decode(
      (manifest['artifact'] as Map).cast<String, Object?>(),
    );
    final hash = sha256
        .convert(utf8.encode(jsonEncode(manifest['artifact'])))
        .toString();
    if (hash != manifest['artifactSha256']) {
      throw StateError('Artifact identity mismatch');
    }
    final files =
        Directory('$_input/images')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.jpg'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (var index = 0; index < files.length; index++) {
      final file = files[index];
      final name = file.uri.pathSegments.last;
      final bytes = file.readAsBytesSync();
      final report = <String, Object?>{
        'file': name,
        'sha256': sha256.convert(bytes).toString(),
        'artifactSha256': hash,
        'buildMode': 'profile',
        'runs': <String, Object?>{},
      };
      // Counterbalance pair order; no timing claim from a debug/profile mix.
      for (final enabled in index.isEven ? [false, true] : [true, false]) {
        final backend = OpenCvArucoVisionBackend();
        try {
          final scanner = OfflineScannerComposition.create(
            alignmentBackend: backend,
            preprocessingBackend: const OpenCvPreprocessingBackend(),
            refineBubbleRegistration: enabled,
          );
          ScannerDiagnosticSnapshot? snapshot;
          final watch = Stopwatch()..start();
          final result = scanner.scan(
            encodedImage: bytes,
            template: artifact.template,
            pageLayout: artifact.layout.pages.single,
            config: ScannerConfig(),
            diagnosticSink: (s) => snapshot = s,
          );
          final run = <String, Object?>{
            'wallMs': watch.elapsedMicroseconds / 1000,
          };
          if (result.isFailure) {
            run['error'] = result.error.toString();
            run['details'] = result.error.details;
          } else {
            run['snapshot'] = snapshot!.toJson();
            run['canonicalSha256'] = sha256
                .convert(snapshot!.canonicalImageBytes)
                .toString();
            run['acceptance'] = const ScanAcceptancePolicy()
                .evaluate(result.value)
                .decision
                .name;
          }
          (report['runs'] as Map)[enabled ? 'registered' : 'baseline'] = run;
        } finally {
          backend.dispose();
        }
      }
      File(
        '${output.path}/$name.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));
    }
    final backend = OpenCvArucoVisionBackend();
    try {
      final bytes = File('$_input/images/blank_tilted.jpg').readAsBytesSync();
      final opened = backend.open(bytes, ArucoAlignmentConfig()).value;
      try {
        final detection = opened.detection;
        final duplicates = detection.markers.where((m) => m.id == 13).toList();
        final variants = <Object?>[];
        for (final keep in duplicates) {
          final filtered = ArucoDetection(
            sourceSize: detection.sourceSize,
            markers: detection.markers.where(
              (m) => m.id != 13 || identical(m, keep),
            ),
          );
          final built = const MarkerCorrespondenceService().build(
            detection: filtered,
            page: artifact.layout.pages.single,
            config: ArucoAlignmentConfig(),
          );
          final row = <String, Object?>{
            'marker13Center': [keep.center.x, keep.center.y],
          };
          if (built.isFailure) {
            row['error'] = built.error.toString();
          } else {
            final fit = opened.estimateHomography(
              sourcePoints: built.value.baselineSourcePoints,
              destinationPoints: built.value.baselineDestinationPoints,
              method: HomographyEstimationMethod.fourPoint,
              ransacReprojectionThresholdPixels: 1.5,
              maximumIterations: 2000,
              confidence: .99,
            );
            row['correspondenceValid'] = true;
            if (fit.isSuccess) row['homography'] = fit.value.homography.values;
          }
          variants.add(row);
        }
        File('${output.path}/duplicate_candidates.json').writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(variants),
        );
      } finally {
        opened.dispose();
      }
    } finally {
      backend.dispose();
    }
    final bytes = File('$_input/images/all_marked.jpg').readAsBytesSync();
    final source = cv.imdecode(bytes, cv.IMREAD_GRAYSCALE);
    try {
      // Predict a search neighborhood from the three actual decoded markers.
      // The prediction is never used as a detected corner or a registration H.
      final backend = OpenCvArucoVisionBackend();
      try {
        final session = backend.open(bytes, ArucoAlignmentConfig()).value;
        try {
          final markers = session.detection.markers;
          final tl = markers.singleWhere((m) => m.id == 10),
              tr = markers.singleWhere((m) => m.id == 11),
              br = markers.singleWhere((m) => m.id == 13);
          final cx = tl.center.x + br.center.x - tr.center.x,
              cy = tl.center.y + br.center.y - tr.center.y;
          final pad = (math.max(tl.minimumSideLength, br.minimumSideLength) * 3)
              .ceil();
          final left = math.max(0, cx.floor() - pad),
              top = math.max(0, cy.floor() - pad);
          final right = math.min(source.width, cx.ceil() + pad),
              bottom = math.min(source.height, cy.ceil() + pad);
          final crop = source.region(
            cv.Rect(left, top, right - left, bottom - top),
          );
          try {
            final controls = <Object?>[];
            for (final refinement in [
              ArucoCornerRefinement.subpixel,
              ArucoCornerRefinement.none,
            ]) {
              final detector = OpenCvArucoDetector(
                profile: ArucoDetectorProfile(cornerRefinement: refinement),
              );
              try {
                final detected = detector.detectMat(crop);
                controls.add({
                  'refinement': refinement.name,
                  'bounds': [left, top, right, bottom],
                  'ids': detected.isSuccess
                      ? detected.value.markers.map((m) => m.id).toList()
                      : [],
                  'error': detected.isFailure
                      ? detected.error.toString()
                      : null,
                });
              } finally {
                detector.dispose();
              }
            }
            File(
              '${output.path}/missing_marker_local_retry.json',
            ).writeAsStringSync(
              const JsonEncoder.withIndent('  ').convert(controls),
            );
          } finally {
            crop.dispose();
          }
        } finally {
          session.dispose();
        }
      } finally {
        backend.dispose();
      }
    } finally {
      source.dispose();
    }
    File('${output.path}/DONE').writeAsStringSync('complete');
  } on Object catch (error, stack) {
    File('${output.path}/ERROR').writeAsStringSync('$error\n$stack');
  }
}
