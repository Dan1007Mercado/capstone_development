import 'dart:typed_data';

import '../../core/errors/engine_error.dart';
import '../../core/ids/identifiers.dart';
import '../../core/result/engine_result.dart';
import '../../core/result/validation.dart';
import '../../engines/layout/application/layout_engine.dart';
import '../../engines/layout/domain/layout_config.dart';
import '../../engines/layout/domain/page_layout.dart';
import '../../engines/pdf/application/pdf_engine.dart';
import '../../engines/template/application/template_validator.dart';
import '../../engines/template/domain/numeric_grid_spec.dart';
import '../../engines/template/domain/question_type.dart';
import '../../engines/template/domain/template_definition.dart';
import '../../engines/template/domain/template_option.dart';
import '../../engines/template/domain/template_question.dart';
import '../../engines/template/domain/template_section.dart';
import '../../engines/template/domain/template_status.dart';
import 'template_id_generator.dart';

/// Immutable view of the active, unpublished builder draft.
final class TemplateBuilderSnapshot {
  const TemplateBuilderSnapshot({required this.definition});

  final TemplateDefinition definition;
}

/// A validated preview created only through the authoritative layout engine.
final class TemplateLayoutPreview {
  const TemplateLayoutPreview({required this.definition, required this.layout});

  final TemplateDefinition definition;
  final LayoutDocument layout;
}

/// PDF bytes and the exact semantic/layout inputs used to render them.
final class TemplatePdfArtifact {
  TemplatePdfArtifact({
    required this.definition,
    required this.layout,
    required Uint8List bytes,
  }) : bytes = Uint8List.fromList(bytes);

  final TemplateDefinition definition;
  final LayoutDocument layout;
  final Uint8List bytes;
}

/// Application-layer editor for an unpublished semantic template draft.
///
/// This class never calculates print coordinates. Preview and PDF operations
/// delegate to [LayoutEngine] and [PdfEngine] using one immutable definition.
final class TemplateBuilderController {
  TemplateBuilderController({
    TemplateId? templateId,
    TemplateVersion? version,
    String name = 'Untitled Template',
    String? description,
    Iterable<TemplateSection> sections = const [],
    TemplateValidator? validator,
    LayoutEngine? layoutEngine,
    PdfEngine? pdfEngine,
    LayoutConfig? layoutConfig,
    TemplateIdGenerator? templateIdGenerator,
  }) : _templateId =
           templateId ??
           (templateIdGenerator ?? RandomTemplateIdGenerator()).generate(),
       _version = version ?? TemplateVersion(1),
       _name = name,
       _description = description,
       _sections = List.of(sections),
       _validator = validator ?? TemplateValidator(),
       _layoutEngine = layoutEngine ?? LayoutEngine(),
       _pdfEngine = pdfEngine ?? PdfEngine(),
       _layoutConfig = layoutConfig ?? LayoutConfig.a4Default();

  factory TemplateBuilderController.fromDraft(
    TemplateDefinition draft, {
    TemplateValidator? validator,
    LayoutEngine? layoutEngine,
    PdfEngine? pdfEngine,
    LayoutConfig? layoutConfig,
  }) {
    if (draft.status != TemplateStatus.draft) {
      throw ArgumentError.value(
        draft.status,
        'draft',
        'TemplateBuilderController requires an editable draft.',
      );
    }
    return TemplateBuilderController(
      templateId: draft.id,
      version: draft.version,
      name: draft.name,
      description: draft.description,
      sections: draft.sections,
      validator: validator,
      layoutEngine: layoutEngine,
      pdfEngine: pdfEngine,
      layoutConfig: layoutConfig,
    );
  }

  final TemplateId _templateId;
  final TemplateVersion _version;
  final TemplateValidator _validator;
  final LayoutEngine _layoutEngine;
  final PdfEngine _pdfEngine;
  final LayoutConfig _layoutConfig;

  String _name;
  String? _description;
  List<TemplateSection> _sections;
  int _nextSectionNumber = 1;
  int _nextQuestionNumber = 1;
  int _nextOptionNumber = 1;

  TemplateBuilderSnapshot get snapshot =>
      TemplateBuilderSnapshot(definition: buildDefinition());

