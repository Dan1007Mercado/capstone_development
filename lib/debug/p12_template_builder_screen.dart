import 'package:flutter/material.dart';

import '../application/template_builder/template_builder_controller.dart';
import '../application/template_builder/template_pdf_exporter.dart';
import '../core/errors/engine_error.dart';
import '../core/ids/identifiers.dart';
import '../core/result/engine_result.dart';
import '../core/result/validation.dart';
import '../engines/layout/domain/page_layout.dart';
import '../engines/template/domain/question_type.dart';
import '../engines/template/domain/template_question.dart';
import '../engines/template/domain/template_section.dart';
import 'p12_template_builder_fixture.dart';

typedef TemplatePdfGenerator =
    Future<EngineResult<TemplatePdfArtifact>> Function();

class P12TemplateBuilderScreen extends StatefulWidget {
  const P12TemplateBuilderScreen({
    super.key,
    this.controller,
    this.exporter,
    this.pdfGenerator,
  });

  final TemplateBuilderController? controller;
  final TemplatePdfExporter? exporter;
  final TemplatePdfGenerator? pdfGenerator;

  @override
  State<P12TemplateBuilderScreen> createState() =>
      _P12TemplateBuilderScreenState();
}

class _P12TemplateBuilderScreenState extends State<P12TemplateBuilderScreen> {
  late TemplateBuilderController _controller;
  late TemplatePdfExporter _exporter;
  late TemplatePdfGenerator _pdfGenerator;
  ValidationResult? _validation;
  TemplateLayoutPreview? _preview;
  TemplatePdfArtifact? _pdf;
  ExportedPdfFile? _exportedPdf;
  EngineError? _error;
  bool _generatingPdf = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TemplateBuilderController();
    _exporter = widget.exporter ?? IoTemplatePdfExporter();
    _pdfGenerator = widget.pdfGenerator ?? () => _controller.generatePdf();
  }

  void _mutate(void Function() operation) {
    operation();
    setState(() {
      _validation = null;
      _preview = null;
      _pdf = null;
      _exportedPdf = null;
      _error = null;
    });
  }

  void _validate() {
    setState(() {
      _validation = _controller.validate();
      _error = null;
    });
  }

  void _previewLayout() {
    final result = _controller.previewLayout();
    setState(() {
      _preview = result.valueOrNull;
      _error = result.errorOrNull;
      _validation = _controller.validate();
    });
  }

  Future<void> _generatePdf() async {
    setState(() {
      _generatingPdf = true;
      _error = null;
    });
    final result = await _pdfGenerator();
    EngineResult<ExportedPdfFile>? exportResult;
    if (result.isSuccess) {
      exportResult = await _exporter.export(
        bytes: result.value.bytes,
        suggestedFileName: templatePdfFileName(
          result.value.definition.name,
          result.value.definition.version,
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _generatingPdf = false;
      _pdf = result.valueOrNull;
      _exportedPdf = exportResult?.valueOrNull;
      _preview = result.isSuccess
          ? TemplateLayoutPreview(
              definition: result.value.definition,
              layout: result.value.layout,
            )
          : null;
      _error = result.errorOrNull ?? exportResult?.errorOrNull;
      _validation = _controller.validate();
    });
  }

  void _loadDemo() {
    setState(() {
      _controller = buildP12MixedTemplateDemo();
      _validation = null;
      _preview = null;
      _pdf = null;
      _exportedPdf = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final definition = _controller.snapshot.definition;
    return Scaffold(
      appBar: AppBar(title: const Text('P12 Template Builder')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            key: ValueKey('name-${definition.id.value}'),
            initialValue: definition.name,
            decoration: const InputDecoration(labelText: 'Template name'),
            onChanged: (value) => _mutate(() => _controller.updateName(value)),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('description-${definition.id.value}'),
            initialValue: definition.description,
            decoration: const InputDecoration(
              labelText: 'Description / instructions',
            ),
            minLines: 1,
            maxLines: 3,
            onChanged: (value) =>
                _mutate(() => _controller.updateDescription(value)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('add-section'),
                onPressed: () => _mutate(_controller.addSection),
                icon: const Icon(Icons.add),
                label: const Text('Add Section'),
              ),
              OutlinedButton(
                key: const Key('load-mixed-demo'),
                onPressed: _loadDemo,
                child: const Text('Load Mixed-Type Demo'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < definition.sections.length; index++)
            _SectionEditor(
              key: ValueKey(definition.sections[index].id.value),
              section: definition.sections[index],
              sectionIndex: index,
              sectionCount: definition.sections.length,
              controller: _controller,
              mutate: _mutate,
            ),
          if (definition.sections.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Add a section to begin building the template.'),
            ),
          const Divider(height: 32),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const Key('validate-template'),
                onPressed: _validate,
                child: const Text('Validate'),
              ),
              OutlinedButton(
                key: const Key('preview-layout'),
                onPressed: _previewLayout,
                child: const Text('Preview Layout'),
              ),
              FilledButton(
                key: const Key('generate-pdf'),
                onPressed: _generatingPdf ? null : _generatePdf,
                child: Text(
                  _generatingPdf ? 'Generating...' : 'Generate Preview PDF',
                ),
              ),
            ],
          ),
          if (_validation case final validation?)
            _ValidationPanel(validation: validation),
          if (_error case final error?) _ErrorPanel(error: error),
          if (_preview case final preview?)
            _LayoutPreviewPanel(preview: preview),
          if (_pdf case final pdf?)
            Card(
              key: const Key('pdf-export-result'),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  _exportedPdf == null
                      ? 'PDF generated in memory but export did not complete.'
                      : 'PDF exported successfully\n'
                            'File: ${_exportedPdf!.fileName}\n'
                            'Path: ${_exportedPdf!.path}\n'
                            'Bytes: ${_exportedPdf!.byteCount}\n'
                            'Pages: ${pdf.layout.pages.length}',
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionEditor extends StatelessWidget {
  const _SectionEditor({
    super.key,
    required this.section,
    required this.sectionIndex,
    required this.sectionCount,
    required this.controller,
    required this.mutate,
  });

  final TemplateSection section;
  final int sectionIndex;
  final int sectionCount;
  final TemplateBuilderController controller;
  final void Function(void Function()) mutate;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('section-title-${section.id.value}'),
                  initialValue: section.title,
                  decoration: const InputDecoration(labelText: 'Section title'),
                  onChanged: (value) => mutate(
                    () => controller.updateSectionTitle(section.id, value),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Move section up',
                onPressed: sectionIndex == 0
                    ? null
                    : () => mutate(
                        () => controller.reorderSections(
                          sectionIndex,
                          sectionIndex - 1,
                        ),
                      ),
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: 'Move section down',
                onPressed: sectionIndex == sectionCount - 1
                    ? null
                    : () => mutate(
                        () => controller.reorderSections(
                          sectionIndex,
                          sectionIndex + 2,
                        ),
                      ),
                icon: const Icon(Icons.arrow_downward),
              ),
              IconButton(
                tooltip: 'Remove section',
                onPressed: () =>
                    mutate(() => controller.removeSection(section.id)),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          TextFormField(
            key: ValueKey('section-instruction-${section.id.value}'),
            initialValue: section.instruction,
            decoration: const InputDecoration(labelText: 'Instructions'),
            onChanged: (value) => mutate(
              () => controller.updateSectionInstruction(section.id, value),
            ),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < section.questions.length; index++)
            _QuestionEditor(
              key: ValueKey(section.questions[index].id.value),
              sectionId: section.id,
              question: section.questions[index],
              questionIndex: index,
              questionCount: section.questions.length,
              controller: controller,
              mutate: mutate,
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: Key('add-question-${section.id.value}'),
              onPressed: () => mutate(() => controller.addQuestion(section.id)),
              icon: const Icon(Icons.add),
              label: const Text('Add Question'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _QuestionEditor extends StatelessWidget {
  const _QuestionEditor({
    super.key,
    required this.sectionId,
    required this.question,
    required this.questionIndex,
    required this.questionCount,
    required this.controller,
    required this.mutate,
  });

  final SectionId sectionId;
  final TemplateQuestion question;
  final int questionIndex;
  final int questionCount;
  final TemplateBuilderController controller;
  final void Function(void Function()) mutate;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('prompt-${question.id.value}'),
                initialValue: question.prompt,
                decoration: const InputDecoration(labelText: 'Prompt'),
                onChanged: (value) => mutate(
                  () => controller.updateQuestionPrompt(
                    sectionId,
                    question.id,
                    value,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Move question up',
              onPressed: questionIndex == 0
                  ? null
                  : () => mutate(
                      () => controller.reorderQuestions(
                        sectionId,
                        questionIndex,
                        questionIndex - 1,
                      ),
                    ),
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              tooltip: 'Move question down',
              onPressed: questionIndex == questionCount - 1
                  ? null
                  : () => mutate(
                      () => controller.reorderQuestions(
                        sectionId,
                        questionIndex,
                        questionIndex + 2,
                      ),
                    ),
              icon: const Icon(Icons.arrow_downward),
            ),
            IconButton(
              tooltip: 'Remove question',
              onPressed: () => mutate(
                () => controller.removeQuestion(sectionId, question.id),
              ),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<QuestionType>(
          key: ValueKey('type-${question.id.value}'),
          initialValue: question.type,
          decoration: const InputDecoration(labelText: 'Question type'),
          items: [
            for (final type in QuestionType.values)
              DropdownMenuItem(value: type, child: Text(type.label)),
          ],
          onChanged: (type) {
            if (type != null) {
              mutate(
                () =>
                    controller.changeQuestionType(sectionId, question.id, type),
              );
            }
          },
        ),
        const SizedBox(height: 8),
        ..._typeControls(),
      ],
    ),
  );

  List<Widget> _typeControls() {
    switch (question.type) {
      case QuestionType.singleChoice:
      case QuestionType.multipleChoice:
        return [
          _OptionEditor(
            sectionId: sectionId,
            question: question,
            controller: controller,
            mutate: mutate,
          ),
        ];
      case QuestionType.likert:
        return [
          DropdownButtonFormField<int>(
            initialValue: question.options.length,
            decoration: const InputDecoration(labelText: 'Likert scale'),
            items: const [
              DropdownMenuItem(value: 5, child: Text('1 - 5')),
              DropdownMenuItem(value: 7, child: Text('1 - 7')),
            ],
            onChanged: (value) {
              if (value != null) {
                mutate(
                  () =>
                      controller.setLikertScale(sectionId, question.id, value),
                );
              }
            },
          ),
          _OptionEditor(
            sectionId: sectionId,
            question: question,
            controller: controller,
            mutate: mutate,
            allowAddRemove: false,
          ),
        ];
      case QuestionType.yesNo:
        return [const Text('Fixed semantic options: Yes / No')];
      case QuestionType.numericGrid:
        return [
          DropdownButtonFormField<int>(
            initialValue: question.numericGridSpec!.columnCount,
            decoration: const InputDecoration(labelText: 'Number of columns'),
            items: [
              for (var count = 1; count <= 8; count++)
                DropdownMenuItem(value: count, child: Text('$count')),
            ],
            onChanged: (value) {
              if (value != null) {
                mutate(
                  () => controller.setNumericColumnCount(
                    sectionId,
                    question.id,
                    value,
                  ),
                );
              }
            },
          ),
        ];
    }
  }
}

class _OptionEditor extends StatelessWidget {
  const _OptionEditor({
    required this.sectionId,
    required this.question,
    required this.controller,
    required this.mutate,
    this.allowAddRemove = true,
  });

  final SectionId sectionId;
  final TemplateQuestion question;
  final TemplateBuilderController controller;
  final void Function(void Function()) mutate;
  final bool allowAddRemove;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var index = 0; index < question.options.length; index++)
        Row(
          key: ValueKey(question.options[index].id.value),
          children: [
            Expanded(
              child: TextFormField(
                initialValue: question.options[index].label,
                decoration: InputDecoration(labelText: 'Option ${index + 1}'),
                onChanged: (value) => mutate(
                  () => controller.updateOptionLabel(
                    sectionId,
                    question.id,
                    question.options[index].id,
                    value,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Move option up',
              onPressed: index == 0
                  ? null
                  : () => mutate(
                      () => controller.reorderOptions(
                        sectionId,
                        question.id,
                        index,
                        index - 1,
                      ),
                    ),
              icon: const Icon(Icons.arrow_upward),
            ),
            IconButton(
              tooltip: 'Move option down',
              onPressed: index == question.options.length - 1
                  ? null
                  : () => mutate(
                      () => controller.reorderOptions(
                        sectionId,
                        question.id,
                        index,
                        index + 2,
                      ),
                    ),
              icon: const Icon(Icons.arrow_downward),
            ),
            if (allowAddRemove)
              IconButton(
                tooltip: 'Remove option',
                onPressed: question.options.length <= 2
                    ? null
                    : () => mutate(
                        () => controller.removeOption(
                          sectionId,
                          question.id,
                          question.options[index].id,
                        ),
                      ),
                icon: const Icon(Icons.remove_circle_outline),
              ),
          ],
        ),
      if (allowAddRemove)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () =>
                mutate(() => controller.addOption(sectionId, question.id)),
            icon: const Icon(Icons.add),
            label: const Text('Add Option'),
          ),
        ),
    ],
  );
}

class _ValidationPanel extends StatelessWidget {
  const _ValidationPanel({required this.validation});

  final ValidationResult validation;

  @override
  Widget build(BuildContext context) => Card(
    color: validation.isValid
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(validation.isValid ? 'Template is valid.' : 'Validation issues'),
          for (final issue in validation.issues)
            Text(
              '${issue.code}: ${issue.message} (${issue.path ?? 'template'})',
            ),
        ],
      ),
    ),
  );
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error});

  final EngineError error;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text('${error.code}: ${error.message}\n${error.details}'),
    ),
  );
}

