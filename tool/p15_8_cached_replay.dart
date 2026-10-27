// Fast experimental comparison on the actual saved native P15.6 pixel buffers.
// It does not decode JPEGs or rerun alignment/preprocessing.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as im;
import 'package:capstone_development/application/published_templates/published_template_artifact_codec.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/preprocessing/domain/pixel_images.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessed_page.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessing_config.dart';
import 'package:capstone_development/engines/recognition/application/bubble_measurement_engine.dart';
import 'package:capstone_development/engines/recognition/application/bubble_registration_engine.dart';
import 'package:capstone_development/engines/recognition/application/mark_classification_engine.dart';

void main(List<String> args) {
  final folder = args.isEmpty || args[0].startsWith('--')
      ? 'build/p156-after-complete/baseline'
      : args[0];
  final labelArg = args
      .where((a) => a.startsWith('--label-ratio='))
      .firstOrNull;
  final shifted = args.contains('--shift');
  final suffix = labelArg != null
      ? 'label-${labelArg.split('=').last}'
      : shifted
      ? 'shifted'
      : 'cached';
  final output = Directory('build/p158-$suffix')..createSync(recursive: true);
  final manifest =
      jsonDecode(
            File(
              'test/fixtures/p15_6/published_manifest.json',
            ).readAsStringSync(),
          )
          as Map;
  if (labelArg != null) {
    // Controlled offline mask experiment only. Never writes a published artifact.
    final ratio = double.parse(labelArg.split('=').last);
    void adjust(Object? object) {
      if (object is Map) {
        if (object.containsKey('measurementCenterExclusionRatio')) {
          object['measurementCenterExclusionRatio'] = ratio;
        }
        for (final value in object.values) {
          adjust(value);
        }
      } else if (object is List) {
        for (final value in object) {
          adjust(value);
        }
      }
    }

    adjust(manifest['artifact']['layout']);
  }
  final artifact = const PublishedTemplateArtifactCodec().decode(
    (manifest['artifact'] as Map).cast<String, Object?>(),
  );
  final page = artifact.layout.pages.single;
  const stats = ImageStatistics(
    meanIntensity: 0,
    intensityStandardDeviation: 0,
    minimumIntensity: 0,
    maximumIntensity: 255,
    darkPixelRatio: 0,
    brightPixelRatio: 0,
  );
  final results = <Object?>[];
  for (final file in Directory(
    folder,
  ).listSync().whereType<File>().where((f) => f.path.endsWith('.jpg.json'))) {
    final name = file.uri.pathSegments.last.replaceAll('.json', '');
    final report = jsonDecode(file.readAsStringSync()) as Map;
    if (report['fourPoint']['snapshot'] == null) {
      results.add({'file': name, 'error': report['fourPoint']['error']});
      continue;
    }
    Uint8List load(String stage) {
      final bytes = im
          .decodePng(
            File('$folder/${name}_fourPoint_$stage.png').readAsBytesSync(),
          )!
          .convert(numChannels: 1)
          .getBytes();
      if (!shifted) return bytes;
      // Shift all three existing buffers by (+2,-1); no extra native passes.
      final translated = Uint8List(bytes.length)
        ..fillRange(0, bytes.length, 255);
      for (var y = 1; y < 2970; y++) {
        translated.setRange((y - 1) * 2100 + 2, y * 2100, bytes, y * 2100);
      }
      return translated;
    }

    final size = ImageSize(width: 2100, height: 2970);
    final binary = load('binary');
    for (var i = 0; i < binary.length; i++) {
      binary[i] = binary[i] < 128 ? 1 : 0;
    }
    final pixels = PreprocessedPage(
      size: size,
      grayscale: GrayImage.owned(size: size, pixels: load('canonical')),
      normalizedGrayscale: GrayImage.owned(
        size: size,
        pixels: load('normalized'),
      ),
      binary: BinaryImage.owned(size: size, pixels: binary),
      diagnostics: const PreprocessingDiagnostics(
        sourceStatistics: stats,
        normalizedStatistics: stats,
        binaryForegroundRatio: 0,
        processingDuration: Duration.zero,
      ),
      config: const PreprocessingConfig(),
    );
    final watch = Stopwatch()..start();
    final measured = const BubbleMeasurementEngine(
      registration: BubbleRegistrationEngine(),
    ).measure(page, pixels);
    if (measured.isFailure) {
      results.add({
        'file': name,
        'error': measured.error.toString(),
        'details': measured.error.details,
      });
      stdout.writeln('$name ${measured.error} ${measured.error.details}');
      continue;
    }
    final classified = const MarkClassificationEngine()
        .classify(artifact.template, page, measured.value)
        .value;
    final result = {
      'file': name,
      'registration': measured.value.registration!.toJson(),
      'measurementMs': watch.elapsedMicroseconds / 1000,
      'answers': [
        for (final q in classified.questions)
          {
            'number': q.questionNumber,
            'state': q.state.name,
            'options': q.selectedOptionIds.map((o) => o.value).toList(),
            'bubbles': [
              for (final b in q.bubbleDecisions)
                {
                  'option': b.optionId?.value,
                  'fill': b.fillRatio,
                  'score': b.combinedMarkScore,
                  'category': b.category.name,
                },
            ],
          },
      ],
    };
    results.add(result);
    stdout.writeln(
      '$name ${classified.questions.map((q) => q.state.name).join(',')} ${measured.value.registration!.regions}',
    );
    File(
      '${output.path}/$name.json',
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(result));
  }
  File(
    '${output.path}/results.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
}
