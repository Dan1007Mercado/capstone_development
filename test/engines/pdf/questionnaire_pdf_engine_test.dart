import 'dart:convert';

import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/engines/pdf/application/questionnaire_pdf_engine.dart';
import 'package:capstone_development/engines/pdf/domain/pdf_render_fonts.dart';
import 'package:capstone_development/engines/pdf/domain/questionnaire_pdf_plan.dart';
import 'package:capstone_development/engines/template/domain/numeric_grid_spec.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_content.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/domain/template_option.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:capstone_development/engines/template/domain/template_section.dart';
import 'package:capstone_development/engines/template/domain/template_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  final engine = QuestionnairePdfEngine(fontLoader: const _TestFontLoader());

  test(
    'draft templates cannot bypass the published-version boundary',
    () async {
      final result = await engine.render(_shortTemplate(TemplateStatus.draft));

      expect(result.isFailure, isTrue);
      expect(result.error.code, 'QUESTIONNAIRE_REQUIRES_PUBLISHED_TEMPLATE');
    },
  );

  test(
    'short published questionnaire renders one valid two-column page',
    () async {
      final template = _shortTemplate(TemplateStatus.published);
      final result = await engine.render(template);

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      expect(ascii.decode(result.value.bytes.take(5).toList()), '%PDF-');
      expect(result.value.templateId, template.id);
      expect(result.value.templateVersion, template.version);
      expect(result.value.plan.pages, hasLength(1));
      final page = result.value.plan.pages.single;
      expect(page.columns, hasLength(2));
      expect(page.columns[0].width, closeTo(page.columns[1].width, 1e-9));
      expect(page.columns[0].left, lessThan(page.columns[1].left));
      expect(page.pageNumber, 1);
      expect(page.totalPageCount, 1);
    },
  );

  test(
    'mixed question semantics and option identities render in order',
    () async {
      final template = _mixedTemplate();
      final result = await engine.render(template);

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      final starts = _questionStarts(result.value.plan);
      expect(starts.map((placement) => placement.questionId!.value), [
        'q-single',
        'q-likert',
        'q-multiple',
        'q-yes-no',
        'q-numeric',
      ]);
      expect(starts.map((placement) => placement.questionNumber), [
        1,
        2,
        3,
        4,
        5,
      ]);

      final text = result.value.plan.pages
          .expand((page) => page.text)
          .map((placement) => placement.text)
          .join('\n');
      expect(text, contains('1 - Strongly disagree'));
      expect(text, contains('[ ] Dashboard'));
      expect(text, contains('Response format: 4 digits'));
      final renderedOptions = result.value.plan.pages
          .expand((page) => page.text)
          .where((placement) => placement.optionId != null)
          .map((placement) => placement.optionId)
          .toSet();
      final expectedOptions = template.sections
          .expand((section) => section.questions)
          .expand((question) => question.options)
          .map((option) => option.id)
          .toSet();
      expect(renderedOptions, expectedOptions);
    },
  );

  test('content flows left then right then onto the next page', () async {
    final template = _longTemplate(questionCount: 70);
    final result = await engine.render(template);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(result.value.plan.pages.length, greaterThan(1));
    expect(_pdfPageCount(result.value.bytes), result.value.plan.pages.length);
    final starts = _questionStarts(result.value.plan);
    expect(starts, hasLength(70));
    expect(
      starts.map((item) => item.questionNumber),
      orderedEquals(List.generate(70, (i) => i + 1)),
    );

    var previousFlowIndex = -1;
    final occupiedColumns = <int>{};
    for (
      var pageIndex = 0;
      pageIndex < result.value.plan.pages.length;
      pageIndex++
    ) {
      final page = result.value.plan.pages[pageIndex];
      for (final placement in page.text.where((item) => item.startsQuestion)) {
        final columnIndex = placement.bounds.left >= page.columns[1].left
            ? 1
            : 0;
        final flowIndex = pageIndex * 2 + columnIndex;
        expect(flowIndex, greaterThanOrEqualTo(previousFlowIndex));
        previousFlowIndex = flowIndex;
        occupiedColumns.add(flowIndex);
      }
    }
    expect(occupiedColumns, containsAll([0, 1, 2]));
    _expectContentInsideNonOverlappingColumns(result.value.plan);
  });

  test(
    'section heading stays with its first complete question when possible',
    () async {
      final result = await engine.render(_manySectionsTemplate());

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      for (
        var pageIndex = 0;
        pageIndex < result.value.plan.pages.length;
        pageIndex++
      ) {
        final page = result.value.plan.pages[pageIndex];
        for (final heading in page.text.where((item) => item.startsSection)) {
          final question = page.text.firstWhere(
            (item) =>
                item.startsQuestion && item.sectionId == heading.sectionId,
          );
          expect(_columnIndex(page, question), _columnIndex(page, heading));
          expect(question.bounds.top, greaterThan(heading.bounds.top));
        }
      }
    },
  );

  test(
    'oversized question splits safely without duplication or truncation',
    () async {
      final template = _oversizedTemplate();
      final result = await engine.render(template);

      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      final placements = [
        for (final page in result.value.plan.pages)
          for (final item in page.text)
            if (item.questionId == QuestionId('oversized')) (page, item),
      ];
      expect(
        placements.where((entry) => entry.$2.startsQuestion),
        hasLength(1),
      );
      expect(
        placements
            .map(
              (entry) =>
                  '${entry.$1.pageNumber}:${_columnIndex(entry.$1, entry.$2)}',
            )
            .toSet()
            .length,
        greaterThan(1),
      );
      expect(
        placements
            .where((entry) => entry.$2.optionId != null)
            .map((entry) => entry.$2.optionId)
            .toSet(),
        template.sections.single.questions.single.options
            .map((option) => option.id)
            .toSet(),
      );
      _expectContentInsideNonOverlappingColumns(result.value.plan);
    },
  );

  test(
    'pagination plan is deterministic for identical published data',
    () async {
      final template = _longTemplate(questionCount: 25);
      final first = await engine.render(template);
      final second = await engine.render(template);

      expect(first.isSuccess, isTrue);
      expect(second.isSuccess, isTrue);
      expect(
        _planSignature(first.value.plan),
        _planSignature(second.value.plan),
      );
    },
  );

  test('bundled fonts render supported Unicode content offline', () async {
    final template = TemplateDefinition(
      id: TemplateId('unicode-questionnaire'),
      version: TemplateVersion(2),
      name: 'Résumé – Talatanungan',
      description: 'Piliin ang tamang sagot: “Oo” o “Hindi”.',
      status: TemplateStatus.published,
      sections: [
        TemplateSection(
          id: SectionId('unicode-section'),
          title: 'Karanasan ng Gumagamit',
          questions: [
            _choiceQuestion('unicode-q', 'Maayos ba ang serbisyo?', [
              'Oo — mahusay',
              'Hindi',
            ]),
          ],
        ),
      ],
    );

    final result = await QuestionnairePdfEngine().render(template);

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(result.value.bytes, isNotEmpty);
  });
}

