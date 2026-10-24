import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'application/published_templates/file_published_template_artifact_repository.dart';
import 'application/published_templates/in_memory_published_template_artifact_repository.dart';
import 'application/published_templates/published_template_artifact_repository.dart';
import 'application/published_templates/published_template_artifact_service.dart';
import 'application/real_scanner/published_scanner_resolver.dart';
import 'application/answer_sheet_packets/file_packet_response_repository.dart';
import 'application/answer_sheet_packets/in_memory_packet_response_repository.dart';
import 'application/answer_sheet_packets/packet_generation_service.dart';
import 'application/answer_sheet_packets/packet_response_repository.dart';
import 'debug/p5_native_validation_screen.dart';
import 'debug/p10_camera_diagnostics_screen.dart';
import 'debug/p11_camera_scanner_screen.dart';
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

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      home: MyHomePage(
        title: 'Flutter Demo Home Page',
        artifactRepository: artifactRepository,
        packetRepository: packetRepository,
      ),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({
    super.key,
    required this.title,
    this.artifactRepository,
    this.packetRepository,
  });

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;
  final PublishedTemplateArtifactRepository? artifactRepository;
  final PacketResponseRepository? packetRepository;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
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

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: .center,
          children: [
            const Text('You have pushed the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const P5NativeValidationScreen(),
                  ),
                ),
                child: const Text('Open P5 Native OpenCV Validation'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const P10CameraDiagnosticsScreen(),
                  ),
                ),
                child: const Text('Open P10 Camera Diagnostics'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const P11CameraScannerScreen(),
                  ),
                ),
                child: const Text('Open P11 Camera Scanner Diagnostics'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
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
                ),
                child: const Text('Open P12 Template Builder'),
              ),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RealScannerSelectionScreen(
                      resolver: PublishedScannerResolver(
                        artifactRepository: _artifactRepository,
                      ),
                      packetRepository: _packetRepository,
                    ),
                  ),
                ),
                child: const Text('Open Real Scanner Validation'),
              ),
            ],
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
