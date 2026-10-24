import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

abstract interface class PacketPdfPreviewer {
  Future<void> preview(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
    required String packetId,
  });
}

final class NavigatorPacketPdfPreviewer implements PacketPdfPreviewer {
  const NavigatorPacketPdfPreviewer();

  @override
  Future<void> preview(
    BuildContext context, {
    required Uint8List bytes,
    required String fileName,
    required String packetId,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PacketPdfPreviewScreen(
        bytes: bytes,
        fileName: fileName,
        packetId: packetId,
      ),
    ),
  );
}

class PacketPdfPreviewScreen extends StatelessWidget {
  PacketPdfPreviewScreen({
    required Uint8List bytes,
    required this.fileName,
    required this.packetId,
    super.key,
  }) : bytes = Uint8List.fromList(bytes);

  final Uint8List bytes;
  final String fileName;
  final String packetId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Packet $packetId')),
    body: PdfPreview(
      key: const Key('packet-pdf-preview'),
      build: (_) async => bytes,
      pdfFileName: fileName,
      canChangeOrientation: false,
      canChangePageFormat: false,
      canDebug: false,
      allowPrinting: true,
      allowSharing: false,
    ),
  );
}
