import 'dart:convert';

import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/pdf/application/pdf_engine.dart';
import 'package:capstone_development/engines/pdf/domain/aruco_marker_encoder.dart';
import 'package:capstone_development/engines/pdf/domain/pdf_render_plan.dart';
import 'package:capstone_development/engines/pdf/domain/pdf_render_style.dart';
import 'package:capstone_development/engines/pdf/domain/pdf_units.dart';
import 'package:capstone_development/engines/pdf/infrastructure/opencv_4x4_50_marker_encoder.dart';
import 'package:capstone_development/engines/pdf/infrastructure/bundled_pdf_render_font_loader.dart';
import 'package:capstone_development/engines/template/domain/numeric_grid_spec.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_content.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/domain/template_option.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:capstone_development/engines/template/domain/template_section.dart';
import 'package:capstone_development/engines/template/domain/template_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout/layout_test_fixtures.dart';

void main() {
  test('A4 page dimensions remain exactly 210 by 297 millimeters', () {
    final page = buildLayout(fullTemplate()).pages.single;

    expect(page.pageSpec.size.width.millimeters, 210);
    expect(page.pageSpec.size.height.millimeters, 297);
    expect(
      PdfUnits.lengthToPoints(page.pageSpec.size.width),
      closeTo(595.2755906, 1e-7),
    );
  });

  test('one layout page produces a non-empty parseable PDF page', () async {
    final template = fullTemplate();
    final result = await PdfEngine().render(template, buildLayout(template));

    expect(
      result.isSuccess,
      isTrue,
      reason: '${result.errorOrNull} ${result.errorOrNull?.details}',
    );
    expect(result.value, isNotEmpty);
    expect(ascii.decode(result.value.take(5).toList()), '%PDF-');
    expect(_pdfPageCount(result.value), 1);
  });

  test('bundled Unicode fonts render multilingual survey text', () async {
    final question = TemplateQuestion(
      id: QuestionId('unicode-question'),
      type: QuestionType.singleChoice,
      prompt: 'Masaya ka ba sa serbisyo? ✓ “Oo” — sigurado',
      options: [
        TemplateOption(id: OptionId('unicode-yes'), label: 'Oo – mahusay'),
        TemplateOption(id: OptionId('unicode-no'), label: 'Hindi — café'),
      ],
    );
    final template = TemplateDefinition(
      id: TemplateId('unicode-survey'),
      version: TemplateVersion(1),
      name: 'Résumé – Survey',
      status: TemplateStatus.draft,
      sections: [
        TemplateSection(
          id: SectionId('respondent'),
          title: 'Impormasyon ng Respondent',
          instruction: 'Piliin ang sagot na “tama”.',
          questions: [question],
        ),
      ],
    );
    final layout = buildLayout(template);
    final unchanged = buildLayout(template);

    final result = await PdfEngine().render(template, layout);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(result.value, isNotEmpty);
    expect(ascii.decode(result.value.take(5).toList()), '%PDF-');
    expect(layout, unchanged);
  });

  test('production renderer uses the bundled Unicode font loader', () {
    expect(PdfEngine().fontLoader, isA<BundledPdfRenderFontLoader>());
  });

  test(
    'multi-page layout produces matching PDF page count and order',
    () async {
      final template = longTemplate(30);
      final layout = buildLayout(template);
      final plan = PdfEngine().buildPlan(template, layout).value;
      final result = await PdfEngine().render(template, layout);

      expect(
        plan.pages.map((page) => page.layout.pageId),
        layout.pages.map((p) => p.pageId),
      );
      expect(_pdfPageCount(result.value), layout.pages.length);
    },
  );

  test('template ID mismatch returns a structured failure', () {
    final template = fullTemplate();
    final original = buildLayout(template);
    final mismatched = LayoutDocument(
      templateId: TemplateId('other'),
      templateVersion: original.templateVersion,
      pages: original.pages,
    );

    final result = PdfEngine().buildPlan(template, mismatched);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'PDF_TEMPLATE_LAYOUT_MISMATCH');
  });

  test('template version mismatch returns a structured failure', () {
    final template = fullTemplate();
    final original = buildLayout(template);
    final mismatched = LayoutDocument(
      templateId: original.templateId,
      templateVersion: TemplateVersion(2),
      pages: original.pages,
    );

    final result = PdfEngine().buildPlan(template, mismatched);

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'PDF_TEMPLATE_LAYOUT_MISMATCH');
  });

  test('each page passes exact marker IDs to the encoder', () {
    final encoder = _RecordingMarkerEncoder();
    final template = longTemplate(30);
    final layout = buildLayout(template);

    final plan = PdfEngine(
      markerEncoder: encoder,
    ).buildPlan(template, layout).value;

    expect(encoder.ids, [
      for (final page in layout.pages)
        ...page.markerRegions.map((marker) => marker.markerId),
    ]);
    expect(plan.pages.every((page) => page.markers.length == 4), isTrue);
  });

  test('marker bounds and registration geometry pass through unchanged', () {
    final template = fullTemplate();
    final layout = buildLayout(template);
    final plan = PdfEngine().buildPlan(template, layout).value.pages.single;

    for (var index = 0; index < plan.markers.length; index++) {
      expect(
        plan.markers[index].region.physicalBounds,
        layout.pages.single.markerRegions[index].physicalBounds,
      );
      expect(
        plan.markers[index].region.physicalMarkerBounds,
        layout.pages.single.markerRegions[index].physicalMarkerBounds,
      );
      expect(
        plan.markers[index].region.physicalRegistrationPoint,
        layout.pages.single.markerRegions[index].physicalRegistrationPoint,
      );
    }
  });

  test('identity payload and bounds come from the exact page', () {
    final template = fullTemplate();
    final layout = buildLayout(template);
    final page = PdfEngine().buildPlan(template, layout).value.pages.single;

    expect(page.identity.payload, 'TS1|survey|1|survey-v1-p1');
    expect(
      page.identity.bounds,
      layout.pages.single.templateIdentityRegion.physicalBounds,
    );
  });

  test('header and section lead text use their supplied regions', () {
    final template = _templateWithLeadContent();
    final layout = buildLayout(template);
    final plan = PdfEngine().buildPlan(template, layout).value.pages.single;
    final section = layout.pages.single.sectionRegions.single;

    expect(
      _singleText(plan, PdfTextRole.header).bounds,
      layout.pages.single.headerRegion.physicalBounds,
    );
    expect(
      _singleText(plan, PdfTextRole.sectionTitle).bounds,
      section.titleRegion!.physicalBounds,
    );
    expect(
      _singleText(plan, PdfTextRole.sectionInstruction).bounds,
      section.instructionRegion!.physicalBounds,
    );
    expect(
      _singleText(plan, PdfTextRole.humanReadableField).bounds,
      section.humanReadableFieldRegion!.physicalBounds,
    );
  });

  test('continuation fragments do not redraw absent section headings', () {
    final template = longTemplate(30);
    final layout = buildLayout(template);
    final pages = PdfEngine().buildPlan(template, layout).value.pages;

    for (final page in pages.skip(1)) {
      expect(
        page.text.where((command) => command.role == PdfTextRole.sectionTitle),
        isEmpty,
      );
      expect(
        page.text.where(
          (command) => command.role == PdfTextRole.sectionInstruction,
        ),
        isEmpty,
      );
    }
  });

  test('every bubble is rendered with exact layout geometry', () {
    final template = fullTemplate();
    final layout = buildLayout(template);
    final plan = PdfEngine().buildPlan(template, layout).value.pages.single;

    expect(plan.bubbles.length, layout.pages.single.bubbleRegions.length);
    expect(
      plan.bubbles.map((bubble) => bubble.physicalBounds),
      layout.pages.single.bubbleRegions.map((bubble) => bubble.physicalBounds),
    );
    expect(
      plan.bubbles.map((bubble) => bubble.physicalDiameter),
      layout.pages.single.bubbleRegions.map(
        (bubble) => bubble.physicalDiameter,
      ),
    );
  });

  test('custom label gap changes labels without changing bubble geometry', () {
    final template = templateWithQuestions([choiceQuestion('q1')]);
    final layout = buildLayout(template);
    final originalBubbles = layout.pages.single.bubbleRegions
        .map((bubble) => bubble.physicalBounds)
        .toList();
    final plan = PdfEngine(
      style: const PdfRenderStyle(optionLabelGapMm: 2.5),
    ).buildPlan(template, layout).value.pages.single;
    final label = plan.text.firstWhere(
      (command) => command.role == PdfTextRole.optionLabel,
    );
    final bubble = plan.bubbles.singleWhere(
      (candidate) => candidate.optionId == label.optionId,
    );

    expect(
      label.bounds.left.millimeters,
      bubble.physicalBounds.right.millimeters + 2.5,
    );
    expect(
      plan.bubbles.map((candidate) => candidate.physicalBounds),
      originalBubbles,
    );
  });

  test('option labels map by OptionId rather than list position', () {
    final question = choiceQuestion('mapped', optionCount: 3);
    final template = templateWithQuestions([question]);
    final plan = PdfEngine()
        .buildPlan(template, buildLayout(template))
        .value
        .pages
        .single;
    final labels = plan.text
        .where((command) => command.role == PdfTextRole.optionLabel)
        .toList();

    expect(
      labels.map((label) => label.optionId),
      question.options.map((o) => o.id),
    );
    expect(
      labels.map((label) => label.text),
      question.options.map((o) => o.label),
    );
  });

  test('numeric grid renders every semantic cell and digit', () {
    final question = TemplateQuestion.numericGrid(
      id: QuestionId('number'),
      prompt: 'Number',
      spec: NumericGridSpec(columnCount: 2, allowedDigits: [1, 4, 7]),
    );
    final template = templateWithQuestions([question]);
    final plan = PdfEngine()
        .buildPlan(template, buildLayout(template))
        .value
        .pages
        .single;
    final labels = plan.text
        .where((command) => command.role == PdfTextRole.numericDigit)
        .toList();

    expect(labels, hasLength(6));
    expect(
      labels.map(
        (label) => (label.numericColumnIndex, label.numericDigitValue),
      ),
      [(0, 1), (0, 4), (0, 7), (1, 1), (1, 4), (1, 7)],
    );
  });

  test('render planning does not mutate LayoutDocument', () {
    final template = fullTemplate();
    final layout = buildLayout(template);
    final equalSnapshot = buildLayout(template);

    PdfEngine().buildPlan(template, layout);

    expect(layout, equalSnapshot);
  });

  test('structural render inputs are deterministic', () {
    final template = fullTemplate();
    final layout = buildLayout(template);
    final first = PdfEngine().buildPlan(template, layout).value;
    final second = PdfEngine().buildPlan(template, layout).value;

    expect(first.pages.length, second.pages.length);
    for (var index = 0; index < first.pages.length; index++) {
      expect(
        first.pages[index].identity.payload,
        second.pages[index].identity.payload,
      );
      expect(
        first.pages[index].markers.map(
          (marker) => marker.region.physicalBounds,
        ),
        second.pages[index].markers.map(
          (marker) => marker.region.physicalBounds,
        ),
      );
      expect(
        first.pages[index].text.map(
          (command) => (command.role, command.text, command.bounds),
        ),
        second.pages[index].text.map(
          (command) => (command.role, command.text, command.bounds),
        ),
      );
    }
  });

  test('debug overlays are disabled by default and opt-in only', () {
    expect(PdfEngine().style.debugOverlays, isFalse);
    expect(
      PdfEngine(
        style: const PdfRenderStyle(debugOverlays: true),
      ).style.debugOverlays,
      isTrue,
    );
  });
}

