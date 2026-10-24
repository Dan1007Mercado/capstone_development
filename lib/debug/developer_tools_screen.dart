import 'package:flutter/material.dart';

import '../application/answer_sheet_packets/packet_generation_service.dart';
import '../application/answer_sheet_packets/packet_response_repository.dart';
import '../application/published_templates/published_template_artifact_repository.dart';
import '../application/published_templates/published_template_artifact_service.dart';
import '../application/real_scanner/published_scanner_resolver.dart';
import '../engines/template/application/template_publication_service.dart';
import 'p5_native_validation_screen.dart';
import 'p10_camera_diagnostics_screen.dart';
import 'p11_camera_scanner_screen.dart';
import 'p12_template_builder_screen.dart';
import 'real_scanner_validation_screen.dart';

class DeveloperToolsScreen extends StatelessWidget {
  const DeveloperToolsScreen({
    required this.artifactRepository,
    required this.packetRepository,
    required this.publicationService,
    super.key,
  });

  final PublishedTemplateArtifactRepository artifactRepository;
  final PacketResponseRepository packetRepository;
  final TemplatePublicationService publicationService;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Developer Tools')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Scanner / Vision',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        _ToolTile(
          key: const Key('developer-native-opencv'),
          title: 'Native OpenCV Validation',
          onTap: () => _open(context, const P5NativeValidationScreen()),
        ),
        _ToolTile(
          key: const Key('developer-camera-diagnostics'),
          title: 'Camera Diagnostics',
          onTap: () => _open(context, const P10CameraDiagnosticsScreen()),
        ),
        _ToolTile(
          key: const Key('developer-camera-scanner-diagnostics'),
          title: 'Camera Scanner Diagnostics',
          onTap: () => _open(context, const P11CameraScannerScreen()),
        ),
        const Divider(height: 32),
        Text('Validation', style: Theme.of(context).textTheme.titleMedium),
        _ToolTile(
          key: const Key('developer-template-validation'),
          title: 'Template Builder Validation Harness',
          onTap: () => _open(
            context,
            P12TemplateBuilderScreen(
              showDeveloperControls: true,
              publicationService: publicationService,
              densePublicationService: PublishedTemplateArtifactService(
                repository: artifactRepository,
              ),
              packetGenerationService: PacketGenerationService(
                repository: packetRepository,
              ),
            ),
          ),
        ),
        _ToolTile(
          key: const Key('developer-real-scanner-validation'),
          title: 'Real Scanner / ROI Validation',
          onTap: () => _open(
            context,
            RealScannerSelectionScreen(
              resolver: PublishedScannerResolver(
                artifactRepository: artifactRepository,
              ),
              packetRepository: packetRepository,
            ),
          ),
        ),
      ],
    ),
  );

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required super.key,
    required this.title,
    required this.onTap,
  });

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    trailing: const Icon(Icons.chevron_right),
    onTap: onTap,
  );
}
