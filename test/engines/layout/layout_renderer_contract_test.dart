import 'package:capstone_development/core/geometry/geometry_converter.dart';
import 'package:capstone_development/core/geometry/physical_geometry.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/template/domain/template_content.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/domain/template_section.dart';
import 'package:capstone_development/engines/template/domain/template_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_test_fixtures.dart';

void main() {
  test('header exposes the exact reserved geometry', () {
    final config = testConfig();
    final page = buildLayout(fullTemplate(), config: config).pages.first;
    final header = page.headerRegion;

    expect(page.safeBounds.containsRect(header.physicalBounds), isTrue);
    expect(
      page.templateIdentityRegion.physicalBounds.intersects(
        header.physicalBounds,
      ),
      isFalse,
    );
    expect(
      header.physicalBounds.top.millimeters,
      page.templateIdentityRegion.physicalBounds.bottom.millimeters +
          config.minimumContentGapMm,
    );
    expect(header.physicalBounds.height.millimeters, config.headerHeightMm);
    expect(
      header.normalizedBounds,
      GeometryConverter.physicalRectToNormalized(
        header.physicalBounds,
        page.pageSpec.size,
      ),
    );
  });

  test('header ends before section content without overlap', () {
    final page = buildLayout(fullTemplate()).pages.first;
    final firstSection = page.sectionRegions.first;

    expect(
      page.headerRegion.physicalBounds.intersects(firstSection.physicalBounds),
      isFalse,
    );
    expect(
      page.headerRegion.physicalBounds.bottom,
      firstSection.physicalBounds.top,
    );
  });

  test('section title exists and absent instruction remains absent', () {
    final section = buildLayout(
      templateWithQuestions([choiceQuestion('q1')]),
    ).pages.first.sectionRegions.single;

    expect(section.titleRegion, isNotNull);
    expect(section.instructionRegion, isNull);
    expect(section.humanReadableFieldRegion, isNull);
  });

  test('instruction and human-readable field geometry are exposed', () {
    final section = buildLayout(
      _templateWithLeadContent(),
    ).pages.first.sectionRegions.single;

    expect(section.titleRegion, isNotNull);
    expect(section.instructionRegion, isNotNull);
    expect(section.humanReadableFieldRegion, isNotNull);
  });

  test('section lead regions are contained and avoid question bubbles', () {
    final page = buildLayout(_templateWithLeadContent()).pages.first;
    final section = page.sectionRegions.single;
    final leadRegions = [
      section.titleRegion!,
      section.instructionRegion!,
      section.humanReadableFieldRegion!,
    ];

    for (final region in leadRegions) {
      expect(
        section.physicalBounds.containsRect(region.physicalBounds),
        isTrue,
      );
      expect(
        page.bubbleRegions.any(
          (bubble) => region.physicalBounds.intersects(bubble.physicalBounds),
        ),
        isFalse,
      );
      expect(
        region.normalizedBounds,
        GeometryConverter.physicalRectToNormalized(
          region.physicalBounds,
          page.pageSpec.size,
        ),
      );
    }
  });

  test('renderer geometry participates in structural equality', () {
    final template = _templateWithLeadContent();

    final first = buildLayout(template);
    final second = buildLayout(template);

    expect(first, second);
    expect(first.hashCode, second.hashCode);
    expect(first.pages.single.headerRegion, second.pages.single.headerRegion);
    expect(
      first.pages.single.sectionRegions.single,
      second.pages.single.sectionRegions.single,
    );
  });

  test('existing marker and bubble coordinates remain stable', () {
    final page = buildLayout(
      templateWithQuestions([choiceQuestion('q1')]),
    ).pages.single;

    expect(
      page.markerRegions.first.physicalBounds,
      PhysicalRect.millimeters(left: 10, top: 10, width: 14, height: 14),
    );
    expect(
      page.markerRegions.first.physicalMarkerBounds,
      PhysicalRect.millimeters(
        left: 11.75,
        top: 11.75,
        width: 10.5,
        height: 10.5,
      ),
    );
    expect(
      page.questionRegions.single.physicalBounds,
      PhysicalRect.millimeters(left: 28, top: 63, width: 154, height: 14),
    );
    expect(page.bubbleRegions.map((bubble) => bubble.physicalBounds), [
      PhysicalRect.millimeters(left: 28, top: 72, width: 5, height: 5),
      PhysicalRect.millimeters(left: 61, top: 72, width: 5, height: 5),
      PhysicalRect.millimeters(left: 94, top: 72, width: 5, height: 5),
    ]);
  });

  test('continuation fragments contain questions without repeated leads', () {
    final pages = buildLayout(longTemplate(30)).pages;
    final continuationSections = pages
        .skip(1)
        .expand((page) => page.sectionRegions);

    expect(continuationSections, isNotEmpty);
    for (final section in continuationSections) {
      expect(section.titleRegion, isNull);
      expect(section.instructionRegion, isNull);
      expect(section.humanReadableFieldRegion, isNull);
      expect(section.questionRegions, isNotEmpty);
    }
  });
}

TemplateDefinition _templateWithLeadContent() => TemplateDefinition(
  id: TemplateId('renderer-contract'),
  version: TemplateVersion(1),
  name: 'Renderer Contract',
  status: TemplateStatus.draft,
  sections: [
    TemplateSection(
      id: SectionId('details'),
      title: 'Respondent details',
      instruction: 'Complete this section before answering.',
      humanReadableTextField: const HumanReadableTextField(
        label: 'Name',
        instruction: 'Write clearly.',
      ),
      questions: [choiceQuestion('q1')],
    ),
  ],
);
