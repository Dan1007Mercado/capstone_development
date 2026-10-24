import 'dart:typed_data';

import '../../../application/answer_sheet_packets/packet_models.dart';
import '../../../application/published_templates/published_template_artifact.dart';
import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../layout/application/packet_header_layout_engine.dart';
import '../domain/pdf_render_plan.dart';
import 'pdf_engine.dart';

final class PacketPdfEngine {
  PacketPdfEngine({
    PdfEngine? pdfEngine,
    this.headerLayoutEngine = const PacketHeaderLayoutEngine(),
  }) : pdfEngine = pdfEngine ?? PdfEngine();

  final PdfEngine pdfEngine;
  final PacketHeaderLayoutEngine headerLayoutEngine;

  Future<EngineResult<Uint8List>> render(
    PublishedTemplateArtifact published,
    AnswerSheetPacket packet,
  ) async {
    final plan = buildPlan(published, packet);
    if (plan.isFailure) return EngineResult.failure(plan.error);
    return pdfEngine.renderPlan(
      plan.value,
      title: '${published.template.name} - ${packet.packetId.value}',
    );
  }

  EngineResult<PdfRenderPlan> buildPlan(
    PublishedTemplateArtifact published,
    AnswerSheetPacket packet,
  ) {
    if (published.templateId != packet.templateId ||
        published.templateVersion != packet.templateVersion ||
        published.layout.pages.length != packet.pages.length) {
      return EngineResult.failure(
        EngineError(
          code: 'PACKET_TEMPLATE_MISMATCH',
          message: 'Packet does not belong to the published artifact.',
        ),
      );
    }
    final base = pdfEngine.buildPlan(published.template, published.layout);
    if (base.isFailure) return EngineResult.failure(base.error);
    final pages = <PdfPageRenderPlan>[];
    for (var index = 0; index < base.value.pages.length; index++) {
      final basePage = base.value.pages[index];
      final packetPage = packet.pages[index];
      final header = headerLayoutEngine.build(
        basePage.layout,
        packetPage.identityMarkerIds,
      );
      if (header.isFailure) return EngineResult.failure(header.error);
      final identityMarkers = <PdfMarkerCommand>[];
      for (final region in header.value.identityMarkers) {
        try {
          identityMarkers.add(
            PdfMarkerCommand.identity(
              bounds: region.physicalBounds,
              marker: pdfEngine.markerEncoder.encode(region.markerId),
            ),
          );
        } on Object catch (error) {
          return EngineResult.failure(
            EngineError(
              code: 'PDF_MARKER_ENCODING_FAILED',
              message: 'Unable to encode a packet identity marker.',
              details: {'markerId': region.markerId, 'cause': error.toString()},
            ),
          );
        }
      }
      pages.add(
        PdfPageRenderPlan(
          layout: basePage.layout,
          identity: basePage.identity,
          markers: [...basePage.markers, ...identityMarkers],
          text: [
            ...basePage.text,
            PdfTextCommand(
              role: PdfTextRole.packetIdentity,
              text: 'Packet ${packet.packetId.value}',
              bounds: header.value.packetLabelBounds,
            ),
            PdfTextCommand(
              role: PdfTextRole.packetPageIdentity,
              text:
                  'Page ${packetPage.pageIndex + 1} of ${packetPage.totalPages}',
              bounds: header.value.pageLabelBounds,
            ),
          ],
          bubbles: basePage.bubbles,
        ),
      );
    }
    return EngineResult.success(PdfRenderPlan(pages: pages));
  }
}