PdfTextCommand _singleText(PdfPageRenderPlan page, PdfTextRole role) =>
    page.text.singleWhere((command) => command.role == role);

int _pdfPageCount(List<int> bytes) {
  final source = latin1.decode(bytes, allowInvalid: true);
  return RegExp(r'/Type\s*/Page(?!s)').allMatches(source).length;
}

TemplateDefinition _templateWithLeadContent() => TemplateDefinition(
  id: TemplateId('lead-content'),
  version: TemplateVersion(1),
  name: 'Lead Content',
  status: TemplateStatus.draft,
  sections: [
    TemplateSection(
      id: SectionId('details'),
      title: 'Details',
      instruction: 'Fill this section.',
      humanReadableTextField: const HumanReadableTextField(
        label: 'Name',
        instruction: 'Write clearly.',
      ),
      questions: [choiceQuestion('q1')],
    ),
  ],
);

final class _RecordingMarkerEncoder implements ArucoMarkerEncoder {
  final List<int> ids = [];

  @override
  ArucoDictionary get dictionary => ArucoDictionary.openCv4x4_50;

  @override
  ArucoMarkerMatrix encode(int markerId) {
    ids.add(markerId);
    return const OpenCvDictionary4x4MarkerEncoder().encode(markerId);
  }
}
