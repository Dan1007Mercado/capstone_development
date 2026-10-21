import 'dart:collection';

import '../../core/ids/identifiers.dart';
import '../../engines/recognition/domain/bubble_measurement.dart';
import '../../engines/recognition/domain/mark_classification.dart';
import '../../engines/scanner/domain/scanner_diagnostic_snapshot.dart';

final class DiagnosticBubbleIdentity {
  const DiagnosticBubbleIdentity({
    required this.questionId,
    required this.optionId,
    required this.numericColumnIndex,
    required this.numericDigitValue,
  });

  final QuestionId questionId;
  final OptionId? optionId;
  final int? numericColumnIndex;
  final int? numericDigitValue;

  String get label => optionId == null
      ? '${questionId.value}-C$numericColumnIndex-$numericDigitValue'
      : '${questionId.value}-${optionId!.value}';

  @override
  bool operator ==(Object other) =>
      other is DiagnosticBubbleIdentity &&
      other.questionId == questionId &&
      other.optionId == optionId &&
      other.numericColumnIndex == numericColumnIndex &&
      other.numericDigitValue == numericDigitValue;

  @override
  int get hashCode =>
      Object.hash(questionId, optionId, numericColumnIndex, numericDigitValue);
}

final class DiagnosticBubbleEvidence {
  const DiagnosticBubbleEvidence({
    required this.scanSequenceIndex,
    required this.identity,
    required this.fillRatio,
    required this.normalizedDarkness,
    required this.darknessContrast,
    required this.combinedScore,
    required this.category,
    required this.decisionState,
    required this.questionState,
  });

  final int scanSequenceIndex;
  final DiagnosticBubbleIdentity identity;
  final double fillRatio;
  final double normalizedDarkness;
  final double darknessContrast;
  final double combinedScore;
  final BubbleEvidenceCategory category;
  final BubbleDecisionState decisionState;
  final MarkState questionState;
}

final class RoiDiagnosticEvidenceScan {
  RoiDiagnosticEvidenceScan({
    required this.scanSequenceIndex,
    required this.templateId,
    required this.templateVersion,
    required this.pageId,
    required Iterable<DiagnosticBubbleEvidence> bubbles,
  }) : bubbles = UnmodifiableListView(List.of(bubbles));

  factory RoiDiagnosticEvidenceScan.fromSnapshot(
    ScannerDiagnosticSnapshot snapshot,
  ) {
    final classifications = {
      for (final question in snapshot.classification.questions)
        question.questionId: question,
    };
    return RoiDiagnosticEvidenceScan(
      scanSequenceIndex: snapshot.scanSequenceIndex,
      templateId: snapshot.templateId,
      templateVersion: snapshot.templateVersion,
      pageId: snapshot.pageId,
      bubbles: [
        for (final measurement in snapshot.measurements.measurements)
          _evidenceFor(
            measurement,
            classifications[measurement.questionId]!,
            snapshot.scanSequenceIndex,
          ),
      ],
    );
  }

  final int scanSequenceIndex;
  final TemplateId templateId;
  final TemplateVersion templateVersion;
  final PageId pageId;
  final List<DiagnosticBubbleEvidence> bubbles;

  static DiagnosticBubbleEvidence _evidenceFor(
    BubbleMeasurement measurement,
    QuestionClassification question,
    int scanSequenceIndex,
  ) {
    final decision = question.bubbleDecisions.singleWhere(
      (candidate) =>
          candidate.optionId == measurement.optionId &&
          candidate.numericColumnIndex == measurement.numericColumnIndex &&
          candidate.numericDigitValue == measurement.numericDigitValue,
    );
    return DiagnosticBubbleEvidence(
      scanSequenceIndex: scanSequenceIndex,
      identity: DiagnosticBubbleIdentity(
        questionId: measurement.questionId,
        optionId: measurement.optionId,
        numericColumnIndex: measurement.numericColumnIndex,
        numericDigitValue: measurement.numericDigitValue,
      ),
      fillRatio: measurement.fillRatio,
      normalizedDarkness: measurement.normalizedDarkness,
      darknessContrast: measurement.darknessContrast,
      combinedScore: decision.combinedScore,
      category: decision.category,
      decisionState: decision.state,
      questionState: question.state,
    );
  }
}

