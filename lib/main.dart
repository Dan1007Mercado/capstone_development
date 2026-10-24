import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'application/answer_sheet_packets/file_packet_response_repository.dart';
import 'application/answer_sheet_packets/in_memory_packet_response_repository.dart';
import 'application/answer_sheet_packets/packet_generation_service.dart';
import 'application/answer_sheet_packets/packet_response_repository.dart';
import 'application/published_templates/file_published_template_artifact_repository.dart';
import 'application/published_templates/in_memory_published_template_artifact_repository.dart';
import 'application/published_templates/published_template_artifact_repository.dart';
import 'application/published_templates/published_template_artifact_service.dart';
import 'application/real_scanner/published_scanner_resolver.dart';
import 'debug/developer_tools_screen.dart';
import 'debug/p12_template_builder_screen.dart';
import 'debug/real_scanner_validation_screen.dart';
import 'engines/template/application/template_publication_service.dart';
import 'engines/template/infrastructure/in_memory_template_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDirectory = await getApplicationSupportDirectory();
  final artifactRepository = FilePublishedTemplateArtifactRepository(
    rootDirectory: Directory(
      '${supportDirectory.path}${Platform.pathSeparator}'
      'published_template_artifacts',
    ),
  );
  final packetRepository = FilePacketResponseRepository(
    rootDirectory: Directory(
      '${supportDirectory.path}${Platform.pathSeparator}'
      'answer_sheet_packets',
    ),
  );
  runApp(
    MyApp(
      artifactRepository: artifactRepository,
      packetRepository: packetRepository,
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.artifactRepository, this.packetRepository});

  final PublishedTemplateArtifactRepository? artifactRepository;
  final PacketResponseRepository? packetRepository;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Capstone OMR',
    theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.deepPurple)),
    home: MyHomePage(
      title: 'Capstone OMR',
      artifactRepository: artifactRepository,
      packetRepository: packetRepository,
    ),
  );
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    this.title = 'Capstone OMR',
    this.artifactRepository,
    this.packetRepository,
  });

  final String title;
  final PublishedTemplateArtifactRepository? artifactRepository;
  final PacketResponseRepository? packetRepository;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late final TemplatePublicationService _publicationService;
  late final PublishedTemplateArtifactRepository _artifactRepository;
  late final PacketResponseRepository _packetRepository;

  @override
  void initState() {
    super.initState();
    _publicationService = TemplatePublicationService(
      repository: InMemoryTemplateRepository(),
    );
    _artifactRepository =
        widget.artifactRepository ??
        InMemoryPublishedTemplateArtifactRepository();
    _packetRepository =
        widget.packetRepository ?? InMemoryPacketResponseRepository();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      title: Text(widget.title),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Capstone OMR',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('open-template-builder'),
              onPressed: () => _openTemplateBuilder(context),
              icon: const Icon(Icons.description_outlined),
              label: const Text('Template Builder'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('open-scanner'),
              onPressed: () => _openScanner(context),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scanner'),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                key: const Key('open-developer-tools'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => DeveloperToolsScreen(
                      artifactRepository: _artifactRepository,
                      packetRepository: _packetRepository,
                      publicationService: _publicationService,
                    ),
                  ),
                ),
                icon: const Icon(Icons.build_outlined),
                label: const Text('Developer Tools'),
              ),
            ],
          ],
        ),
      ),
    ),
  );

  void _openTemplateBuilder(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => P12TemplateBuilderScreen(
          publicationService: _publicationService,
          densePublicationService: PublishedTemplateArtifactService(
            repository: _artifactRepository,
          ),
          packetGenerationService: PacketGenerationService(
            repository: _packetRepository,
          ),
        ),
      ),
    );
  }

  void _openScanner(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RealScannerSelectionScreen(
          resolver: PublishedScannerResolver(
            artifactRepository: _artifactRepository,
          ),
          packetRepository: _packetRepository,
        ),
      ),
    );
  }
}
