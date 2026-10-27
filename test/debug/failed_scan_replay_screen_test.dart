import 'dart:typed_data';

import 'package:capstone_development/debug/failed_scan_replay_runner.dart';
import 'package:capstone_development/debug/failed_scan_replay_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('runs both bundled-capture modes and exposes diagnostics', (
    tester,
  ) async {
    var loaded = false;
    Uint8List? executedBytes;

    await tester.pumpWidget(
      MaterialApp(
        home: FailedScanReplayScreen(
          autoStart: true,
          bundleLoader: () async {
            loaded = true;
            return Uint8List.fromList([1, 2, 3]);
          },
          executor: (bytes) async {
            executedBytes = bytes;
            return FailedScanReplayOutput(
              reportJson:
                  '{"fourPointCandidate":{"accepted":false},'
                  '"multiPointCandidate":{"accepted":false}}',
              exportZip: Uint8List.fromList([80, 75]),
              summaries: const [
                'recorded-resolution four=rejected:FULL_CORNER_CONSISTENCY_EXCEEDED',
                'full-resolution multi=rejected:UNSAFE_INLIER_DISTRIBUTION',
              ],
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(loaded, isTrue);
    expect(executedBytes, orderedEquals([1, 2, 3]));
    expect(find.textContaining('recorded-resolution four=rejected'), findsOne);
    expect(find.textContaining('full-resolution multi=rejected'), findsOne);
    expect(
      find.byKey(const Key('export-failed-scan-replay-diagnostics')),
      findsOneWidget,
    );

    await tester.tap(find.text('Replay JSON'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('failed-scan-replay-json')), findsOneWidget);
    expect(find.textContaining('fourPointCandidate'), findsOneWidget);
    expect(find.textContaining('multiPointCandidate'), findsOneWidget);
  });
}
