import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/layout/application/layout_engine.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/template/domain/numeric_grid_spec.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:capstone_development/engines/template/domain/template_status.dart';
import 'package:flutter_test/flutter_test.dart';

import 'layout_test_fixtures.dart';

void main() {
  test('invalid template fails before layout', () {
    final template = TemplateDefinition(
      id: TemplateId('invalid'),
      version: TemplateVersion(1),
      name: '',
      status: TemplateStatus.draft,
      sections: const [],
    );

    final result = LayoutEngine().build(template, testConfig());

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'TEMPLATE_INVALID');
  });

  test('duplicate marker IDs return a config failure', () {
    final result = LayoutEngine().build(
      fullTemplate(),
      testConfig(
        markerIds: const MarkerIds(
          topLeft: 10,
          topRight: 10,
          bottomLeft: 12,
          bottomRight: 13,
        ),
      ),
    );

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'MARKER_IDS_DUPLICATE');
  });

  test('impossible margins return a content-area failure', () {
    final result = LayoutEngine().build(
      fullTemplate(),
      testConfig(margins: impossibleMargins()),
    );

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'CONTENT_AREA_INVALID');
  });

  test('impossible marker geometry returns a marker failure', () {
    final result = LayoutEngine().build(
      fullTemplate(),
      testConfig(markerSizeMm: 200),
    );

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'MARKER_GEOMETRY_INVALID');
  });

  test('non-positive bubble diameter returns a config failure', () {
    final result = LayoutEngine().build(
      fullTemplate(),
      testConfig(bubbleDiameterMm: 0),
    );

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'LAYOUT_CONFIG_INVALID');
  });

  test('numeric grid wider than safe content returns question-too-large', () {
    final template = templateWithQuestions([
      TemplateQuestion.numericGrid(
        id: QuestionId('wide-grid'),
        prompt: 'Wide code',
        spec: NumericGridSpec(columnCount: 40),
      ),
    ]);

    final result = LayoutEngine().build(template, testConfig());

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'QUESTION_TOO_LARGE');
  });

  test('negative marker IDs return a config failure', () {
    final result = LayoutEngine().build(
      fullTemplate(),
      testConfig(
        markerIds: const MarkerIds(
          topLeft: -1,
          topRight: 11,
          bottomLeft: 12,
          bottomRight: 13,
        ),
      ),
    );

    expect(result.isFailure, isTrue);
    expect(result.error.code, 'LAYOUT_CONFIG_INVALID');
  });

  test('section fragments retain their semantic section ID across pages', () {
    final pages = buildLayout(longTemplate(30)).pages;

    expect(
      pages
          .expand((page) => page.sectionRegions)
          .map((section) => section.sectionId),
      everyElement(SectionId('section-1')),
    );
  });
}