  TemplateDefinition buildDefinition() => TemplateDefinition(
    id: _templateId,
    version: _version,
    name: _name,
    description: _description,
    status: TemplateStatus.draft,
    sections: _sections,
  );

  void updateName(String value) => _name = value;

  void updateDescription(String? value) =>
      _description = value == null || value.isEmpty ? null : value;

  SectionId addSection({String? title}) {
    final id = _newSectionId();
    _sections = [
      ..._sections,
      TemplateSection(
        id: id,
        title: title ?? 'Section ${_sections.length + 1}',
      ),
    ];
    return id;
  }

  EngineResult<bool> removeSection(SectionId sectionId) {
    final index = _sectionIndex(sectionId);
    if (index < 0) return _missingSection(sectionId);
    _sections = [..._sections]..removeAt(index);
    return EngineResult.success(true);
  }

  EngineResult<bool> updateSectionTitle(SectionId sectionId, String title) =>
      _updateSection(sectionId, (section) => section.copyWith(title: title));

  EngineResult<bool> updateSectionInstruction(
    SectionId sectionId,
    String? instruction,
  ) => _updateSection(
    sectionId,
    (section) => section.copyWith(
      instruction: instruction == null || instruction.isEmpty
          ? null
          : instruction,
    ),
  );

  EngineResult<bool> reorderSections(int oldIndex, int newIndex) {
    final error = _reorderError(oldIndex, newIndex, _sections.length);
    if (error != null) return EngineResult.failure(error);
    _sections = _reordered(_sections, oldIndex, newIndex);
    return EngineResult.success(true);
  }

  EngineResult<QuestionId> addQuestion(
    SectionId sectionId, {
    QuestionType type = QuestionType.singleChoice,
    String? prompt,
  }) {
    final index = _sectionIndex(sectionId);
    if (index < 0) {
      return EngineResult.failure(_missingSectionError(sectionId));
    }
    final id = _newQuestionId();
    final question = _newQuestion(
      id: id,
      type: type,
      prompt: prompt ?? 'Question ${_questionCount + 1}',
    );
    final section = _sections[index];
    _replaceSection(
      index,
      section.copyWith(questions: [...section.questions, question]),
    );
    return EngineResult.success(id);
  }

  EngineResult<bool> removeQuestion(
    SectionId sectionId,
    QuestionId questionId,
  ) => _updateQuestions(sectionId, (questions) {
    final index = questions.indexWhere((question) => question.id == questionId);
    if (index < 0) return null;
    return [...questions]..removeAt(index);
  }, missingQuestionId: questionId);

  EngineResult<bool> reorderQuestions(
    SectionId sectionId,
    int oldIndex,
    int newIndex,
  ) {
    final sectionIndex = _sectionIndex(sectionId);
    if (sectionIndex < 0) return _missingSection(sectionId);
    final questions = _sections[sectionIndex].questions;
    final error = _reorderError(oldIndex, newIndex, questions.length);
    if (error != null) return EngineResult.failure(error);
    _replaceSection(
      sectionIndex,
      _sections[sectionIndex].copyWith(
        questions: _reordered(questions, oldIndex, newIndex),
      ),
    );
    return EngineResult.success(true);
  }

  EngineResult<bool> updateQuestionPrompt(
    SectionId sectionId,
    QuestionId questionId,
    String prompt,
  ) => _updateQuestion(
    sectionId,
    questionId,
    (question) => question.copyWith(prompt: prompt),
  );

  EngineResult<bool> changeQuestionType(
    SectionId sectionId,
    QuestionId questionId,
    QuestionType type,
  ) => _updateQuestion(sectionId, questionId, (question) {
    if (question.type == type) return question;
    return _newQuestion(
      id: question.id,
      type: type,
      prompt: question.prompt,
      required: question.required,
      description: question.description,
    );
  });

