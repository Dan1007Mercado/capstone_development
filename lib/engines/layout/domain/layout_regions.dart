import 'dart:collection';

import '../../../core/geometry/normalized_geometry.dart';
import '../../../core/geometry/physical_geometry.dart';
import '../../../core/ids/identifiers.dart';
import '../../template/domain/question_type.dart';
import 'layout_value_equality.dart';

enum MarkerRole { topLeft, topRight, bottomLeft, bottomRight }

/// Shared print/detection geometry for an ArUco marker with its quiet zone.
abstract final class ArucoMarkerPrintContract {
  static const int quietZoneModules = 1;
  static const int markerBorderModules = 1;
  static const int payloadModules = 4;
  static const int markerModules = payloadModules + markerBorderModules * 2;
  static const int totalModules = markerModules + quietZoneModules * 2;

  static PhysicalRect detectableMarkerBounds(PhysicalRect printableBounds) {
    final quietZoneInset =
        printableBounds.width.millimeters * quietZoneModules / totalModules;
    return PhysicalRect.millimeters(
      left: printableBounds.left.millimeters + quietZoneInset,
      top: printableBounds.top.millimeters + quietZoneInset,
      width: printableBounds.width.millimeters - quietZoneInset * 2,
      height: printableBounds.height.millimeters - quietZoneInset * 2,
    );
  }

  static PhysicalPoint pageFacingRegistrationPoint(
    MarkerRole role,
    PhysicalRect detectableBounds,
  ) => switch (role) {
    MarkerRole.topLeft => PhysicalPoint(
      x: detectableBounds.right,
      y: detectableBounds.bottom,
    ),
    MarkerRole.topRight => PhysicalPoint(
      x: detectableBounds.left,
      y: detectableBounds.bottom,
    ),
    MarkerRole.bottomLeft => PhysicalPoint(
      x: detectableBounds.right,
      y: detectableBounds.top,
    ),
    MarkerRole.bottomRight => PhysicalPoint(
      x: detectableBounds.left,
      y: detectableBounds.top,
    ),
  };
}

/// Registration marker geometry.
///
/// [physicalBounds] includes the printable quiet zone. [physicalMarkerBounds]
/// is the inner detectable marker. The registration point is the detectable
/// marker corner facing the page interior, not the quiet-zone corner or center.
final class MarkerRegion {
  const MarkerRegion({
    required this.markerId,
    required this.role,
    required this.physicalBounds,
    required this.normalizedBounds,
    required this.physicalMarkerBounds,
    required this.normalizedMarkerBounds,
    required this.physicalRegistrationPoint,
    required this.normalizedRegistrationPoint,
  });

  final int markerId;
  final MarkerRole role;
  final PhysicalRect physicalBounds;
  final NormalizedRect normalizedBounds;
  final PhysicalRect physicalMarkerBounds;
  final NormalizedRect normalizedMarkerBounds;
  final PhysicalPoint physicalRegistrationPoint;
  final NormalizedPoint normalizedRegistrationPoint;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MarkerRegion &&
          other.markerId == markerId &&
          other.role == role &&
          other.physicalBounds == physicalBounds &&
          other.normalizedBounds == normalizedBounds &&
          other.physicalMarkerBounds == physicalMarkerBounds &&
          other.normalizedMarkerBounds == normalizedMarkerBounds &&
          other.physicalRegistrationPoint == physicalRegistrationPoint &&
          other.normalizedRegistrationPoint == normalizedRegistrationPoint;

  @override
  int get hashCode => Object.hash(
    markerId,
    role,
    physicalBounds,
    normalizedBounds,
    physicalMarkerBounds,
    normalizedMarkerBounds,
    physicalRegistrationPoint,
    normalizedRegistrationPoint,
  );
}

final class TemplateIdentityRegion {
  const TemplateIdentityRegion({
    required this.physicalBounds,
    required this.normalizedBounds,
  });

  final PhysicalRect physicalBounds;
  final NormalizedRect normalizedBounds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TemplateIdentityRegion &&
          other.physicalBounds == physicalBounds &&
          other.normalizedBounds == normalizedBounds;

  @override
  int get hashCode => Object.hash(physicalBounds, normalizedBounds);
}

/// Immutable geometry for non-scannable content rendered within a page.
final class ContentRegion {
  const ContentRegion({
    required this.physicalBounds,
    required this.normalizedBounds,
  });

