import 'dart:convert';
import 'dart:io';
import 'package:image/image.dart' as image;
import 'package:capstone_development/application/published_templates/published_template_artifact_codec.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/recognition/application/bubble_alignment_evidence.dart';
import 'package:capstone_development/engines/recognition/application/bubble_alignment_ground_truth.dart';

void main(List<String> args) {
  final folder = args.isEmpty ? 'build/p156-before/baseline' : args[0];
  final manifest =
      jsonDecode(
            File(
              'test/fixtures/p15_6/published_manifest.json',
            ).readAsStringSync(),
          )
          as Map;
  final artifact = const PublishedTemplateArtifactCodec().decode(
    (manifest['artifact'] as Map).cast<String, Object?>(),
  );
  final raw = image
      .decodePng(
        File('$folder/unmarked.jpg_fourPoint_canonical.png').readAsBytesSync(),
      )!
      .convert(numChannels: 1);
  final evidence =
      const BubbleAlignmentEvidenceEvaluator(
        maximumCenterSearchPixels: 24,
      ).evaluate(
        CanonicalPageImage.ownedGrayscale(
          size: ImageSize(width: raw.width, height: raw.height),
          grayscaleBytes: raw.getBytes(),
        ),
        artifact.layout.pages.single,
      );
  final observations = [
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
        'contrast': o.ringContrast,
        'confident': o.confident,
      },
  ];
  File(
    '$folder/wide-outline-evidence.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(observations));
  stdout.writeln(
    jsonEncode({
      'mean': evidence.meanCenterDisplacementPixels,
      'p95': evidence.percentile95CenterDisplacementPixels,
    }),
  );
  final report =
      jsonDecode(File('$folder/unmarked.jpg.json').readAsStringSync()) as Map;
  HomographyMatrix matrix(List values) =>
      HomographyMatrix(values.map((v) => (v as num).toDouble()));
  final four = matrix(
    (report['fourPoint'] as Map)['snapshot']['homography'] as List,
  );
  final multi = matrix(
    (report['multiPointEstimate'] as Map)['homography'] as List,
  );
  final inverse = four.inverse();
  // Printed-outline observations are algorithmic independent landmarks, not
  // manually verified ground truth. Do not use this diagnostic to accept H.
  final annotations = [
    for (final o in evidence.observations.where((o) => o.confident))
      BubbleGroundTruthAnnotation(
        questionId: o.questionId,
        targetLabel: o.targetLabel,
        sourceCenter: inverse.project(
          ImagePoint(o.observedCenterX, o.observedCenterY),
        ),
      ),
  ];
  final comparison = <String, Object?>{
    'provenance':
        'algorithmic printed-outline landmarks; not manual ground truth',
  };
  for (final entry in {
    'fourPoint': four,
    'rejectedMultiPointDiagnostic': multi,
  }.entries) {
    final result = const BubbleAlignmentGroundTruthEvaluator().evaluate(
      page: artifact.layout.pages.single,
      homography: entry.value,
      annotations: annotations,
    );
    comparison[entry.key] = {
      'mean': result.mean,
      'p95': result.percentile95,
      'maximum': result.maximum,
      'complete': result.complete,
      'regional': result.regionalMeanDisplacementPixels,
    };
  }
  File(
    '$folder/independent_projection_comparison.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(comparison));
  stdout.writeln(jsonEncode(comparison));
}