  EngineResult<OptionId> addOption(
    SectionId sectionId,
    QuestionId questionId, {
    String? label,
  }) {
    OptionId? createdId;
    final result = _updateQuestion(sectionId, questionId, (question) {
      if (!_hasEditableOptions(question.type)) return null;
      createdId = _newOptionId(question.id);
      return question.copyWith(
        options: [
          ...question.options,
          TemplateOption(
            id: createdId!,
            label: label ?? 'Option ${question.options.length + 1}',
          ),
        ],
      );
    });
    if (result.isFailure) return EngineResult.failure(result.error);
    if (createdId == null) {
      return EngineResult.failure(_unsupportedOptionsError(questionId));
    }
    return EngineResult.success(createdId!);
  }

  EngineResult<bool> removeOption(
    SectionId sectionId,
    QuestionId questionId,
    OptionId optionId,
  ) => _updateQuestion(
    sectionId,
    questionId,
    (question) {
      if (!_hasEditableOptions(question.type)) return null;
      if (question.options.length <= 2) return null;
      final index = question.options.indexWhere(
        (option) => option.id == optionId,
      );
      if (index < 0) return null;
      return question.copyWith(options: [...question.options]..removeAt(index));
    },
    failure: EngineError(
      code: 'BUILDER_OPTION_CHANGE_REJECTED',
      message:
          'The option does not exist, is fixed, or is required for validity.',
      details: {'questionId': questionId.value, 'optionId': optionId.value},
    ),
  );

  EngineResult<bool> updateOptionLabel(
    SectionId sectionId,
    QuestionId questionId,
    OptionId optionId,
    String label,
  ) => _updateQuestion(
    sectionId,
    questionId,
    (question) {
      final index = question.options.indexWhere(
        (option) => option.id == optionId,
      );
      if (index < 0 || question.type == QuestionType.numericGrid) return null;
      final options = [...question.options];
      options[index] = options[index].copyWith(label: label);
      return question.copyWith(options: options);
    },
    failure: EngineError(
      code: 'BUILDER_OPTION_NOT_FOUND',
      message: 'The requested option does not exist.',
      details: {'questionId': questionId.value, 'optionId': optionId.value},
    ),
  );

  EngineResult<bool> reorderOptions(
    SectionId sectionId,
    QuestionId questionId,
    int oldIndex,
    int newIndex,
  ) => _updateQuestion(
    sectionId,
    questionId,
    (question) {
      if (!_hasEditableOptions(question.type)) return null;
      final error = _reorderError(oldIndex, newIndex, question.options.length);
      if (error != null) return null;
      return question.copyWith(
        options: _reordered(question.options, oldIndex, newIndex),
      );
    },
    failure: EngineError(
      code: 'BUILDER_OPTION_REORDER_INVALID',
      message: 'The requested option reorder is not valid for this question.',
      details: {'questionId': questionId.value},
    ),
  );

  EngineResult<bool> setLikertScale(
    SectionId sectionId,
    QuestionId questionId,
    int length,
  ) {
    if (length != 5 && length != 7) {
      return EngineResult.failure(
        EngineError(
          code: 'BUILDER_LIKERT_SCALE_INVALID',
          message: 'Likert scale length must be 5 or 7.',
          details: {'length': length},
        ),
      );
    }
    return _updateQuestion(
      sectionId,
      questionId,
      (question) {
        if (question.type != QuestionType.likert) return null;
        final options = <TemplateOption>[];
        for (var index = 0; index < length; index++) {
          final value = index + 1;
          options.add(
            index < question.options.length
                ? TemplateOption(
                    id: question.options[index].id,
                    label: question.options[index].label,
                    value: value,
                  )
                : TemplateOption(
                    id: _newOptionId(question.id),
                    label: '$value',
                    value: value,
                  ),
          );
        }
        return question.copyWith(options: options);
      },
      failure: EngineError(
        code: 'BUILDER_NOT_LIKERT',
        message: 'Only Likert questions have a scale length.',
        details: {'questionId': questionId.value},
      ),
    );
  }