class _LayoutPreviewPanel extends StatelessWidget {
  const _LayoutPreviewPanel({required this.preview});

  final TemplateLayoutPreview preview;

  @override
  Widget build(BuildContext context) {
    final questions = {
      for (final section in preview.definition.sections)
        for (final question in section.questions) question.id: question,
    };
    return Card(
      key: const Key('layout-preview-panel'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Layout preview: ${preview.layout.pages.length} page(s)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final page in preview.layout.pages)
              _PageSummary(page: page, questions: questions),
          ],
        ),
      ),
    );
  }
}

class _PageSummary extends StatelessWidget {
  const _PageSummary({required this.page, required this.questions});

  final PageLayout page;
  final Map<QuestionId, TemplateQuestion> questions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Page ${page.pageIndex + 1}: ${page.pageId.value}'),
        Text(
          'Sections: ${page.sectionRegions.map((item) => item.sectionId.value).join(', ')}',
        ),
        for (final region in page.questionRegions)
          Text(
            '  ${region.questionId.value} - '
            '${questions[region.questionId]?.type.label ?? 'Unknown'}',
          ),
      ],
    ),
  );
}

extension on QuestionType {
  String get label => switch (this) {
    QuestionType.singleChoice => 'Single Choice',
    QuestionType.multipleChoice => 'Multiple Choice',
    QuestionType.likert => 'Likert',
    QuestionType.yesNo => 'Yes / No',
    QuestionType.numericGrid => 'Numeric Grid',
  };
}
