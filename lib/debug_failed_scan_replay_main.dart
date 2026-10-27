import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'debug/failed_scan_replay_screen.dart';

void main() {
  if (!kDebugMode) {
    throw StateError('The bundled failed-scan replay is debug-only.');
  }
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FailedScanReplayScreen(autoStart: true),
    ),
  );
}
