import 'dart:typed_data';

import '../../core/errors/engine_error.dart';
import '../../core/ids/identifiers.dart';
import '../../core/protocol/packet_marker_codec.dart';
import '../../core/result/engine_result.dart';
import '../../engines/layout/domain/layout_config.dart';
import '../../engines/pdf/application/packet_batch_pdf_engine.dart';
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

typedef PacketBatchPdfRenderer =
    Future<EngineResult<Uint8List>> Function(
      PublishedTemplateArtifact published,
      Iterable<AnswerSheetPacket> packets,
    );

final class PacketGenerationService {
  PacketGenerationService({
    required this.repository,
    PacketPdfRenderer? pdfRenderer,
    PacketBatchPdfRenderer? batchPdfRenderer,
    this.markerCodec = const PacketMarkerCodec(),
    DateTime Function()? clock,
  }) : pdfRenderer = pdfRenderer ?? PacketPdfEngine().render,
       batchPdfRenderer = batchPdfRenderer ?? PacketBatchPdfEngine().render,
       clock = clock ?? DateTime.now;

  final PacketResponseRepository repository;
  final PacketPdfRenderer pdfRenderer;
  final PacketBatchPdfRenderer batchPdfRenderer;
  final PacketMarkerCodec markerCodec;
  final DateTime Function() clock;

  Future<EngineResult<PacketArtifact>> renderPacket(
    PublishedTemplateArtifact published,
    AnswerSheetPacket packet,
  ) async {
    if (published.templateId != packet.templateId ||
        published.templateVersion != packet.templateVersion) {
      return EngineResult.failure(
        EngineError(
          code: 'PACKET_ARTIFACT_INVALID',
          message: 'Packet does not belong to the selected published artifact.',
        ),
      );
    }
    final rendered = await pdfRenderer(published, packet);
    if (rendered.isFailure) return EngineResult.failure(rendered.error);
    return EngineResult.success(
      PacketArtifact(packet: packet, pdfBytes: rendered.value),
    );
  }

  Future<EngineResult<List<PacketArtifact>>> generatePackets(
    PublishedTemplateArtifact published, {
    required int count,
  }) async {
    final packetsResult = await _reservePackets(published, count);
    if (packetsResult.isFailure) {
      return EngineResult.failure(packetsResult.error);
    }
    final packets = packetsResult.value;
    final artifacts = <PacketArtifact>[];
    for (final packet in packets) {
      final rendered = await renderPacket(published, packet);
      if (rendered.isFailure) return EngineResult.failure(rendered.error);
      artifacts.add(rendered.value);
    }
    final saved = await repository.saveGeneratedPackets(packets);
    if (saved.isFailure) return EngineResult.failure(saved.error);
    return EngineResult.success(List.unmodifiable(artifacts));
  }

  /// Reserves unique packet identities, renders one ordered batch PDF, then
  /// commits all packet metadata atomically. Reserved IDs are never reused if
  /// rendering or persistence fails.
  Future<EngineResult<PacketBatchArtifact>> generateBatch(
    PublishedTemplateArtifact published, {
    required int count,
  }) async {
    final packetsResult = await _reservePackets(published, count);
    if (packetsResult.isFailure) {
      return EngineResult.failure(packetsResult.error);
    }
    final packets = packetsResult.value;
    final rendered = await batchPdfRenderer(published, packets);
    if (rendered.isFailure) return EngineResult.failure(rendered.error);
    final saved = await repository.saveGeneratedPackets(packets);
    if (saved.isFailure) return EngineResult.failure(saved.error);
    return EngineResult.success(
      PacketBatchArtifact(
        publishedArtifact: published,
        packets: packets,
        pdfBytes: rendered.value,
        createdAt: clock().toUtc(),
      ),
    );
  }

  Future<EngineResult<List<AnswerSheetPacket>>> _reservePackets(
    PublishedTemplateArtifact published,
    int count,
  ) async {
    final validation = _validatePublishedArtifact(published);
    if (validation != null) return EngineResult.failure(validation);
    final reserved = await repository.reservePacketSequences(count);
    if (reserved.isFailure) return EngineResult.failure(reserved.error);
    final createdAt = clock().toUtc();
    final packets = <AnswerSheetPacket>[];
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
      packets.add(
        AnswerSheetPacket(
          packetId: packetId,
          templateId: published.templateId,
          templateVersion: published.templateVersion,
          createdAt: createdAt,
          pages: pages,
          status: AnswerSheetPacketStatus.unused,
        ),
      );
    }
    return EngineResult.success(List.unmodifiable(packets));
  }

  EngineError? _validatePublishedArtifact(PublishedTemplateArtifact published) {
    if (published.template.status != TemplateStatus.published ||
        published.layoutProfile != LayoutProfile.answerSheet) {
      return EngineError(
        code: 'PACKET_ARTIFACT_INVALID',
        message: 'Packets require a published answer-sheet artifact.',
      );
    }
    if (published.layout.pages.length >
        PacketMarkerCodec.maximumPageIndex + 1) {
      return EngineError(
        code: 'PACKET_MARKER_CAPACITY_EXCEEDED',
        message: 'Published artifact has too many pages for packet markers.',
      );
    }
    return null;
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
