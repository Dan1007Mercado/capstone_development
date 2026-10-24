import 'dart:typed_data';

import 'package:capstone_development/application/answer_sheet_packets/packet_models.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/core/protocol/packet_marker_codec.dart';
import 'package:capstone_development/debug/p11_1_scanner_validation_sheet.dart';
import 'package:capstone_development/engines/layout/application/packet_header_layout_engine.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/pdf/application/packet_pdf_engine.dart';
import 'package:capstone_development/engines/pdf/domain/pdf_render_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('header identity markers respect all published geometry exclusions', () {
    final page = buildP11ScannerValidationSheetInputs().layout.pages.first;
    final markerIds = const PacketMarkerCodec()
        .encode(packetId: PacketId.fromSequence(42), pageIndex: page.pageIndex)
        .value
        .markerIds;

    final result = const PacketHeaderLayoutEngine().build(page, markerIds);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    final header = result.value;
    expect(
      header.markerRowBounds.bottom.millimeters,
      lessThanOrEqualTo(header.packetInfoTextBounds.top.millimeters),
    );
    expect(
      header.packetInfoTextBounds.containsRect(header.packetLabelBounds),
      isTrue,
    );
    expect(
      header.packetInfoTextBounds.containsRect(header.pageLabelBounds),
      isTrue,
    );
    expect(
      header.packetLabelBounds.intersects(header.pageLabelBounds),
      isFalse,
    );
    for (final textBounds in [
      header.packetLabelBounds,
      header.pageLabelBounds,
    ]) {
      expect(
        page.markerRegions.any(
          (marker) => marker.physicalBounds.intersects(textBounds),
        ),
        isFalse,
      );
      expect(
        header.identityMarkers.any(
          (marker) => marker.physicalBounds.intersects(textBounds),
        ),
        isFalse,
      );
      expect(
        page.questionRegions.any(
          (question) => question.physicalBounds.intersects(textBounds),
        ),
        isFalse,
      );
      expect(
        page.bubbleRegions.any(
          (bubble) => bubble.physicalBounds.intersects(textBounds),
        ),
        isFalse,
      );
    }
    for (final identity in header.identityMarkers) {
      expect(
        page.printableBounds.containsRect(identity.physicalBounds),
        isTrue,
      );
      expect(
        page.markerRegions.any(
          (marker) => marker.physicalBounds.intersects(identity.physicalBounds),
        ),
        isFalse,
      );
      expect(
        page.questionRegions.any(
          (question) =>
              question.physicalBounds.intersects(identity.physicalBounds),
        ),
        isFalse,
      );
      expect(
        page.bubbleRegions.any(
          (bubble) => bubble.physicalBounds.intersects(identity.physicalBounds),
        ),
        isFalse,
      );
    }
  });

  test(
    'packet plan overlays identity while preserving exact stored layout',
    () {
      final inputs = buildP11ScannerValidationSheetInputs();
      final published = PublishedTemplateArtifact(
        template: inputs.template.toPublishedAfterValidation(),
        layoutProfile: LayoutProfile.answerSheet,
        layout: inputs.layout,
        pdfBytes: Uint8List.fromList([37, 80, 68, 70, 45]),
      );
      final packetId = PacketId.fromSequence(43);
      const codec = PacketMarkerCodec();
      final packet = AnswerSheetPacket(
        packetId: packetId,
        templateId: published.templateId,
        templateVersion: published.templateVersion,
        createdAt: DateTime.utc(2026, 1, 1),
        pages: [
          for (final page in published.layout.pages)
            AnswerSheetPacketPage(
              packetId: packetId,
              pageId: page.pageId,
              pageIndex: page.pageIndex,
              totalPages: page.totalPageCount,
              identityMarkerIds: codec
                  .encode(packetId: packetId, pageIndex: page.pageIndex)
                  .value
                  .markerIds,
            ),
        ],
        status: AnswerSheetPacketStatus.unused,
      );

      final plan = PacketPdfEngine().buildPlan(published, packet);

      expect(plan.isSuccess, isTrue, reason: plan.errorOrNull?.toString());
      for (var index = 0; index < plan.value.pages.length; index++) {
        final page = plan.value.pages[index];
        final stored = published.layout.pages[index];
        expect(page.layout, same(stored));
        expect(
          page.bubbles.map((bubble) => bubble.physicalBounds),
          stored.bubbleRegions.map((bubble) => bubble.physicalBounds),
        );
        expect(
          page.markers.where((marker) => marker.isRegistration),
          hasLength(4),
        );
        expect(
          page.markers.where((marker) => !marker.isRegistration),
          hasLength(4),
        );
        expect(
          page.text
              .where((text) => text.role == PdfTextRole.packetIdentity)
              .single
              .text,
          'Packet ${packetId.value}',
        );
        expect(
          page.text
              .where((text) => text.role == PdfTextRole.packetPageIdentity)
              .single
              .text,
          'Page ${index + 1} of ${plan.value.pages.length}',
        );
      }
    },
  );
}
