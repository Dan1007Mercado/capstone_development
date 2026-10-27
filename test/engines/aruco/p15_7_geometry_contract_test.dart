import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact_codec.dart';
import 'package:capstone_development/engines/aruco/application/marker_correspondence_service.dart';
import 'package:capstone_development/engines/aruco/domain/detected_marker.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/recognition/application/canonical_bubble_mapper.dart';
import 'package:capstone_development/engines/recognition/domain/bubble_measurement_config.dart';

void main() {
  test('published mapping agrees with independently rasterized packet ink', () {
    final manifest =
        jsonDecode(
              File(
                'test/fixtures/p15_6/published_manifest.json',
              ).readAsStringSync(),
            )
            as Map;
    final page = const PublishedTemplateArtifactCodec()
        .decode((manifest['artifact'] as Map).cast<String, Object?>())
        .layout
        .pages
        .single;
    const correspondences = MarkerCorrespondenceService();
    for (var packetPage = 0; packetPage < 3; packetPage++) {
      // These are observations of the recovered PDF made with PDFium, not
      // synthetic circles drawn from the same mapping under test.
      final raster =
          jsonDecode(
                File(
                  'docs/development/evidence/p15_7/packet_print_job.pdf_$packetPage.bmp.measurements.json',
                ).readAsStringSync(),
              )
              as Map;
      final bubbles = raster['measurements'] as List;
      expect(bubbles.length, page.bubbleRegions.length);
      for (final bubble in page.bubbleRegions) {
        final observed =
            (bubbles.singleWhere(
                      (b) => b['target'] == bubble.optionId!.value,
                    )['observed']
                    as List)
                .cast<num>();
        final roi = const CanonicalBubbleMapper().map(
          bubble,
          page,
          const BubbleMeasurementConfig(),
        );
        expect(
          roi.center.distanceTo(
            ImagePoint(observed[0].toDouble(), observed[1].toDouble()),
          ),
          lessThan(1),
        );
        expect(roi.printedRadius, 25);
      }
      for (final marker in page.markerRegions) {
        final observed =
            (raster['markers'] as List).singleWhere(
                  (m) => m['id'] == marker.markerId,
                )['inkComponents'][0]
                as List;
        final left = (observed[0] as num).toDouble();
        final top = (observed[1] as num).toDouble();
        final right = left + (observed[2] as num);
        final bottom = top + (observed[3] as num);
        final corners = {
          MarkerCorner.topLeft: ImagePoint(left, top),
          MarkerCorner.topRight: ImagePoint(right, top),
          MarkerCorner.bottomRight: ImagePoint(right, bottom),
          MarkerCorner.bottomLeft: ImagePoint(left, bottom),
        };
        for (final corner in MarkerCorner.values) {
          expect(
            correspondences
                .physicalMarkerCornerToCanonical(marker, corner, page)
                .distanceTo(corners[corner]!),
            lessThan(1),
          );
        }
        final inner = DetectedRegistrationCorner.forRole(marker.role);
        expect(
          correspondences
              .physicalRegistrationToCanonical(marker, page)
              .distanceTo(corners[inner]!),
          lessThan(1),
        );
      }
    }
  });
}