TemplateDefinition _shortTemplate(TemplateStatus status) => TemplateDefinition(
  id: TemplateId('short-questionnaire'),
  version: TemplateVersion(3),
  name: 'Short Questionnaire',
  description: 'Read each item carefully before answering.',
  status: status,
  sections: [
    TemplateSection(
      id: SectionId('short-section'),
      title: 'General',
      instruction: 'Choose one answer.',
      humanReadableTextField: const HumanReadableTextField(
        label: 'Respondent code',
        instruction: 'Write clearly.',
      ),
      questions: [
        _choiceQuestion('short-q1', 'How satisfied are you?', [
          'Satisfied',
          'Not satisfied',
        ]),
        _choiceQuestion('short-q2', 'Would you recommend the service?', [
          'Yes',
          'No',
        ]),
      ],
    ),
  ],
);

TemplateDefinition _mixedTemplate() => TemplateDefinition(
  id: TemplateId('mixed-questionnaire'),
  version: TemplateVersion(4),
  name: 'Mixed Questionnaire',
  status: TemplateStatus.published,
  sections: [
    TemplateSection(
      id: SectionId('mixed-a'),
      title: 'Usage',
      questions: [
        _choiceQuestion('q-single', 'Choose one service.', [
          'Support',
          'Training',
        ]),
        TemplateQuestion(
          id: QuestionId('q-likert'),
          type: QuestionType.likert,
          prompt: 'The application is easy to use.',
          options: [
            _option('q-likert-1', 'Strongly disagree', 1),
            _option('q-likert-2', 'Disagree', 2),
            _option('q-likert-3', 'Neutral', 3),
            _option('q-likert-4', 'Agree', 4),
            _option('q-likert-5', 'Strongly agree', 5),
          ],
        ),
        TemplateQuestion(
          id: QuestionId('q-multiple'),
          type: QuestionType.multipleChoice,
          prompt: 'Which features do you use?',
          description: 'Select all that apply.',
          options: [
            _option('q-multi-a', 'Dashboard'),
            _option('q-multi-b', 'Reports'),
          ],
        ),
      ],
    ),
    TemplateSection(
      id: SectionId('mixed-b'),
      title: 'Details',
      questions: [
        TemplateQuestion.yesNo(
          id: QuestionId('q-yes-no'),
          prompt: 'Do you consent?',
          yesOptionId: OptionId('q-yes'),
          noOptionId: OptionId('q-no'),
        ),
        TemplateQuestion.numericGrid(
          id: QuestionId('q-numeric'),
          prompt: 'Enter your four-digit code.',
          spec: NumericGridSpec(
            columnCount: 4,
            allowedDigits: [0, 1, 2, 3, 4, 5],
          ),
        ),
      ],
    ),
  ],
);

