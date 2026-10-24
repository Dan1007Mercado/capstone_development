import 'dart:collection';

import '../../core/ids/identifiers.dart';
import '../../engines/recognition/domain/mark_classification.dart';
import '../../engines/scanner/domain/scan_result.dart';
import '../../engines/template/domain/question_type.dart';

enum ScanAcceptanceDecision {
  accept,
  rescanBlankPage,
  rescanAmbiguous,
  rescanInvalid,
}

final class ScanAcceptanceResult {
  ScanAcceptanceResult({
    required this.decision,
    required Iterable<QuestionId> questionIds,
  }) : questionIds = UnmodifiableListView(List.of(questionIds));

  final ScanAcceptanceDecision decision;
  final List<QuestionId> questionIds;

  bool get accepted => decision == ScanAcceptanceDecision.accept;

  String get title => switch (decision) {
    ScanAcceptanceDecision.accept => 'Scan accepted',
    ScanAcceptanceDecision.rescanBlankPage => 'Blank answer sheet detected',
    ScanAcceptanceDecision.rescanAmbiguous => 'Unclear answers detected',
    ScanAcceptanceDecision.rescanInvalid =>
      'The sheet could not be read reliably',
  };

  String get guidance => switch (decision) {
    ScanAcceptanceDecision.accept => '',
    ScanAcceptanceDecision.rescanBlankPage =>
      'No marked answers were found on this page. Please verify the sheet and scan again.',
    ScanAcceptanceDecision.rescanAmbiguous =>
      questionIds.isEmpty
          ? 'Please scan this page again.'
          : 'Questions: ${questionIds.map((id) => id.value).join(', ')}. Please scan this page again.',
    ScanAcceptanceDecision.rescanInvalid =>
      'Please flatten the page, improve lighting, and scan again.',
  };
}

final class ScanAcceptancePolicy {
  const ScanAcceptancePolicy();

  ScanAcceptanceResult evaluate(ScanResult result) {
    final questions = result.questions;
    if (questions.isNotEmpty &&
        questions.every((question) => question.state == MarkState.blank)) {
      return ScanAcceptanceResult(
        decision: ScanAcceptanceDecision.rescanBlankPage,
        questionIds: questions.map((question) => question.questionId),
      );
    }

    final invalid = questions
        .where((question) => question.state == MarkState.invalid)
        .map((question) => question.questionId)
        .toSet();
    if (result.pageState == ScanPageState.invalid || invalid.isNotEmpty) {
      return ScanAcceptanceResult(
        decision: ScanAcceptanceDecision.rescanInvalid,
        questionIds: invalid,
      );
    }

    final unclear = <QuestionId>{};
    for (final question in questions) {
      if (question.state == MarkState.ambiguous) {
        unclear.add(question.questionId);
      }
      if (question.state == MarkState.multiple &&
          question.questionType != QuestionType.multipleChoice) {
        unclear.add(question.questionId);
      }
      if (question.questionType == QuestionType.numericGrid) {
        final selection = question.numericSelection;
        if (selection == null || selection.completeDigitString == null) {
          if (question.state != MarkState.blank ||
              selection?.columns.any(
                    (column) => column.state != MarkState.blank,
                  ) ==
                  true) {
            unclear.add(question.questionId);
          }
        }
      }
    }
    if (result.reviewReasons.contains(ScanReviewReason.requiredQuestionBlank)) {
      unclear.addAll(result.reviewQuestionIds);
    }
    if (unclear.isNotEmpty || result.pageState == ScanPageState.needsReview) {
      return ScanAcceptanceResult(
        decision: ScanAcceptanceDecision.rescanAmbiguous,
        questionIds: unclear.isEmpty ? result.reviewQuestionIds : unclear,
      );
    }
    return ScanAcceptanceResult(
      decision: ScanAcceptanceDecision.accept,
      questionIds: const [],
    );
  }
}
