import 'dart:collection';

import '../../../core/geometry/physical_geometry.dart';
import '../../../core/ids/identifiers.dart';
import '../../layout/domain/layout_regions.dart';
import '../../layout/domain/page_layout.dart';
import 'aruco_marker_encoder.dart';

enum PdfTextRole {
  header,
  sectionTitle,
  sectionInstruction,
  humanReadableField,
  questionPrompt,
  optionLabel,
  numericDigit,
}

final class PdfTextCommand {
  const PdfTextCommand({
    required this.role,
    required this.text,
    required this.bounds,
    this.sectionId,
    this.questionId,
    this.optionId,
    this.numericColumnIndex,
    this.numericDigitValue,
  });

  final PdfTextRole role;
  final String text;
  final PhysicalRect bounds;
  final SectionId? sectionId;
  final QuestionId? questionId;
  final OptionId? optionId;
  final int? numericColumnIndex;
  final int? numericDigitValue;
}

final class PdfMarkerCommand {
  const PdfMarkerCommand({required this.region, required this.marker});

  final MarkerRegion region;
  final ArucoMarkerMatrix marker;
}

final class PdfIdentityCommand {
  const PdfIdentityCommand({required this.payload, required this.bounds});

  final String payload;
  final PhysicalRect bounds;
}

final class PdfPageRenderPlan {
  PdfPageRenderPlan({
    required this.layout,
    required this.identity,
    required Iterable<PdfMarkerCommand> markers,
    required Iterable<PdfTextCommand> text,
    required Iterable<BubbleRegion> bubbles,
  }) : markers = UnmodifiableListView(List.of(markers)),
       text = UnmodifiableListView(List.of(text)),
       bubbles = UnmodifiableListView(List.of(bubbles));

  final PageLayout layout;
  final PdfIdentityCommand identity;
  final List<PdfMarkerCommand> markers;
  final List<PdfTextCommand> text;
  final List<BubbleRegion> bubbles;
}

final class PdfRenderPlan {
  PdfRenderPlan({required Iterable<PdfPageRenderPlan> pages})
    : pages = UnmodifiableListView(List.of(pages));

  final List<PdfPageRenderPlan> pages;
}