TemplateDefinition _longTemplate({
  required int questionCount,
}) => TemplateDefinition(
  id: TemplateId('long-questionnaire'),
  version: TemplateVersion(1),
  name: 'Long Questionnaire',
  status: TemplateStatus.published,
  sections: [
    TemplateSection(
      id: SectionId('long-section'),
      title: 'Service Evaluation',
      questions: [
        for (var index = 0; index < questionCount; index++)
          _choiceQuestion(
            'long-q-$index',
            'Question ${index + 1} asks for a carefully considered response about the service experience.',
            ['Very satisfied', 'Satisfied', 'Neutral', 'Dissatisfied'],
          ),
      ],
    ),
  ],
);

TemplateDefinition _manySectionsTemplate() => TemplateDefinition(
  id: TemplateId('section-flow'),
  version: TemplateVersion(1),
  name: 'Section Flow',
  status: TemplateStatus.published,
  sections: [
    for (var section = 0; section < 18; section++)
      TemplateSection(
        id: SectionId('section-$section'),
        title: 'Section ${section + 1}',
        instruction: 'Answer the following item.',
        questions: [
          _choiceQuestion(
            'section-$section-question',
            'A section-opening question with enough text to require deliberate placement.',
            ['First response', 'Second response', 'Third response'],
          ),
        ],
      ),
  ],
);

TemplateDefinition _oversizedTemplate() {
  final longText = List.filled(
    420,
    'This deliberately long questionnaire content must remain readable and continue in semantic order',
  ).join(' ');
  return TemplateDefinition(
    id: TemplateId('oversized-questionnaire'),
    version: TemplateVersion(1),
    name: 'Oversized Content',
    status: TemplateStatus.published,
    sections: [
      TemplateSection(
        id: SectionId('oversized-section'),
        title: 'Long Form',
        questions: [
          TemplateQuestion(
            id: QuestionId('oversized'),
            type: QuestionType.singleChoice,
            prompt: longText,
            options: [
              _option('oversized-a', '$longText Option A'),
              _option('oversized-b', '$longText Option B'),
            ],
          ),
        ],
      ),
    ],
  );
}

TemplateQuestion _choiceQuestion(
  String id,
  String prompt,
  List<String> labels,
) => TemplateQuestion(
  id: QuestionId(id),
  type: QuestionType.singleChoice,
  prompt: prompt,
  options: [
    for (var index = 0; index < labels.length; index++)
      _option('$id-option-$index', labels[index]),
  ],
);

TemplateOption _option(String id, String label, [Object? value]) =>
    TemplateOption(id: OptionId(id), label: label, value: value);

List<QuestionnaireTextPlacement> _questionStarts(QuestionnairePdfPlan plan) => [
  for (final page in plan.pages)
    for (final placement in page.text)
      if (placement.startsQuestion) placement,
];

int _columnIndex(QuestionnairePagePlan page, QuestionnaireTextPlacement item) =>
    item.bounds.left >= page.columns[1].left ? 1 : 0;

void _expectContentInsideNonOverlappingColumns(QuestionnairePdfPlan plan) {
  for (final page in plan.pages) {
    for (var columnIndex = 0; columnIndex < 2; columnIndex++) {
      final column = page.columns[columnIndex];
      final content =
          page.text
              .where(
                (item) =>
                    item.role.index >= QuestionnaireTextRole.sectionTitle.index,
              )
              .where((item) => _columnIndex(page, item) == columnIndex)
              .toList()
            ..sort(
              (left, right) => left.bounds.top.compareTo(right.bounds.top),
            );
      var bottom = column.top;
      for (final item in content) {
        expect(item.bounds.left, greaterThanOrEqualTo(column.left - 1e-8));
        expect(
          item.bounds.left + item.bounds.width,
          lessThanOrEqualTo(column.left + column.width + 1e-8),
        );
        expect(item.bounds.top, greaterThanOrEqualTo(bottom - 1e-8));
        expect(
          item.bounds.top + item.bounds.height,
          lessThanOrEqualTo(column.top + column.height + 1e-8),
        );
        bottom = item.bounds.top + item.bounds.height;
      }
    }
  }
}

String _planSignature(QuestionnairePdfPlan plan) => plan.pages
    .expand(
      (page) => page.text.map(
        (item) => [
          page.pageNumber,
          item.role.name,
          item.text,
          item.bounds.left,
          item.bounds.top,
          item.bounds.width,
          item.bounds.height,
          item.sectionId?.value,
          item.questionId?.value,
          item.optionId?.value,
        ].join('|'),
      ),
    )
    .join('\n');

int _pdfPageCount(List<int> bytes) {
  final source = latin1.decode(bytes, allowInvalid: true);
  return RegExp(r'/Type\s*/Page(?!s)').allMatches(source).length;
}

final class _TestFontLoader implements PdfRenderFontLoader {
  const _TestFontLoader();

  @override
  Future<EngineResult<PdfRenderFonts>> load() async => EngineResult.success(
    PdfRenderFonts(regular: pw.Font.helvetica(), bold: pw.Font.helveticaBold()),
  );
}