  EngineResult<bool> setNumericColumnCount(
    SectionId sectionId,
    QuestionId questionId,
    int columnCount,
  ) => _updateQuestion(
    sectionId,
    questionId,
    (question) {
      if (question.type != QuestionType.numericGrid) return null;
      return question.copyWith(
        numericGridSpec: NumericGridSpec(
          columnCount: columnCount,
          allowedDigits:
              question.numericGridSpec?.allowedDigits ??
              const [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
        ),
      );
    },
    failure: EngineError(
      code: 'BUILDER_NOT_NUMERIC_GRID',
      message: 'Only numeric-grid questions have a column count.',
      details: {'questionId': questionId.value},
    ),
  );

  ValidationResult validate() => _validator.validate(buildDefinition());

  EngineResult<TemplateLayoutPreview> previewLayout() =>
      previewDefinition(buildDefinition());

  /// Builds layout for an exact immutable definition, including published
  /// versions selected for historical diagnostics.
  EngineResult<TemplateLayoutPreview> previewDefinition(
    TemplateDefinition definition, {
    LayoutConfig? layoutConfig,
  }) {
    final validation = _validator.validate(definition);
    if (!validation.isValid) {
      return EngineResult.failure(_validationError(validation));
    }
    final layoutResult = _layoutEngine.build(
      definition,
      layoutConfig ?? _layoutConfig,
    );
    if (layoutResult.isFailure) {
      return EngineResult.failure(layoutResult.error);
    }
    return EngineResult.success(
      TemplateLayoutPreview(definition: definition, layout: layoutResult.value),
    );
  }

  Future<EngineResult<TemplatePdfArtifact>> generatePdf() =>
      generatePdfFor(buildDefinition());

  /// Renders the exact supplied semantic version without converting status or
  /// regenerating identity.
  Future<EngineResult<TemplatePdfArtifact>> generatePdfFor(
    TemplateDefinition definition, {
    LayoutConfig? layoutConfig,
  }) async {
    final preview = previewDefinition(definition, layoutConfig: layoutConfig);
    if (preview.isFailure) return EngineResult.failure(preview.error);
    final pdf = await _pdfEngine.render(
      preview.value.definition,
      preview.value.layout,
    );
    if (pdf.isFailure) return EngineResult.failure(pdf.error);
    return EngineResult.success(
      TemplatePdfArtifact(
        definition: preview.value.definition,
        layout: preview.value.layout,
        bytes: pdf.value,
      ),
    );
  }

  int get _questionCount =>
      _sections.fold(0, (count, section) => count + section.questions.length);

  TemplateQuestion _newQuestion({
    required QuestionId id,
    required QuestionType type,
    required String prompt,
    bool required = false,
    String? description,
  }) {
    switch (type) {
      case QuestionType.singleChoice:
      case QuestionType.multipleChoice:
        return TemplateQuestion(
          id: id,
          type: type,
          prompt: prompt,
          required: required,
          description: description,
          options: _defaultOptions(id, 2),
        );
      case QuestionType.likert:
        return TemplateQuestion(
          id: id,
          type: type,
          prompt: prompt,
          required: required,
          description: description,
          options: [
            for (var value = 1; value <= 5; value++)
              TemplateOption(
                id: _newOptionId(id),
                label: '$value',
                value: value,
              ),
          ],
        );
      case QuestionType.yesNo:
        return TemplateQuestion.yesNo(
          id: id,
          prompt: prompt,
          required: required,
          description: description,
          yesOptionId: _newOptionId(id),
          noOptionId: _newOptionId(id),
        );
      case QuestionType.numericGrid:
        return TemplateQuestion.numericGrid(
          id: id,
          prompt: prompt,
          required: required,
          description: description,
          spec: NumericGridSpec(columnCount: 3),
        );
    }
  }

  List<TemplateOption> _defaultOptions(QuestionId questionId, int count) => [
    for (var index = 0; index < count; index++)
      TemplateOption(
        id: _newOptionId(questionId),
        label: 'Option ${index + 1}',
      ),
  ];

  SectionId _newSectionId() {
    final existing = _sections.map((section) => section.id.value).toSet();
    while (true) {
      final id = SectionId('section-${_nextSectionNumber++}');
      if (!existing.contains(id.value)) return id;
    }
  }

  QuestionId _newQuestionId() {
    final existing = _sections
        .expand((section) => section.questions)
        .map((question) => question.id.value)
        .toSet();
    while (true) {
      final id = QuestionId('question-${_nextQuestionNumber++}');
      if (!existing.contains(id.value)) return id;
    }
  }

  OptionId _newOptionId(QuestionId questionId) {
    final existing = _sections
        .expand((section) => section.questions)
        .expand((question) => question.options)
        .map((option) => option.id.value)
        .toSet();
    while (true) {
      final id = OptionId('${questionId.value}-option-${_nextOptionNumber++}');
      if (!existing.contains(id.value)) return id;
    }
  }

  int _sectionIndex(SectionId id) =>
      _sections.indexWhere((section) => section.id == id);

  void _replaceSection(int index, TemplateSection section) {
    final sections = [..._sections];
    sections[index] = section;
    _sections = sections;
  }

  EngineResult<bool> _updateSection(
    SectionId id,
    TemplateSection Function(TemplateSection section) update,
  ) {
    final index = _sectionIndex(id);
    if (index < 0) return _missingSection(id);
    _replaceSection(index, update(_sections[index]));
    return EngineResult.success(true);
  }

  EngineResult<bool> _updateQuestions(
    SectionId sectionId,
    List<TemplateQuestion>? Function(List<TemplateQuestion> questions) update, {
    QuestionId? missingQuestionId,
  }) {
    final sectionIndex = _sectionIndex(sectionId);
    if (sectionIndex < 0) return _missingSection(sectionId);
    final questions = update(_sections[sectionIndex].questions);
    if (questions == null) {
      return EngineResult.failure(
        EngineError(
          code: 'BUILDER_QUESTION_NOT_FOUND',
          message: 'The requested question does not exist.',
          details: {'questionId': missingQuestionId?.value},
        ),
      );
    }
    _replaceSection(
      sectionIndex,
      _sections[sectionIndex].copyWith(questions: questions),
    );
    return EngineResult.success(true);
  }

  EngineResult<bool> _updateQuestion(
    SectionId sectionId,
    QuestionId questionId,
    TemplateQuestion? Function(TemplateQuestion question) update, {
    EngineError? failure,
  }) => _updateQuestions(sectionId, (questions) {
    final index = questions.indexWhere((question) => question.id == questionId);
    if (index < 0) return null;
    final updated = update(questions[index]);
    if (updated == null) return null;
    final result = [...questions];
    result[index] = updated;
    return result;
  }, missingQuestionId: questionId).mapFailure(failure);

  EngineResult<bool> _missingSection(SectionId id) =>
      EngineResult.failure(_missingSectionError(id));

  EngineError _missingSectionError(SectionId id) => EngineError(
    code: 'BUILDER_SECTION_NOT_FOUND',
    message: 'The requested section does not exist.',
    details: {'sectionId': id.value},
  );

  EngineError _unsupportedOptionsError(QuestionId id) => EngineError(
    code: 'BUILDER_OPTION_CHANGE_REJECTED',
    message: 'This question type does not support arbitrary options.',
    details: {'questionId': id.value},
  );

  EngineError? _reorderError(int oldIndex, int newIndex, int length) {
    if (oldIndex < 0 ||
        oldIndex >= length ||
        newIndex < 0 ||
        newIndex > length) {
      return EngineError(
        code: 'BUILDER_REORDER_INVALID',
        message: 'Reorder indices are outside the current list.',
        details: {'oldIndex': oldIndex, 'newIndex': newIndex, 'length': length},
      );
    }
    return null;
  }

  List<T> _reordered<T>(List<T> source, int oldIndex, int newIndex) {
    final result = [...source];
    final item = result.removeAt(oldIndex);
    final adjustedIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    result.insert(adjustedIndex, item);
    return result;
  }

  bool _hasEditableOptions(QuestionType type) =>
      type == QuestionType.singleChoice ||
      type == QuestionType.multipleChoice ||
      type == QuestionType.likert;

  EngineError _validationError(ValidationResult validation) => EngineError(
    code: 'BUILDER_TEMPLATE_INVALID',
    message: 'The template must be valid before layout or PDF generation.',
    details: {
      'issues': [
        for (final issue in validation.errors)
          {'code': issue.code, 'message': issue.message, 'path': issue.path},
      ],
    },
  );
}

extension on EngineResult<bool> {
  EngineResult<bool> mapFailure(EngineError? replacement) {
    if (isFailure && replacement != null) {
      return EngineResult.failure(replacement);
    }
    return this;
  }
}
