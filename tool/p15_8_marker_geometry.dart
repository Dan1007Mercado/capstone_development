import 'dart:convert';
import 'dart:io';

import 'package:capstone_development/application/published_templates/published_template_artifact_codec.dart';
import 'package:capstone_development/engines/aruco/application/homography_geometry_validator.dart';
import 'package:capstone_development/engines/aruco/domain/aruco_alignment_config.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';

void main() {
  final manifest=jsonDecode(File('test/fixtures/p15_6/published_manifest.json').readAsStringSync()) as Map;
  final page=const PublishedTemplateArtifactCodec().decode((manifest['artifact'] as Map).cast<String,Object?>()).layout.pages.single;
  final rows=jsonDecode(File('build/p158-native/duplicate_candidates.json').readAsStringSync()) as List;
  for(final row in rows) {
    final values=row['homography'] as List?;
    if(values==null) continue;
    row['geometryFailure']=const HomographyGeometryValidator().validationFailure(
        matrix:HomographyMatrix(values.cast<num>().map((v)=>v.toDouble())),page:page,
        sourceSize:ImageSize(width:2976,height:3968),config:ArucoAlignmentConfig());
  }
  File('build/p158-native/duplicate_geometry_validation.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
  stdout.writeln(rows);
}
