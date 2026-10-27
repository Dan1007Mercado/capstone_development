import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'failed_scan_replay_runner.dart';

typedef FailedScanBundleLoader = Future<Uint8List> Function();

final class FailedScanReplayScreen extends StatefulWidget {
  const FailedScanReplayScreen({
    this.autoStart = false,
    this.bundleLoader,
    this.executor = runFailedScanReplay,
    super.key,
  });

  final bool autoStart;
  final FailedScanBundleLoader? bundleLoader;
  final FailedScanReplayExecutor executor;

  @override
  State<FailedScanReplayScreen> createState() => _FailedScanReplayScreenState();
}

final class _FailedScanReplayScreenState extends State<FailedScanReplayScreen> {
  static const _channel = MethodChannel(
    'com.example.capstone_development/debug_replay',
  );

  FailedScanReplayOutput? _output;
  String? _error;
  String? _exportLocation;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoStart) unawaited(_run());
  }

  Future<Uint8List> _loadBundledCapture() async {
    final bytes = await _channel.invokeMethod<Uint8List>(
      'loadBundledFailedScanCapture',
    );
    if (bytes == null || bytes.isEmpty) {
      throw StateError('The Android debug replay asset is empty.');
    }
    return bytes;
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
      _exportLocation = null;
    });
    try {
      final bytes = await (widget.bundleLoader ?? _loadBundledCapture)();
      final output = await widget.executor(bytes);
      if (!mounted) return;
      setState(() => _output = output);
    } on Object catch (error, stack) {
      debugPrint('Failed-scan replay error: $error\n$stack');
      if (!mounted) return;
      setState(() {
        _output = null;
        _error = error.toString();
      });
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _export() async {
    final output = _output;
    if (output == null) return;
    try {
      final location = await FilePicker.saveFile(
        dialogTitle: 'Export failed-scan replay diagnostics',
        fileName: 'talaanscan_failed_capture_replay_diagnostics.zip',
        bytes: output.exportZip,
        mimeType: 'application/zip',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (!mounted) return;
      setState(() => _exportLocation = location?.toString());
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Diagnostics export failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final output = _output;
    return Scaffold(
      appBar: AppBar(title: const Text('Bundled Failed-Scan Replay')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Runs the bundled physical capture at its recorded detector '
            'resolution and at full resolution using native OpenCV. This '
            'diagnostic does not alter production scanner behavior.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('run-bundled-failed-scan-replay'),
            onPressed: _running ? null : () => unawaited(_run()),
            icon: const Icon(Icons.replay),
            label: Text(_running ? 'Running on device…' : 'Run Both Replays'),
          ),
          if (_running) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: 12),
            SelectableText(
              error,
              key: const Key('failed-scan-replay-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (output != null) ...[
            const SizedBox(height: 16),
            Text('Results', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final summary in output.summaries)
              SelectableText(summary, key: ValueKey(summary)),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('export-failed-scan-replay-diagnostics'),
              onPressed: () => unawaited(_export()),
              icon: const Icon(Icons.save_alt),
              label: const Text('Export JSON and Overlays'),
            ),
            if (_exportLocation case final location?)
              SelectableText('Saved: $location'),
            const SizedBox(height: 12),
            ExpansionTile(
              title: const Text('Replay JSON'),
              children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SelectableText(
                    output.reportJson,
                    key: const Key('failed-scan-replay-json'),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
