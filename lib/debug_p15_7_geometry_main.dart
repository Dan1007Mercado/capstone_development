// Offline investigation only; no production entry point calls this file.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import 'debug/p15_6_experiment.dart' as replay;
import 'engines/aruco/domain/aruco_alignment_config.dart';
import 'engines/aruco/domain/aruco_detector_profile.dart';
import 'engines/aruco/infrastructure/opencv_aruco_detector.dart';
import 'engines/aruco/infrastructure/opencv_aruco_vision_backend.dart';

const _input = '/data/user/0/com.example.capstone_development/files/p156-input';
const _output =
    '/sdcard/Android/data/com.example.capstone_development/files/p157';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Text('P15.7 offline geometry experiment')),
    ),
  );
  unawaited(_run());
}

Future<void> _run() async {
  final output = Directory(_output)..createSync(recursive: true);
  try {
    final bytes = File('$_input/published_template.pdf').readAsBytesSync();
    await for (final page in Printing.raster(bytes, pages: [0], dpi: 254)) {
      File(
        '${output.path}/published_254dpi.png',
      ).writeAsBytesSync(await page.toPng());
      File('${output.path}/raster.json').writeAsStringSync(
        jsonEncode({
          'renderer': 'printing Android PdfRenderer',
          'dpi': 254,
          'width': page.width,
          'height': page.height,
        }),
      );
    }
    await Isolate.run(_native);
    File('${output.path}/DONE').writeAsStringSync('complete');
  } on Object catch (error, stack) {
    File('${output.path}/ERROR').writeAsStringSync('$error\n$stack');
  }
}

void _native() {
  final detections = <Object?>[];
  final files =
      Directory('$_input/images').listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  files.add(File('$_output/published_254dpi.png'));
  for (final file in files) {
    final bytes = file.readAsBytesSync();
    for (final mode in ['baseline', 'full-resolution', 'no-refinement']) {
      final backend = OpenCvArucoVisionBackend(
        detector: OpenCvArucoDetector(
          profile: ArucoDetectorProfile(
            cornerRefinement: mode == 'no-refinement'
                ? ArucoCornerRefinement.none
                : ArucoCornerRefinement.subpixel,
          ),
        ),
      );
      try {
        final opened = backend.open(
          bytes,
          ArucoAlignmentConfig(
            finalMarkerDetectionMaxDimension: mode == 'full-resolution'
                ? null
                : 1400,
          ),
        );
        if (opened.isFailure) {
          detections.add({
            'file': file.uri.pathSegments.last,
            'mode': mode,
            'error': opened.error.toString(),
          });
          continue;
        }
        final session = opened.value;
        try {
          detections.add({
            'file': file.uri.pathSegments.last,
            'mode': mode,
            'sourceWidth': session.sourceSize.width,
            'sourceHeight': session.sourceSize.height,
            'markers': [
              for (final marker in session.detection.markers)
                {
                  'id': marker.id,
                  'corners': [
                    for (final point in marker.corners) [point.x, point.y],
                  ],
                },
            ],
          });
        } finally {
          session.dispose();
        }
      } finally {
        backend.dispose();
      }
    }
  }
  File(
    '$_output/detections.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(detections));
  replay.main([_input, '$_output/baseline']);
}