  final PhysicalRect physicalBounds;
  final NormalizedRect normalizedBounds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContentRegion &&
          other.physicalBounds == physicalBounds &&
          other.normalizedBounds == normalizedBounds;

  @override
  int get hashCode => Object.hash(physicalBounds, normalizedBounds);
}

/// One deterministic vertical flow lane within the page content area.
final class LayoutColumnRegion {
  const LayoutColumnRegion({
    required this.columnIndex,
    required this.physicalBounds,
    required this.normalizedBounds,
  });

  final int columnIndex;
  final PhysicalRect physicalBounds;
  final NormalizedRect normalizedBounds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LayoutColumnRegion &&
          other.columnIndex == columnIndex &&
          other.physicalBounds == physicalBounds &&
          other.normalizedBounds == normalizedBounds;

  @override
  int get hashCode =>
      Object.hash(columnIndex, physicalBounds, normalizedBounds);
}

/// Scanner-target geometry for either an option or one numeric-grid cell.
final class BubbleRegion {
  const BubbleRegion._({
    required this.pageId,
    required this.questionId,
    required this.optionId,
    required this.numericColumnIndex,
    required this.numericDigitValue,
    required this.physicalBounds,
    required this.normalizedBounds,
    required this.physicalCenter,
    required this.normalizedCenter,
    required this.physicalDiameter,
    required this.printedLabel,
    required this.measurementCenterExclusionRatio,
  });

  factory BubbleRegion.option({
    required PageId pageId,
    required QuestionId questionId,
    required OptionId optionId,
    required PhysicalRect physicalBounds,
    required NormalizedRect normalizedBounds,
    required PhysicalPoint physicalCenter,
    required NormalizedPoint normalizedCenter,
    required PhysicalLength physicalDiameter,
    String? printedLabel,
    double measurementCenterExclusionRatio = 0,
  }) => BubbleRegion._(
    pageId: pageId,
    questionId: questionId,
    optionId: optionId,
    numericColumnIndex: null,
    numericDigitValue: null,
    physicalBounds: physicalBounds,
    normalizedBounds: normalizedBounds,
    physicalCenter: physicalCenter,
    normalizedCenter: normalizedCenter,
    physicalDiameter: physicalDiameter,
    printedLabel: printedLabel,
    measurementCenterExclusionRatio: measurementCenterExclusionRatio,
  );

  factory BubbleRegion.numericCell({
    required PageId pageId,
    required QuestionId questionId,
    required int columnIndex,
    required int digitValue,
    required PhysicalRect physicalBounds,
    required NormalizedRect normalizedBounds,
    required PhysicalPoint physicalCenter,
    required NormalizedPoint normalizedCenter,
    required PhysicalLength physicalDiameter,
    String? printedLabel,
    double measurementCenterExclusionRatio = 0,
  }) => BubbleRegion._(
    pageId: pageId,
    questionId: questionId,
    optionId: null,
    numericColumnIndex: columnIndex,
    numericDigitValue: digitValue,
    physicalBounds: physicalBounds,
    normalizedBounds: normalizedBounds,
    physicalCenter: physicalCenter,
    normalizedCenter: normalizedCenter,
    physicalDiameter: physicalDiameter,
    printedLabel: printedLabel,
    measurementCenterExclusionRatio: measurementCenterExclusionRatio,
  );

  final PageId pageId;
  final QuestionId questionId;
  final OptionId? optionId;
  final int? numericColumnIndex;
  final int? numericDigitValue;
  final PhysicalRect physicalBounds;
  final NormalizedRect normalizedBounds;
  final PhysicalPoint physicalCenter;
  final NormalizedPoint normalizedCenter;
  final PhysicalLength physicalDiameter;

  /// Optional glyph printed inside this scanner target.
  final String? printedLabel;

  /// Fraction of the printed radius excluded from recognition sampling.
  final double measurementCenterExclusionRatio;

  bool get isOptionTarget => optionId != null;
  bool get isNumericCellTarget =>
      numericColumnIndex != null && numericDigitValue != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BubbleRegion &&
          other.pageId == pageId &&
          other.questionId == questionId &&
          other.optionId == optionId &&
          other.numericColumnIndex == numericColumnIndex &&
          other.numericDigitValue == numericDigitValue &&
          other.physicalBounds == physicalBounds &&
          other.normalizedBounds == normalizedBounds &&
          other.physicalCenter == physicalCenter &&
          other.normalizedCenter == normalizedCenter &&
          other.physicalDiameter == physicalDiameter &&
          other.printedLabel == printedLabel &&
          other.measurementCenterExclusionRatio ==
              measurementCenterExclusionRatio;

