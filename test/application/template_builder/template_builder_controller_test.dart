import 'dart:convert';
import 'dart:io';

import 'package:capstone_development/application/template_builder/template_builder_controller.dart';
import 'package:capstone_development/debug/p12_template_builder_fixture.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TemplateBuilderController structure', () {
    test('creates an immutable empty/new draft', () {
      final controller = TemplateBuilderController();

      expect(controller.snapshot.definition.name, 'Untitled Template');
      expect(controller.snapshot.definition.sections, isEmpty);
      expect(controller.validate().errors.single.code, 'NO_SECTIONS');
      controller.addSection();
      final snapshot = controller.snapshot.definition;
      expect(
        () => snapshot.sections.add(snapshot.sections.first),
        throwsUnsupportedError,
      );
    });

    test('adds, removes, and reorders sections without changing IDs', () {
      final controller = TemplateBuilderController();
      final first = controller.addSection(title: 'First');
      final second = controller.addSection(title: 'Second');

      expect(controller.reorderSections(0, 2).isSuccess, isTrue);
      expect(
        controller.snapshot.definition.sections.map((section) => section.id),
        [second, first],
      );
      expect(controller.removeSection(second).isSuccess, isTrue);
      expect(controller.snapshot.definition.sections.single.id, first);
    });

    test('adds, removes, and reorders questions without changing IDs', () {
      final controller = TemplateBuilderController();
      final section = controller.addSection();
      final first = controller.addQuestion(section, prompt: 'First').value;
      final second = controller.addQuestion(section, prompt: 'Second').value;

      expect(controller.reorderQuestions(section, 0, 2).isSuccess, isTrue);
      expect(_questions(controller).map((question) => question.id), [
        second,
        first,
      ]);
      expect(controller.removeQuestion(section, second).isSuccess, isTrue);
      expect(_questions(controller).single.id, first);
    });

    test('single and multiple choice options add/remove/reorder', () {
      for (final type in [
        QuestionType.singleChoice,
        QuestionType.multipleChoice,
      ]) {
        final controller = TemplateBuilderController();
        final section = controller.addSection();
        final question = controller.addQuestion(section, type: type).value;
        final originalIds = _questions(
          controller,
        ).single.options.map((option) => option.id).toList();
        final added = controller
            .addOption(section, question, label: 'Added')
            .value;

        expect(
          controller.reorderOptions(section, question, 2, 0).isSuccess,
          isTrue,
        );
        expect(_questions(controller).single.options.first.id, added);
        expect(
          controller.removeOption(section, question, added).isSuccess,
          isTrue,
        );
        expect(
          _questions(controller).single.options.map((option) => option.id),
          originalIds,
        );
      }
    });

    test('Likert scales generate stable 1-5 and 1-7 semantics', () {
      final controller = TemplateBuilderController();
      final section = controller.addSection();
      final question = controller
          .addQuestion(section, type: QuestionType.likert)
          .value;
      final fiveIds = _questions(
        controller,
      ).single.options.map((option) => option.id).toList();

      expect(
        _questions(controller).single.options.map((option) => option.value),
        [1, 2, 3, 4, 5],
      );
      expect(controller.setLikertScale(section, question, 7).isSuccess, isTrue);
      final seven = _questions(controller).single.options;
      expect(seven.map((option) => option.value), [1, 2, 3, 4, 5, 6, 7]);
      expect(seven.take(5).map((option) => option.id), fiveIds);
      expect(controller.setLikertScale(section, question, 6).isFailure, isTrue);
    });

    test('yes/no and numeric-grid generation use domain contracts', () {
      final controller = TemplateBuilderController();
      final section = controller.addSection();
      controller.addQuestion(section, type: QuestionType.yesNo);
      final numeric = controller
          .addQuestion(section, type: QuestionType.numericGrid)
          .value;

      final yesNo = _questions(controller)[0];
      expect(yesNo.options.map((option) => option.value), [true, false]);
      expect(yesNo.options.map((option) => option.label), ['Yes', 'No']);
      expect(
        controller.setNumericColumnCount(section, numeric, 6).isSuccess,
        isTrue,
      );
      expect(_questions(controller)[1].numericGridSpec!.columnCount, 6);
      expect(_questions(controller)[1].options, isEmpty);
    });
  });

  group('type switching and identity', () {
    test(
      'repeated switching preserves QuestionId and removes stale config',
      () {
        final controller = TemplateBuilderController();
        final section = controller.addSection();
        final id = controller
            .addQuestion(
              section,
              type: QuestionType.likert,
              prompt: 'Preserved prompt',
            )
            .value;

        for (final type in [
          QuestionType.multipleChoice,
          QuestionType.yesNo,
          QuestionType.numericGrid,
          QuestionType.likert,
        ]) {
          expect(
            controller.changeQuestionType(section, id, type).isSuccess,
            isTrue,
          );
          final question = _questions(controller).single;
          expect(question.id, id);
          expect(question.prompt, 'Preserved prompt');
          expect(question.type, type);
          expect(
            question.numericGridSpec == null,
            type != QuestionType.numericGrid,
          );
          expect(question.options.isEmpty, type == QuestionType.numericGrid);
        }
        expect(controller.validate().isValid, isTrue);
      },
    );

    test('prompt and option edits preserve IDs', () {
      final controller = TemplateBuilderController();
      final section = controller.addSection();
      final questionId = controller.addQuestion(section).value;
      final optionIds = _questions(
        controller,
      ).single.options.map((option) => option.id).toList();

      controller.updateQuestionPrompt(section, questionId, 'Edited');
      controller.updateOptionLabel(section, questionId, optionIds.first, 'A');

      expect(_questions(controller).single.id, questionId);
      expect(
        _questions(controller).single.options.map((option) => option.id),
        optionIds,
      );
    });
  });

  group('mixed type pipeline', () {
    test('mixed types work within one section and across sections', () {
      final controller = TemplateBuilderController(name: 'Mixed');
      final first = controller.addSection(title: 'Mixed section');
      for (final type in QuestionType.values) {
        controller.addQuestion(first, type: type, prompt: type.name);
      }
      final second = controller.addSection(title: 'More types');
      controller.addQuestion(second, type: QuestionType.likert);
      controller.addQuestion(second, type: QuestionType.yesNo);

      final definition = controller.buildDefinition();
      expect(controller.validate().isValid, isTrue);
      expect(
        definition.sections.first.questions.map((item) => item.type),
        QuestionType.values,
      );
      expect(definition.sections.last.questions.map((item) => item.type), [
        QuestionType.likert,
        QuestionType.yesNo,
      ]);
    });

    test(
      'required P12 fixture validates, paginates, and renders exact layout',
      () async {
        final controller = buildP12MixedTemplateDemo();
        final originalIds = controller.snapshot.definition.sections
            .expand((section) => section.questions)
            .map((question) => question.id)
            .toList();
        final firstSection = controller.snapshot.definition.sections.first.id;
        controller.reorderSections(0, 2);
        controller.reorderSections(1, 0);
        expect(
          controller.snapshot.definition.sections
              .expand((section) => section.questions)
              .map((question) => question.id)
              .toSet(),
          originalIds.toSet(),
        );
        expect(
          controller.snapshot.definition.sections.any(
            (section) => section.id == firstSection,
          ),
          isTrue,
        );

        final preview = controller.previewLayout();
        expect(
          preview.isSuccess,
          isTrue,
          reason: preview.errorOrNull?.toString(),
        );
        final laidOutIds = preview.value.layout.pages
            .expand((page) => page.questionRegions)
            .map((region) => region.questionId)
            .toList();
        expect(laidOutIds.toSet(), originalIds.toSet());
        expect(laidOutIds.length, originalIds.length);
        for (final page in preview.value.layout.pages) {
          final firstMarkerId = 10 + page.pageIndex * 4;
          expect(page.markerRegions.map((marker) => marker.markerId), [
            firstMarkerId,
            firstMarkerId + 1,
            firstMarkerId + 2,
            firstMarkerId + 3,
          ]);
        }

        final pdf = await controller.generatePdf();
        expect(pdf.isSuccess, isTrue, reason: pdf.errorOrNull?.toString());
        expect(pdf.value.layout, preview.value.layout);
        expect(pdf.value.definition, preview.value.definition);
        expect(ascii.decode(pdf.value.bytes.take(5).toList()), '%PDF-');
      },
    );

    test(
      'invalid drafts return validation issues and structured pipeline failure',
      () {
        final controller = TemplateBuilderController(name: '');
        controller.addSection(title: '');

        expect(
          controller.validate().errors.map((issue) => issue.code),
          containsAll(['TEMPLATE_NAME_EMPTY', 'SECTION_TITLE_EMPTY']),
        );
        final preview = controller.previewLayout();
        expect(preview.isFailure, isTrue);
        expect(preview.error.code, 'BUILDER_TEMPLATE_INVALID');
      },
    );

    test(
      'builder source contains no custom physical coordinate calculations',
      () {
        final text = File(
          'lib/application/template_builder/template_builder_controller.dart',
        ).readAsStringSync();

        expect(text, isNot(contains('PhysicalRect')));
        expect(text, isNot(contains('NormalizedRect')));
        expect(text, isNot(contains('bubbleDiameter')));
        expect(text, isNot(contains('millimeters')));
      },
    );
  });
}

List<TemplateQuestion> _questions(TemplateBuilderController controller) =>
    controller.snapshot.definition.sections.single.questions;
