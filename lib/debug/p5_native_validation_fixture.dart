import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as image;

import '../core/ids/identifiers.dart';
import '../engines/layout/application/layout_engine.dart';
import '../engines/layout/domain/layout_config.dart';
import '../engines/layout/domain/page_layout.dart';
import '../engines/pdf/infrastructure/opencv_4x4_50_marker_encoder.dart';
import '../engines/template/domain/template_definition.dart';
import '../engines/template/domain/template_question.dart';
import '../engines/template/domain/template_section.dart';
import '../engines/template/domain/template_status.dart';

const p5NativeValidationExpectedMarkerIds = <int>[10, 11, 12, 13];

/// Builds the authoritative layout used to render and validate the test page.
PageLayout buildP5NativeValidationPage() {
  final template = buildP5NativeValidationTemplate();
  final result = LayoutEngine().build(template, LayoutConfig.a4Default());
  if (result.isFailure) {
    throw StateError(
      '${result.error.code}: ${result.error.message} ${result.error.details}',
    );
  }
  if (result.value.pages.length != 1) {
    throw StateError('P5 native validation fixture must fit on one page.');
  }
  final page = result.value.pages.single;
  final markerIds = page.markerRegions
      .map((marker) => marker.markerId)
      .toList(growable: false);
  if (!_listEquals(markerIds, p5NativeValidationExpectedMarkerIds)) {
    throw StateError(
      'P5 native validation marker IDs must be '
      '$p5NativeValidationExpectedMarkerIds, but were $markerIds.',
    );
  }
  return page;
}

/// Builds the semantic fixture paired with [buildP5NativeValidationPage].
TemplateDefinition buildP5NativeValidationTemplate({
  String name = 'P5 Native Validation',
}) => TemplateDefinition(
  id: TemplateId('p5-native-validation'),
  version: TemplateVersion(1),
  name: name,
  status: TemplateStatus.draft,
  sections: [
    TemplateSection(
      id: SectionId('validation-section'),
      title: 'Native validation',
      questions: [
        TemplateQuestion.yesNo(
          id: QuestionId('native-runtime-ready'),
          prompt: 'Did the native validation complete?',
          yesOptionId: OptionId('yes'),
          noOptionId: OptionId('no'),
        ),
      ],
    ),
  ],
);

/// Renders a clean canonical page using the repository marker print contract.
Uint8List renderP5NativeValidationPng(PageLayout page) {
  final output = image.Image(
    width: page.canonicalPageSpec.widthPixels,
    height: page.canonicalPageSpec.heightPixels,
    numChannels: 3,
  );
  image.fill(output, color: image.ColorRgb8(255, 255, 255));

  for (final marker in page.markerRegions) {
    final bounds = marker.physicalBounds;
    final left = _physicalX(bounds.left.millimeters, page);
    final top = _physicalY(bounds.top.millimeters, page);
    final right = _physicalX(bounds.right.millimeters, page);
    final bottom = _physicalY(bounds.bottom.millimeters, page);
    _drawMarker(
      output,
      markerId: marker.markerId,
      left: left,
      top: top,
      size: math.min(right - left, bottom - top),
    );
  }

  return Uint8List.fromList(image.encodePng(output));
}

void _drawMarker(
  image.Image target, {
  required int markerId,
  required int left,
  required int top,
  required int size,
}) {
  final matrix = const OpenCvDictionary4x4MarkerEncoder().encode(markerId);
  image.fillRect(
    target,
    x1: left,
    y1: top,
    x2: left + size - 1,
    y2: top + size - 1,
    color: image.ColorRgb8(255, 255, 255),
  );
  for (var row = 0; row < matrix.totalModules; row++) {
    for (var column = 0; column < matrix.totalModules; column++) {
      if (!matrix.modules[row][column]) continue;
      final x1 = left + (column * size / matrix.totalModules).round();
      final y1 = top + (row * size / matrix.totalModules).round();
      final x2 = left + ((column + 1) * size / matrix.totalModules).round() - 1;
      final y2 = top + ((row + 1) * size / matrix.totalModules).round() - 1;
      image.fillRect(
        target,
        x1: x1,
        y1: y1,
        x2: x2,
        y2: y2,
        color: image.ColorRgb8(0, 0, 0),
      );
    }
  }
}

int _physicalX(double millimeters, PageLayout page) =>
    (millimeters /
            page.pageSpec.size.width.millimeters *
            page.canonicalPageSpec.widthPixels)
        .round();

int _physicalY(double millimeters, PageLayout page) =>
    (millimeters /
            page.pageSpec.size.height.millimeters *
            page.canonicalPageSpec.heightPixels)
        .round();

bool _listEquals(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
