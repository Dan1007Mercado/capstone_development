import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef ScannerDebugClipboardWriter = Future<void> Function(String text);
typedef FailedCaptureExporter = Future<String?> Function();

Future<void> _writeScannerDebugClipboard(String text) =>
    Clipboard.setData(ClipboardData(text: text));

class ScannerDiagnosticsSheet extends StatelessWidget {
  const ScannerDiagnosticsSheet({
    required this.report,
    this.clipboardWriter = _writeScannerDebugClipboard,
    this.failedCaptureExporter,
    super.key,
  });

  final String report;
  final ScannerDebugClipboardWriter clipboardWriter;
  final FailedCaptureExporter? failedCaptureExporter;

  Future<void> _copy(BuildContext context) async {
    try {
      await clipboardWriter(report);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Debug results copied.')));
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not copy debug results.')),
      );
    }
  }

  Future<void> _exportFailedCapture(BuildContext context) async {
    try {
      final path = await failedCaptureExporter!();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            path == null
                ? 'Failed capture export dismissed; retained bytes cleared.'
                : 'Failed capture exported to $path. It may contain handwritten personal information.',
          ),
        ),
      );
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not export failed capture.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FractionallySizedBox(
      heightFactor: 0.86,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Scanner Diagnostics',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Close diagnostics',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  report,
                  key: const Key('scanner-debug-report'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (failedCaptureExporter != null) ...[
              OutlinedButton.icon(
                key: const Key('export-failed-scanner-capture'),
                onPressed: () => _exportFailedCapture(context),
                icon: const Icon(Icons.save_alt),
                label: const Text('Export Failed Capture'),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton.icon(
              key: const Key('copy-scanner-debug-results'),
              onPressed: () => _copy(context),
              icon: const Icon(Icons.copy),
              label: const Text('Copy Debug Results'),
            ),
          ],
        ),
      ),
    ),
  );
}
