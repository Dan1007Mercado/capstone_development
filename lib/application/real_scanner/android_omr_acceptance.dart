import 'dart:collection';

import '../../core/errors/engine_error.dart';
import '../../engines/scanner/domain/scan_result.dart';
import '../../engines/recognition/application/bubble_alignment_evidence.dart';
import 'physical_validation_recorder.dart';

enum AndroidOmrScenario {
  a4Flat,
  moderateTilt,
  oneSidedShadow,
  letterFitToPage,
  reducedPrintScale,
}

/// One local, non-persisting physical attempt. The UI may export the resulting
/// JSON, but this model never writes a response submission.
final class AndroidOmrAcceptanceAttempt {
  const AndroidOmrAcceptanceAttempt({
    required this.scenario,
    required this.attemptNumber,
    required this.deviceModel,
    required this.startedAtUtc,
    required this.cameraCaptureDuration,
    required this.duration,
    required this.expectedPlan,
    this.result,
    this.failure,
    this.bubbleAlignmentEvidence,
  }) : assert((result == null) != (failure == null));

  final AndroidOmrScenario scenario;
  final int attemptNumber;
  final String deviceModel;
  final DateTime startedAtUtc;
  final Duration cameraCaptureDuration;
  final Duration duration;
  final PhysicalValidationPlan expectedPlan;
  final ScanResult? result;
  final EngineError? failure;
  final BubbleAlignmentEvidence? bubbleAlignmentEvidence;

  Map<String, Object?> toJson() {
    final scan = result;
    final validation = scan == null
        ? null
        : PhysicalValidationReport.record(plan: expectedPlan, results: [scan]);
    return {
      'scenario': scenario.name,
      'attemptNumber': attemptNumber,
      'deviceModel': deviceModel,
      'startedAtUtc': startedAtUtc.toUtc().toIso8601String(),
      'cameraCaptureMs': cameraCaptureDuration.inMicroseconds / 1000,
      'markerDetectionMs': scan == null
          ? null
          : scan.diagnostics.alignment.detectionDuration.inMicroseconds / 1000,
      'durationMs': duration.inMicroseconds / 1000,
      'accepted': scan != null,
      'alignmentValidation': scan != null ? 'accepted' : 'rejected',
      'failureCode': failure?.code,
      'selectedMethod':
          scan?.diagnostics.alignment.selectedHomographyMethod.name,
      'selectionReason': scan?.diagnostics.alignment.selectionReason,
      'fallbackReason': scan?.diagnostics.alignment.fallbackReason,
      'fourPointAccepted':
          scan?.diagnostics.alignment.fourPointCandidate?.accepted,
      'multiPointAccepted':
          scan?.diagnostics.alignment.multiPointCandidate?.accepted,
      'bubbleOutlineEvidence': bubbleAlignmentEvidence == null
          ? null
          : {
              'status': bubbleAlignmentEvidence!.status.name,
              'meanCenterDisplacementPixels':
                  bubbleAlignmentEvidence!.meanCenterDisplacementPixels,
              'p95CenterDisplacementPixels':
                  bubbleAlignmentEvidence!.percentile95CenterDisplacementPixels,
              'coverage': bubbleAlignmentEvidence!.observedCoverage,
              'confidenceScore': bubbleAlignmentEvidence!.confidenceScore,
              'reason': bubbleAlignmentEvidence!.inconclusiveReason,
            },
      'validation': validation?.toJson(),
    };
  }
}

final class AndroidOmrAcceptanceReport {
  AndroidOmrAcceptanceReport._({
    required Iterable<AndroidOmrAcceptanceAttempt> attempts,
    required this.summary,
  }) : attempts = UnmodifiableListView(List.of(attempts));

  factory AndroidOmrAcceptanceReport.build(
    Iterable<AndroidOmrAcceptanceAttempt> values, {
    int requiredAttemptsPerScenario = 5,
    String requiredDeviceModel = 'Infinix X6711',
  }) {
    final attempts = values.toList(growable: false);
    final durations =
        attempts.map((item) => item.duration.inMicroseconds).toList()..sort();
    final accepted = attempts.where((item) => item.result != null).toList();
    final validations = [
      for (final attempt in accepted)
        PhysicalValidationReport.record(
          plan: attempt.expectedPlan,
          results: [attempt.result!],
        ),
    ];
    final totalQuestions = validations.fold<int>(
      0,
      (sum, report) => sum + report.summary.totalQuestions,
    );
    final correct = validations.fold<int>(
      0,
      (sum, report) => sum + report.summary.correct,
    );
    int total(int Function(PhysicalValidationSummary summary) select) =>
        validations.fold(0, (sum, report) => sum + select(report.summary));
    final methodFrequency = <String, int>{};
    for (final attempt in accepted) {
      final method =
          attempt.result!.diagnostics.alignment.selectedHomographyMethod.name;
      methodFrequency[method] = (methodFrequency[method] ?? 0) + 1;
    }
    final counts = {
      for (final scenario in AndroidOmrScenario.values)
        scenario.name: attempts
            .where((item) => item.scenario == scenario)
            .length,
    };
    final complete =
        attempts.every((item) => item.deviceModel == requiredDeviceModel) &&
        counts.values.every((count) => count >= requiredAttemptsPerScenario);
    final questionRecords = [
      for (final validation in validations) ...validation.questions,
    ];
    return AndroidOmrAcceptanceReport._(
      attempts: attempts,
      summary: {
        'deviceModel': requiredDeviceModel,
        'matrixComplete': complete,
        'attemptCounts': counts,
        'acceptedAttempts': accepted.length,
        'rejectedAttempts': attempts.length - accepted.length,
        'acceptedQuestionAccuracy': totalQuestions == 0
            ? null
            : correct / totalQuestions,
        'falsePositiveMarks': total((s) => s.falsePositiveMarks),
        'falseBlanks': total((s) => s.falseBlank),
        'falseMultipleMarks': questionRecords
            .where(
              (record) =>
                  record.expected.state != record.detected.state &&
                  record.detected.state.name == 'multiple',
            )
            .length,
        'wrongConfident': total((s) => s.wrongConfidentCount),
        'latencyP50Ms': _percentile(durations, 0.50),
        'latencyP95Ms': _percentile(durations, 0.95),
        'methodFrequency': methodFrequency,
        'rejectionFrequency': {
          for (final code
              in attempts
                  .map((item) => item.failure?.code)
                  .whereType<String>()
                  .toSet())
            code: attempts.where((item) => item.failure?.code == code).length,
        },
      },
    );
  }

  final List<AndroidOmrAcceptanceAttempt> attempts;
  final Map<String, Object?> summary;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'summary': summary,
    'attempts': attempts.map((item) => item.toJson()).toList(),
  };

  static double? _percentile(List<int> sortedMicros, double percentile) {
    if (sortedMicros.isEmpty) return null;
    final index = ((sortedMicros.length * percentile).ceil() - 1).clamp(
      0,
      sortedMicros.length - 1,
    );
    return sortedMicros[index] / 1000;
  }
}
