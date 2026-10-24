import 'dart:typed_data';

import '../../../application/answer_sheet_packets/packet_models.dart';
import '../../../application/published_templates/published_template_artifact.dart';
import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../domain/pdf_render_plan.dart';
import 'packet_pdf_engine.dart';

/// Composes packet-specific page plans in packet order and renders one PDF.
final class PacketBatchPdfEngine {
  PacketBatchPdfEngine({PacketPdfEngine? packetPdfEngine})
    : packetPdfEngine = packetPdfEngine ?? PacketPdfEngine();

  final PacketPdfEngine packetPdfEngine;

  EngineResult<PdfRenderPlan> buildPlan(
    PublishedTemplateArtifact published,
    Iterable<AnswerSheetPacket> packets,
  ) {
    final values = packets.toList(growable: false);
    if (values.isEmpty) {
      return EngineResult.failure(
        EngineError(
          code: 'PACKET_BATCH_EMPTY',
          message: 'A packet batch requires at least one packet.',
        ),
      );
    }
    final pages = <PdfPageRenderPlan>[];
    for (final packet in values) {
      final packetPlan = packetPdfEngine.buildPlan(published, packet);
      if (packetPlan.isFailure) {
        return EngineResult.failure(packetPlan.error);
      }
      pages.addAll(packetPlan.value.pages);
    }
    return EngineResult.success(PdfRenderPlan(pages: pages));
  }

  Future<EngineResult<Uint8List>> render(
    PublishedTemplateArtifact published,
    Iterable<AnswerSheetPacket> packets,
  ) async {
    final values = packets.toList(growable: false);
    final plan = buildPlan(published, values);
    if (plan.isFailure) return EngineResult.failure(plan.error);
    return packetPdfEngine.pdfEngine.renderPlan(
      plan.value,
      title: '${published.template.name} - ${values.length} packet batch',
    );
  }
}
