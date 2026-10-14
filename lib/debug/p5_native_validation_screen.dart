import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'p5_native_validation_runner.dart';

class P5NativeValidationScreen extends StatefulWidget {
  const P5NativeValidationScreen({super.key});

  @override
  State<P5NativeValidationScreen> createState() =>
      _P5NativeValidationScreenState();
}

class _P5NativeValidationScreenState extends State<P5NativeValidationScreen> {
  bool _running = false;
  P5NativeValidationReport? _report;

  Future<void> _run() async {
    if (!kDebugMode) return;
    setState(() {
      _running = true;
      _report = null;
    });
    final P5NativeValidationReport report = await runP5NativeValidation();
    report.printToDebugConsole();
    if (!mounted) return;
    setState(() {
      _running = false;
      _report = report;
    });
  }

  @override
  Widget build(BuildContext context) {
    assert(kDebugMode, 'P5 native validation is debug-only.');
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('P5 Native OpenCV Validation')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton(
              onPressed: _running ? null : _run,
              child: Text(
                _running
                    ? 'Running Native ArUco Test...'
                    : 'Run Native ArUco Test',
              ),
            ),
            if (report != null) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: report.text)),
                child: const Text('Copy Log'),
              ),
              const SizedBox(height: 8),
              Text(
                report.passed ? 'PASS' : 'FAIL',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(report.text),
                ),
              ),
            ] else
              const Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Text('P5 native gate status: UNVERIFIED'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
