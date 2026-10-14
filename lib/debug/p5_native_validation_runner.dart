import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/errors/engine_error.dart';
import '../engines/aruco/application/aruco_alignment_engine.dart';
import '../engines/aruco/domain/aruco_alignment_config.dart';
import '../engines/aruco/infrastructure/opencv_aruco_vision_backend.dart';
import 'p5_native_validation_fixture.dart';

final class P5NativeValidationReport {
  P5NativeValidationReport({
    required Iterable<String> lines,
    required this.passed,
  }) : lines = UnmodifiableListView(List.of(lines));

  final List<String> lines;
  final bool passed;

  String get text => lines.map((line) => '[P5_NATIVE] $line').join('\n');

  void printToDebugConsole() {
    for (final line in lines) {
      debugPrint('[P5_NATIVE] $line');
    }
  }
}

Future<P5NativeValidationReport> runP5NativeValidation() async {
  final lines = <String>[
    'platform=${Platform.operatingSystem}',
    'platformVersion=${Platform.operatingSystemVersion}',
    'gateStatus=UNVERIFIED',
    'expectedMarkerIds=$p5NativeValidationExpectedMarkerIds',
  ];

  try {
    final page = buildP5NativeValidationPage();
    final expectedWidth = page.canonicalPageSpec.widthPixels;
    final expectedHeight = page.canonicalPageSpec.heightPixels;
    lines.add('expectedCanonical=${expectedWidth}x$expectedHeight');

    final bytes = renderP5NativeValidationPng(page);
    final backend = const OpenCvArucoVisionBackend();
    final backendResult = backend.open(bytes, ArucoAlignmentConfig());
    if (backendResult.isFailure) {
      lines.add('backend=failure');
      _appendEngineError(lines, backendResult.error);
      _appendUnavailableAlignment(lines);
      lines.add('verdict=FAIL');
      return P5NativeValidationReport(lines: lines, passed: false);
    }

    final session = backendResult.value;
    final detectedIds =
        session.detection.markers
            .map((marker) => marker.id)
            .toList(growable: false)
          ..sort();
    lines.addAll([
      'backend=success',
      'detectedIds=$detectedIds',
      'detectedMarkerCount=${detectedIds.length}',
    ]);
    session.dispose();

    final alignment = ArucoAlignmentEngine(backend: backend).align(bytes, page);
    if (alignment.isFailure) {
      lines.add('alignment=failure');
      _appendEngineError(lines, alignment.error);
      lines.addAll([
        'homographyAvailable=false',
        'meanReprojectionError=unavailable',
        'maxReprojectionError=unavailable',
        'sourceRegistrationPointsCount=0',
        'destinationRegistrationPointsCount=0',
        'canonical=unavailable',
        'verdict=FAIL',
      ]);
      return P5NativeValidationReport(lines: lines, passed: false);
    }

    final result = alignment.value;
    final diagnostics = result.diagnostics;
    final canonical = result.canonicalPage.size;
    final detectedAllExpected =
        detectedIds.length == p5NativeValidationExpectedMarkerIds.length &&
        detectedIds.toSet().containsAll(p5NativeValidationExpectedMarkerIds);
    final dimensionsMatch =
        canonical.width == expectedWidth && canonical.height == expectedHeight;
    final passed = Platform.isAndroid && detectedAllExpected && dimensionsMatch;
    lines.addAll([
      'alignment=success',
      'homographyAvailable=true',
      'meanReprojectionError=${diagnostics.meanReprojectionError}',
      'maxReprojectionError=${diagnostics.maxReprojectionError}',
      'sourceRegistrationPointsCount=${diagnostics.sourceRegistrationPoints.length}',
      'destinationRegistrationPointsCount=${diagnostics.destinationRegistrationPoints.length}',
      'canonical=${canonical.width}x${canonical.height}',
      if (!Platform.isAndroid) 'failureReason=Android device required',
      if (!detectedAllExpected)
        'failureReason=Required marker IDs do not match',
      if (!dimensionsMatch) 'failureReason=Canonical dimensions do not match',
      'verdict=${passed ? 'PASS' : 'FAIL'}',
    ]);
    return P5NativeValidationReport(lines: lines, passed: passed);
  } on Object catch (error, stackTrace) {
    lines.addAll([
      'backend=failure',
      'exceptionType=${error.runtimeType}',
      'exception=$error',
      'stackTrace=$stackTrace',
    ]);
    if (error is EngineError) {
      _appendEngineError(lines, error, prefix: 'child');
    }
    _appendUnavailableAlignment(lines);
    lines.add('verdict=FAIL');
    return P5NativeValidationReport(lines: lines, passed: false);
  }
}

void _appendEngineError(
  List<String> lines,
  EngineError error, {
  String prefix = '',
}) {
  final keyPrefix = prefix.isEmpty ? '' : '${prefix}EngineError.';
  lines.add('${keyPrefix}code=${error.code}');
  lines.add('${keyPrefix}message=${error.message}');
  lines.add('${keyPrefix}details=${error.details}');
  final cause = error.details['cause'];
  if (cause != null) lines.add('${keyPrefix}cause=$cause');
  if (cause is EngineError) {
    _appendEngineError(lines, cause, prefix: 'child');
  }
}

void _appendUnavailableAlignment(List<String> lines) {
  lines.addAll(const [
    'detectedIds=[]',
    'detectedMarkerCount=0',
    'alignment=failure',
    'homographyAvailable=false',
    'meanReprojectionError=unavailable',
    'maxReprojectionError=unavailable',
    'sourceRegistrationPointsCount=0',
    'destinationRegistrationPointsCount=0',
    'canonical=unavailable',
  ]);
}
