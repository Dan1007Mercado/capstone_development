import 'dart:convert';
import 'dart:typed_data';

import 'package:capstone_development/application/answer_sheet_packets/packet_models.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact.dart';
import 'package:capstone_development/application/template_builder/template_builder_controller.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/core/protocol/packet_marker_codec.dart';
import 'package:capstone_development/debug/p11_1_scanner_validation_sheet.dart';
import 'package:capstone_development/engines/layout/application/layout_engine.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/pdf/application/packet_batch_pdf_engine.dart';
import 'package:capstone_development/engines/pdf/domain/pdf_render_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('50 one-page packets compose one ordered 50-page batch plan', () {
    final published = _onePageArtifact();
    final packets = _packets(published, count: 50);

    final result = PacketBatchPdfEngine().buildPlan(published, packets);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(result.value.pages, hasLength(50));
    for (var index = 0; index < packets.length; index++) {
      _expectPacketPage(result.value.pages[index], packets[index], 0);
    }
  });

  test(
    'batch renderer emits one parseable PDF with every packet page',
    () async {
      final published = _onePageArtifact();
      final packets = _packets(published, count: 5);

      final result = await PacketBatchPdfEngine().render(published, packets);

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      expect(ascii.decode(result.value.take(5).toList()), '%PDF-');
      expect(_pdfPageCount(result.value), 5);
    },
  );

  test('10 three-page packets preserve packet-major page ordering', () {
    final inputs = buildP11ScannerValidationSheetInputs();
    final published = PublishedTemplateArtifact(
      template: inputs.template.toPublishedAfterValidation(),
      layoutProfile: LayoutProfile.answerSheet,
      layout: inputs.layout,
      pdfBytes: Uint8List.fromList([37, 80, 68, 70]),
    );
    expect(published.layout.pages, hasLength(3));
    final packets = _packets(published, count: 10);

    final result = PacketBatchPdfEngine().buildPlan(published, packets);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(result.value.pages, hasLength(30));
    var renderedIndex = 0;
    for (final packet in packets) {
      for (var pageIndex = 0; pageIndex < 3; pageIndex++) {
        _expectPacketPage(
          result.value.pages[renderedIndex++],
          packet,
          pageIndex,
        );
      }
    }
  });
}

void _expectPacketPage(
  PdfPageRenderPlan rendered,
  AnswerSheetPacket packet,
  int pageIndex,
) {
  final packetPage = packet.pages[pageIndex];
  expect(rendered.layout.pageIndex, pageIndex);
  expect(rendered.layout.pageId, packetPage.pageId);
  expect(
    rendered.text
        .where((command) => command.role == PdfTextRole.packetIdentity)
        .single
        .text,
    'Packet ${packet.packetId.value}',
  );
  expect(
    rendered.text
        .where((command) => command.role == PdfTextRole.packetPageIdentity)
        .single
        .text,
    'Page ${pageIndex + 1} of ${packet.pages.length}',
  );
  expect(
    rendered.markers
        .where((marker) => !marker.isRegistration)
        .map((marker) => marker.marker.markerId),
    packetPage.identityMarkerIds,
  );
}

PublishedTemplateArtifact _onePageArtifact() {
  final controller = TemplateBuilderController(
    templateId: TemplateId('batch-one-page'),
    name: 'Batch One Page',
  );
  final section = controller.addSection(title: 'Section');
  controller.addQuestion(section, prompt: 'Question');
  final template = controller.buildDefinition().toPublishedAfterValidation();
  final layout = LayoutEngine().build(template, LayoutConfig.a4AnswerSheet());
  expect(layout.isSuccess, isTrue, reason: layout.errorOrNull?.toString());
  expect(layout.value.pages, hasLength(1));
  return PublishedTemplateArtifact(
    template: template,
    layoutProfile: LayoutProfile.answerSheet,
    layout: layout.value,
    pdfBytes: Uint8List.fromList([37, 80, 68, 70]),
  );
}

List<AnswerSheetPacket> _packets(
  PublishedTemplateArtifact published, {
  required int count,
}) {
  const codec = PacketMarkerCodec();
  return [
    for (var sequence = 0; sequence < count; sequence++)
      _packet(published, PacketId.fromSequence(sequence), codec),
  ];
}

AnswerSheetPacket _packet(
  PublishedTemplateArtifact published,
  PacketId packetId,
  PacketMarkerCodec codec,
) => AnswerSheetPacket(
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

int _pdfPageCount(List<int> bytes) {
  final source = latin1.decode(bytes, allowInvalid: true);
  return RegExp(r'/Type\s*/Page(?!s)').allMatches(source).length;
}
