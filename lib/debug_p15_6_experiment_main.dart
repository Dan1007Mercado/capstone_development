import 'dart:async';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'debug/p15_6_experiment.dart' as experiment;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Text(
            'P15.6 native experiment. Results are written to app files.',
          ),
        ),
      ),
    ),
  );
  unawaited(
    Isolate.run(() {
      for (final mode in const String.fromEnvironment(
        'P156_MODES',
        defaultValue: 'baseline',
      ).split(',')) {
        experiment.main([
          String.fromEnvironment(
            'P156_INPUT',
            defaultValue:
                '/data/user/0/com.example.capstone_development/files/p156-input',
          ),
          '${const String.fromEnvironment('P156_OUTPUT', defaultValue: '/sdcard/Android/data/com.example.capstone_development/files/p156-after')}/$mode',
          if (mode != 'baseline') mode,
        ]);
      }
    }),
  );
}