  @override
  int get hashCode => Object.hashAll([
    pageId,
    questionId,
    optionId,
    numericColumnIndex,
    numericDigitValue,
    physicalBounds,
    normalizedBounds,
    physicalCenter,
    normalizedCenter,
    physicalDiameter,
    printedLabel,
    measurementCenterExclusionRatio,
  ]);
}

final class QuestionRegion {
  QuestionRegion({
    required this.questionId,
    required this.questionNumber,
    required this.questionType,
    required this.columnIndex,
    required this.physicalBounds,
    required this.normalizedBounds,
    required this.promptRegion,
    required this.renderMode,
    required this.promptLineCount,
    required Iterable<BubbleRegion> bubbleRegions,
    this.answerGroupLabel,
    this.answerGroupLabelRegion,
  }) : bubbleRegions = UnmodifiableListView(List.of(bubbleRegions));

  final QuestionId questionId;

  /// One-based number in exact logical template order across the document.
  final int questionNumber;
  final QuestionType questionType;

  /// Null only for a deliberately full-width question in a column profile.
  final int? columnIndex;
  final PhysicalRect physicalBounds;
  final NormalizedRect normalizedBounds;
  final ContentRegion promptRegion;
  final QuestionRenderMode renderMode;
  final int promptLineCount;
  final List<BubbleRegion> bubbleRegions;
  final String? answerGroupLabel;
  final ContentRegion? answerGroupLabelRegion;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuestionRegion &&
          other.questionId == questionId &&
          other.questionNumber == questionNumber &&
          other.questionType == questionType &&
          other.columnIndex == columnIndex &&
          other.physicalBounds == physicalBounds &&
          other.normalizedBounds == normalizedBounds &&
          other.promptRegion == promptRegion &&
          other.renderMode == renderMode &&
          other.promptLineCount == promptLineCount &&
          other.answerGroupLabel == answerGroupLabel &&
          other.answerGroupLabelRegion == answerGroupLabelRegion &&
          layoutListEquals(other.bubbleRegions, bubbleRegions);

  @override
  int get hashCode => Object.hash(
    questionId,
    questionNumber,
    questionType,
    columnIndex,
    physicalBounds,
    normalizedBounds,
    promptRegion,
    renderMode,
    promptLineCount,
    answerGroupLabel,
    answerGroupLabelRegion,
    Object.hashAll(bubbleRegions),
  );
}

/// Authoritative print mode selected while the question is measured.
enum QuestionRenderMode {
  inlineHorizontal,
  stackedHorizontal,
  stackedVertical,
  numericGrid,
  answerSheetHorizontal,
  answerSheetNumericGrid,
}

final class SectionRegion {
  SectionRegion({
    required this.sectionId,
    required this.columnIndex,
    required this.physicalBounds,
    required this.normalizedBounds,
    required this.titleRegion,
    required this.instructionRegion,
    required this.humanReadableFieldRegion,
    required Iterable<QuestionRegion> questionRegions,
  }) : questionRegions = UnmodifiableListView(List.of(questionRegions));

  final SectionId sectionId;

  /// Null only for a deliberately full-width fragment.
  final int? columnIndex;
  final PhysicalRect physicalBounds;
  final NormalizedRect normalizedBounds;

  /// Null only on a continuation fragment, where headings are not repeated.
  final ContentRegion? titleRegion;
  final ContentRegion? instructionRegion;
  final ContentRegion? humanReadableFieldRegion;
  final List<QuestionRegion> questionRegions;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SectionRegion &&
          other.sectionId == sectionId &&
          other.columnIndex == columnIndex &&
          other.physicalBounds == physicalBounds &&
          other.normalizedBounds == normalizedBounds &&
          other.titleRegion == titleRegion &&
          other.instructionRegion == instructionRegion &&
          other.humanReadableFieldRegion == humanReadableFieldRegion &&
          layoutListEquals(other.questionRegions, questionRegions);

  @override
  int get hashCode => Object.hash(
    sectionId,
    columnIndex,
    physicalBounds,
    normalizedBounds,
    titleRegion,
    instructionRegion,
    humanReadableFieldRegion,
    Object.hashAll(questionRegions),
  );
}
