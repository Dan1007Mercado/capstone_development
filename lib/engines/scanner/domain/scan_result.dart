import 'dart:collection';

import '../../../core/ids/identifiers.dart';
import '../../aruco/domain/page_alignment_result.dart';
import '../../preprocessing/domain/preprocessed_page.dart';
import '../../recognition/domain/mark_classification.dart';

enum ScanStage {
  alignment,
  preprocessing,
  measurement,
  classification,
  complete,
}

enum ScanPageState { accepted, needsReview, invalid }

enum ScanReviewReason {
  requiredQuestionBlank,
  ambiguousQuestion,
  multipleSelection,
  invalidQuestion,
  lowQualityMeasurement,
}

final class ScanSummary {
  const ScanSummary({
    required this.totalQuestions,
    required this.marked,
    required this.blank,
    required this.multiple,
    required this.ambiguous,
    required this.invalid,
    required this.requiredBlank,
    required this.measuredBubbles,
  });

  final int totalQuestions;
  final int marked;
  final int blank;
  final int multiple;
  final int ambiguous;
  final int invalid;
  final int requiredBlank;
  final int measuredBubbles;
}

final class ScanStageDurations {
  const ScanStageDurations({
    required this.alignment,
    required this.preprocessing,
    required this.measurement,
    required this.classification,
    this.validation = Duration.zero,
  });

  final Duration alignment;
  final Duration preprocessing;
  final Duration measurement;
  final Duration classification;
  final Duration validation;
}

final class ScanDiagnostics {
  const ScanDiagnostics({
    required this.totalProcessingDuration,
    required this.stageDurations,
    required this.alignment,
    required this.preprocessing,
    required this.summary,
  });

  final Duration totalProcessingDuration;
  final ScanStageDurations stageDurations;
  final PageAlignmentDiagnostics alignment;
  final PreprocessingDiagnostics preprocessing;
  final ScanSummary summary;
}

final class ScanResult {
  ScanResult({
    required this.templateId,
    required this.templateVersion,
    required this.pageId,
    required Iterable<QuestionClassification> questions,
    required this.pageState,
    required Iterable<ScanReviewReason> reviewReasons,
    required Iterable<QuestionId> reviewQuestionIds,
    required this.diagnostics,
  }) : questions = UnmodifiableListView(List.of(questions)),
       reviewReasons = UnmodifiableListView(List.of(reviewReasons)),
       reviewQuestionIds = UnmodifiableListView(List.of(reviewQuestionIds));

  final TemplateId templateId;
  final TemplateVersion templateVersion;
  final PageId pageId;
  final List<QuestionClassification> questions;
  final ScanPageState pageState;
  final List<ScanReviewReason> reviewReasons;
  final List<QuestionId> reviewQuestionIds;
  final ScanDiagnostics diagnostics;

  ScanSummary get summary => diagnostics.summary;
}
