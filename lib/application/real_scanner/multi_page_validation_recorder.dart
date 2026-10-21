import 'dart:collection';

import '../../core/ids/identifiers.dart';
import '../../engines/layout/domain/page_layout.dart';
import '../../engines/scanner/domain/scan_result.dart';
import 'published_scanner_resolver.dart';

enum MultiPageValidationAttemptOutcome {
  accepted,
  duplicateRejected,
  identityRejected,
  sessionRejected,
}

final class MultiPageValidationPlan {
  MultiPageValidationPlan({
    required this.templateId,
    required this.templateVersion,
    required Iterable<PageId> requiredPageIds,
    required Iterable<PageId> expectedCaptureOrder,
  }) : requiredPageIds = UnmodifiableListView(List.of(requiredPageIds)),
       expectedCaptureOrder = UnmodifiableListView(
         List.of(expectedCaptureOrder),
       );

  final TemplateId templateId;
  final TemplateVersion templateVersion;
  final List<PageId> requiredPageIds;
  final List<PageId> expectedCaptureOrder;
}

MultiPageValidationPlan? buildP13_9MultiPageValidationPlan(
  PublishedScannerArtifact artifact,
) {
  final pages = artifact.layout.pages;
  if (artifact.templateId.value != 'p11-1-scanner-validation' ||
      artifact.templateVersion.value != 1 ||
      pages.length != 3) {
    return null;
  }
  final pageIds = pages.map((page) => page.pageId).toList(growable: false);
  return MultiPageValidationPlan(
    templateId: artifact.templateId,
    templateVersion: artifact.templateVersion,
    requiredPageIds: pageIds,
    expectedCaptureOrder: [pageIds[1], pageIds[0], pageIds[2], pageIds[1]],
  );
}

final class MultiPageValidationAttempt {
  MultiPageValidationAttempt({
    required this.templateId,
    required this.templateVersion,
    required this.expectedPageId,
    required this.detectedPageId,
    required Iterable<int> detectedMarkerIds,
    required this.captureSequenceIndex,
    required this.outcome,
    required this.processingDuration,
    required this.completedUniquePageCount,
    required Iterable<PageId> missingPageIds,
    this.rejectionCode,
  }) : detectedMarkerIds = UnmodifiableListView(List.of(detectedMarkerIds)),
       missingPageIds = UnmodifiableListView(List.of(missingPageIds));

  final TemplateId templateId;
  final TemplateVersion templateVersion;
  final PageId? expectedPageId;
  final PageId? detectedPageId;
  final List<int> detectedMarkerIds;
  final int captureSequenceIndex;
  final MultiPageValidationAttemptOutcome outcome;
  final String? rejectionCode;
  final Duration processingDuration;
  final int completedUniquePageCount;
  final List<PageId> missingPageIds;

  bool get duplicate =>
      outcome == MultiPageValidationAttemptOutcome.duplicateRejected;
  bool get accepted => outcome == MultiPageValidationAttemptOutcome.accepted;
  bool get wrongPageDetection =>
      expectedPageId != null &&
      detectedPageId != null &&
      expectedPageId != detectedPageId;

  Map<String, Object?> toJson() => {
    'templateId': templateId.value,
    'templateVersion': templateVersion.value,
    'expectedPageId': expectedPageId?.value,
    'detectedPageId': detectedPageId?.value,
    'detectedMarkerIds': detectedMarkerIds,
    'captureSequenceIndex': captureSequenceIndex,
    'duplicate': duplicate,
    'outcome': outcome.name,
    'accepted': accepted,
    'rejectionCode': rejectionCode,
    'processingMs': processingDuration.inMicroseconds / 1000,
    'completedUniquePageCount': completedUniquePageCount,
    'missingPageIds': missingPageIds.map((id) => id.value).toList(),
  };
}

final class MultiPageValidationSummary {
  MultiPageValidationSummary({
    required this.requiredPages,
    required this.uniqueAcceptedPages,
    required this.duplicateAttempts,
    required this.wrongPageDetections,
    required this.rejectedIdentityAttempts,
    required this.sessionComplete,
    required Iterable<PageId> finalPageOrder,
    required this.totalProcessingDuration,
    required this.averageProcessingDuration,
  }) : finalPageOrder = UnmodifiableListView(List.of(finalPageOrder));

  final int requiredPages;
  final int uniqueAcceptedPages;
  final int duplicateAttempts;
  final int wrongPageDetections;
  final int rejectedIdentityAttempts;
  final bool sessionComplete;
  final List<PageId> finalPageOrder;
  final Duration totalProcessingDuration;
  final Duration averageProcessingDuration;

  Map<String, Object?> toJson() => {
    'requiredPages': requiredPages,
    'uniqueAcceptedPages': uniqueAcceptedPages,
    'duplicateAttempts': duplicateAttempts,
    'wrongPageDetections': wrongPageDetections,
    'rejectedIdentityAttempts': rejectedIdentityAttempts,
    'sessionComplete': sessionComplete,
    'finalPageOrder': finalPageOrder.map((id) => id.value).toList(),
    'totalProcessingMs': totalProcessingDuration.inMicroseconds / 1000,
    'averageProcessingMs': averageProcessingDuration.inMicroseconds / 1000,
  };
}

final class MultiPageValidationReport {
  MultiPageValidationReport({
    required this.plan,
    required Iterable<MultiPageValidationAttempt> attempts,
    required this.summary,
  }) : attempts = UnmodifiableListView(List.of(attempts));

  factory MultiPageValidationReport.build({
    required MultiPageValidationPlan plan,
    required Iterable<MultiPageValidationAttempt> attempts,
    required Iterable<ScanResult> orderedResults,
    required bool sessionComplete,
  }) {
    final attemptList = attempts.toList(growable: false);
    final resultList = orderedResults.toList(growable: false);
    final totalMicros = attemptList.fold<int>(
      0,
      (sum, attempt) => sum + attempt.processingDuration.inMicroseconds,
    );
    return MultiPageValidationReport(
      plan: plan,
      attempts: attemptList,
      summary: MultiPageValidationSummary(
        requiredPages: plan.requiredPageIds.length,
        uniqueAcceptedPages: resultList.length,
        duplicateAttempts: attemptList
            .where((attempt) => attempt.duplicate)
            .length,
        wrongPageDetections: attemptList
            .where((attempt) => attempt.wrongPageDetection)
            .length,
        rejectedIdentityAttempts: attemptList
            .where(
              (attempt) =>
                  attempt.outcome ==
                  MultiPageValidationAttemptOutcome.identityRejected,
            )
            .length,
        sessionComplete: sessionComplete,
        finalPageOrder: resultList.map((result) => result.pageId),
        totalProcessingDuration: Duration(microseconds: totalMicros),
        averageProcessingDuration: attemptList.isEmpty
            ? Duration.zero
            : Duration(microseconds: totalMicros ~/ attemptList.length),
      ),
    );
  }

  final MultiPageValidationPlan plan;
  final List<MultiPageValidationAttempt> attempts;
  final MultiPageValidationSummary summary;

  Map<String, Object?> toJson() => {
    'templateId': plan.templateId.value,
    'templateVersion': plan.templateVersion.value,
    'summary': summary.toJson(),
    'attempts': attempts.map((attempt) => attempt.toJson()).toList(),
  };
}

List<int> markerIdsForPage(PageLayout page) =>
    page.markerRegions.map((marker) => marker.markerId).toList(growable: false);
