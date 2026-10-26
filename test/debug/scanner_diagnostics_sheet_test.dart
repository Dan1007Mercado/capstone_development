import 'dart:io';

import 'package:capstone_development/debug/scanner_diagnostics_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('copy button writes the report before confirming success', (
    tester,
  ) async {
    String? copied;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScannerDiagnosticsSheet(
            report: 'SCANNER DEBUG REPORT\nState: rejected',
            clipboardWriter: (text) async => copied = text,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('copy-scanner-debug-results')));
    await tester.pump();

    expect(copied, contains('State: rejected'));
    expect(find.text('Debug results copied.'), findsOneWidget);
  });

  testWidgets('clipboard failure never shows a success confirmation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScannerDiagnosticsSheet(
            report: 'report',
            clipboardWriter: (_) => Future<void>.error(StateError('denied')),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('copy-scanner-debug-results')));
    await tester.pump();

    expect(find.text('Debug results copied.'), findsNothing);
    expect(find.text('Could not copy debug results.'), findsOneWidget);
  });

  test('opening diagnostics does not invoke camera lifecycle operations', () {
    final source = File(
      'lib/debug/real_scanner_validation_screen.dart',
    ).readAsStringSync();
    final start = source.indexOf('void _showScannerDiagnostics()');
    final end = source.indexOf('\n  void _claimPacketResult', start);
    final method = source.substring(start, end);

    expect(method, contains('showModalBottomSheet'));
    expect(method, isNot(contains('.suspend()')));
    expect(method, isNot(contains('.stopAnalysis()')));
    expect(method, isNot(contains('.captureAndScan()')));
  });
}
