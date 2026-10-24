import 'dart:typed_data';

import '../../core/errors/engine_error.dart';
import '../../core/ids/identifiers.dart';
import '../../core/protocol/packet_marker_codec.dart';
import '../../core/result/engine_result.dart';
import '../../engines/layout/domain/layout_config.dart';
import '../../engines/pdf/application/packet_pdf_engine.dart';
import '../../engines/scanner/domain/packet_scan_identity.dart';
import '../../engines/template/domain/template_status.dart';
import '../published_templates/published_template_artifact.dart';
import 'packet_models.dart';
import 'packet_response_repository.dart';

typedef PacketPdfRenderer =
    Future<EngineResult<Uint8List>> Function(
      PublishedTemplateArtifact published,
      AnswerSheetPacket packet,
    );

final class PacketGenerationService {
  PacketGenerationService({
    required this.repository,
    PacketPdfRenderer? pdfRenderer,
    this.markerCodec = const PacketMarkerCodec(),
    DateTime Function()? clock,
  }) : pdfRenderer = pdfRenderer ?? PacketPdfEngine().render,
       clock = clock ?? DateTime.now;

  final PacketResponseRepository repository;
  final PacketPdfRenderer pdfRenderer;
  final PacketMarkerCodec markerCodec;
  final DateTime Function() clock;

  Future<EngineResult<List<PacketArtifact>>> generatePackets(
    PublishedTemplateArtifact published, {
    required int count,
  }) async {
    if (published.template.status != TemplateStatus.published ||
        published.layoutProfile != LayoutProfile.answerSheet) {
      return EngineResult.failure(
        EngineError(
          code: 'PACKET_ARTIFACT_INVALID',
          message: 'Packets require a published answer-sheet artifact.',
        ),
      );
    }
    if (published.layout.pages.length >
        PacketMarkerCodec.maximumPageIndex + 1) {
      return EngineResult.failure(
        EngineError(
          code: 'PACKET_MARKER_CAPACITY_EXCEEDED',
          message: 'Published artifact has too many pages for packet markers.',
        ),
      );
    }
    final reserved = await repository.reservePacketSequences(count);
    if (reserved.isFailure) return EngineResult.failure(reserved.error);
    final packets = <AnswerSheetPacket>[];
    final artifacts = <PacketArtifact>[];
    for (final sequence in reserved.value) {
      final packetId = PacketId.fromSequence(sequence);
      final pages = <AnswerSheetPacketPage>[];
      for (final layoutPage in published.layout.pages) {
        final encoded = markerCodec.encode(
          packetId: packetId,
          pageIndex: layoutPage.pageIndex,
        );
        if (encoded.isFailure) return EngineResult.failure(encoded.error);
        pages.add(
          AnswerSheetPacketPage(
            packetId: packetId,
            pageId: layoutPage.pageId,
            pageIndex: layoutPage.pageIndex,
            totalPages: layoutPage.totalPageCount,
            identityMarkerIds: encoded.value.markerIds,
          ),
        );
      }
      final packet = AnswerSheetPacket(
        packetId: packetId,
        templateId: published.templateId,
        templateVersion: published.templateVersion,
        createdAt: clock().toUtc(),
        pages: pages,
        status: AnswerSheetPacketStatus.unused,
      );
      final rendered = await pdfRenderer(published, packet);
      if (rendered.isFailure) return EngineResult.failure(rendered.error);
      packets.add(packet);
      artifacts.add(PacketArtifact(packet: packet, pdfBytes: rendered.value));
    }
    final saved = await repository.saveGeneratedPackets(packets);
    if (saved.isFailure) return EngineResult.failure(saved.error);
    return EngineResult.success(List.unmodifiable(artifacts));
  }
}

PacketScanContext packetScanContext(Iterable<AnswerSheetPacket> packets) =>
    PacketScanContext(
      knownPages: [
        for (final packet in packets)
          for (final page in packet.pages)
            PacketPageIdentity(
              packetId: packet.packetId,
              templateId: packet.templateId,
              templateVersion: packet.templateVersion,
              pageId: page.pageId,
              pageIndex: page.pageIndex,
              totalPages: page.totalPages,
              identityMarkerIds: page.identityMarkerIds,
            ),
      ],
    );