final class DiagnosticBubbleStabilitySummary {
  const DiagnosticBubbleStabilitySummary({
    required this.scanCount,
    required this.minimumFillRatio,
    required this.maximumFillRatio,
    required this.minimumNormalizedDarkness,
    required this.maximumNormalizedDarkness,
    required this.minimumDarknessContrast,
    required this.maximumDarknessContrast,
    required this.minimumCombinedScore,
    required this.maximumCombinedScore,
    required this.categoryChanges,
    required this.stateChanges,
  });

  final int scanCount;
  final double minimumFillRatio;
  final double maximumFillRatio;
  final double minimumNormalizedDarkness;
  final double maximumNormalizedDarkness;
  final double minimumDarknessContrast;
  final double maximumDarknessContrast;
  final double minimumCombinedScore;
  final double maximumCombinedScore;
  final int categoryChanges;
  final int stateChanges;
}

final class RoiDiagnosticHistory {
  RoiDiagnosticHistory({
    this.capacity = 5,
    Iterable<RoiDiagnosticEvidenceScan> scans = const [],
  }) : assert(capacity > 0),
       scans = UnmodifiableListView(List.of(scans));

  final int capacity;
  final List<RoiDiagnosticEvidenceScan> scans;

  /// History intentionally retains numeric evidence only.
  int get retainedCanonicalImageByteCount => 0;

  RoiDiagnosticHistory record(ScannerDiagnosticSnapshot snapshot) {
    final updated = [
      ...scans,
      RoiDiagnosticEvidenceScan.fromSnapshot(snapshot),
    ];
    final retained = updated.length <= capacity
        ? updated
        : updated.sublist(updated.length - capacity);
    return RoiDiagnosticHistory(capacity: capacity, scans: retained);
  }

  RoiDiagnosticHistory clear() => RoiDiagnosticHistory(capacity: capacity);

  List<DiagnosticBubbleEvidence> evidenceFor(
    DiagnosticBubbleIdentity identity,
  ) => [
    for (final scan in scans)
      for (final evidence in scan.bubbles)
        if (evidence.identity == identity) evidence,
  ];

  DiagnosticBubbleStabilitySummary? summarize(
    DiagnosticBubbleIdentity identity,
  ) {
    final evidence = evidenceFor(identity);
    if (evidence.isEmpty) return null;
    var categoryChanges = 0;
    var stateChanges = 0;
    for (var index = 1; index < evidence.length; index++) {
      if (evidence[index].category != evidence[index - 1].category) {
        categoryChanges++;
      }
      if (evidence[index].questionState != evidence[index - 1].questionState) {
        stateChanges++;
      }
    }
    return DiagnosticBubbleStabilitySummary(
      scanCount: evidence.length,
      minimumFillRatio: evidence.map((item) => item.fillRatio).reduce(_min),
      maximumFillRatio: evidence.map((item) => item.fillRatio).reduce(_max),
      minimumNormalizedDarkness: evidence
          .map((item) => item.normalizedDarkness)
          .reduce(_min),
      maximumNormalizedDarkness: evidence
          .map((item) => item.normalizedDarkness)
          .reduce(_max),
      minimumDarknessContrast: evidence
          .map((item) => item.darknessContrast)
          .reduce(_min),
      maximumDarknessContrast: evidence
          .map((item) => item.darknessContrast)
          .reduce(_max),
      minimumCombinedScore: evidence
          .map((item) => item.combinedScore)
          .reduce(_min),
      maximumCombinedScore: evidence
          .map((item) => item.combinedScore)
          .reduce(_max),
      categoryChanges: categoryChanges,
      stateChanges: stateChanges,
    );
  }

  static double _min(double first, double second) =>
      first < second ? first : second;
  static double _max(double first, double second) =>
      first > second ? first : second;
}
