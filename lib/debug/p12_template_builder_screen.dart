import 'package:flutter/material.dart';

import '../application/answer_sheet_packets/in_memory_packet_response_repository.dart';
import '../application/answer_sheet_packets/packet_generation_service.dart';
import '../application/answer_sheet_packets/packet_models.dart';
import '../application/template_builder/template_builder_controller.dart';
import '../application/template_builder/template_pdf_exporter.dart';
import '../application/template_builder/user_accessible_template_pdf_exporter.dart';
import '../application/published_templates/in_memory_published_template_artifact_repository.dart';
import '../application/published_templates/published_template_artifact.dart';
import '../application/published_templates/published_template_artifact_service.dart';
import '../core/errors/engine_error.dart';
import '../core/ids/identifiers.dart';
import '../core/result/engine_result.dart';
import '../core/result/validation.dart';
import '../engines/layout/domain/layout_config.dart';
import '../engines/layout/domain/page_layout.dart';
import '../engines/pdf/application/pdf_engine.dart';
import '../engines/template/application/template_publication_service.dart';
import '../engines/template/application/template_validator.dart';
import '../engines/template/domain/question_type.dart';
import '../engines/template/domain/template_definition.dart';
import '../engines/template/domain/template_question.dart';
import '../engines/template/domain/template_section.dart';
import '../engines/template/domain/template_status.dart';
import '../engines/template/infrastructure/in_memory_template_repository.dart';
import 'p11_1_scanner_validation_sheet.dart';
import 'p12_template_builder_fixture.dart';
import 'p13_6_dense_validation_sheet.dart';

typedef TemplatePdfGenerator =
    Future<EngineResult<TemplatePdfArtifact>> Function();

class P12TemplateBuilderScreen extends StatefulWidget {
  const P12TemplateBuilderScreen({
    super.key,
    this.controller,
    this.exporter,
    this.pdfGenerator,
    this.densePdfGenerator,
    this.multiPagePdfGenerator,
    this.publicationService,
    this.densePublicationService,
    this.answerSheetPublicationService,
    this.packetGenerationService,
  });

  final TemplateBuilderController? controller;
  final TemplatePdfExporter? exporter;
  final TemplatePdfGenerator? pdfGenerator;
  final TemplatePdfGenerator? densePdfGenerator;
  final TemplatePdfGenerator? multiPagePdfGenerator;
  final TemplatePublicationService? publicationService;
  final PublishedTemplateArtifactService? densePublicationService;
  final PublishedTemplateArtifactService? answerSheetPublicationService;
  final PacketGenerationService? packetGenerationService;

  @override
  State<P12TemplateBuilderScreen> createState() =>
      _P12TemplateBuilderScreenState();
}

class _P12TemplateBuilderScreenState extends State<P12TemplateBuilderScreen> {
  late TemplateBuilderController _controller;
  late TemplatePdfExporter _exporter;
  late TemplatePdfGenerator _pdfGenerator;
  late TemplatePdfGenerator _densePdfGenerator;
  late TemplatePdfGenerator _multiPagePdfGenerator;
  late TemplatePublicationService _publicationService;
  late PublishedTemplateArtifactService _densePublicationService;
  late PublishedTemplateArtifactService _answerSheetPublicationService;
  late PacketGenerationService _packetGenerationService;
  final TextEditingController _packetCountController = TextEditingController(
    text: '25',
  );
  final TemplateValidator _validator = TemplateValidator();
  ValidationResult? _validation;
  TemplateLayoutPreview? _preview;
  TemplatePdfArtifact? _pdf;
  PdfExportOutcome? _exportOutcome;
  EngineError? _error;
  bool _generatingPdf = false;
  bool _savingPdf = false;
  bool _publishing = false;
  TemplateDefinition? _publishedDefinition;
  List<TemplateDefinition> _publishedVersions = const [];
  String? _lifecycleMessage;
  String? _densePublicationMessage;
  String? _multiPagePublicationMessage;
  String? _answerSheetPublicationMessage;
  PublishedTemplateArtifact? _publishedAnswerSheetArtifact;
  List<PacketArtifact> _generatedPackets = const [];
  int _responseCount = 0;
  bool _generatingPackets = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TemplateBuilderController();
    _exporter = widget.exporter ?? UserAccessibleTemplatePdfExporter();
    _pdfGenerator = widget.pdfGenerator ?? () => _controller.generatePdf();
    _densePdfGenerator = widget.densePdfGenerator ?? _generateDenseArtifact;
    _multiPagePdfGenerator =
        widget.multiPagePdfGenerator ?? _generateMultiPageArtifact;
    _publicationService =
        widget.publicationService ??
        TemplatePublicationService(repository: InMemoryTemplateRepository());
    _densePublicationService =
        widget.densePublicationService ??
        PublishedTemplateArtifactService(
          repository: InMemoryPublishedTemplateArtifactRepository(),
        );
    _answerSheetPublicationService =
        widget.answerSheetPublicationService ?? _densePublicationService;
    _packetGenerationService =
        widget.packetGenerationService ??
        PacketGenerationService(repository: InMemoryPacketResponseRepository());
  }

  @override
  void dispose() {
    _packetCountController.dispose();
    super.dispose();
  }

  TemplateDefinition get _activeDefinition =>
      _publishedDefinition ?? _controller.snapshot.definition;

  bool get _isEditable =>
      _activeDefinition.status == TemplateStatus.draft && !_publishing;

  void _mutate(void Function() operation) {
    if (!_isEditable) return;
    operation();
    setState(() {
      _validation = null;
      _preview = null;
      _pdf = null;
      _exportOutcome = null;
      _error = null;
    });
  }

  void _validate() {
    setState(() {
      _validation = _validator.validate(_activeDefinition);
      _error = null;
    });
  }

  void _previewLayout() {
    final result = _controller.previewDefinition(_activeDefinition);
    setState(() {
      _preview = result.valueOrNull;
      _error = result.errorOrNull;
      _validation = _validator.validate(_activeDefinition);
    });
  }

  Future<void> _generatePdf() async {
    setState(() {
      _generatingPdf = true;
      _error = null;
    });
    final definition = _activeDefinition;
    final result = definition.status == TemplateStatus.published
        ? await _controller.generatePdfFor(definition)
        : await _pdfGenerator();
    if (!mounted) return;
    setState(() {
      _generatingPdf = false;
      _pdf = result.valueOrNull;
      _exportOutcome = null;
      _preview = result.isSuccess
          ? TemplateLayoutPreview(
              definition: result.value.definition,
              layout: result.value.layout,
            )
          : null;
      _error = result.errorOrNull;
      _validation = _validator.validate(definition);
    });
  }

  Future<void> _generateP14_1DensePreviewPdf() async {
    setState(() {
      _generatingPdf = true;
      _error = null;
    });
    final definition = _activeDefinition;
    final result = await _controller.generatePdfFor(
      definition,
      layoutConfig: LayoutConfig.a4Dense(),
    );
    if (!mounted) return;
    setState(() {
      _generatingPdf = false;
      _pdf = result.valueOrNull;
      _exportOutcome = null;
      _preview = result.isSuccess
          ? TemplateLayoutPreview(
              definition: result.value.definition,
              layout: result.value.layout,
            )
          : null;
      _error = result.errorOrNull;
      _validation = _validator.validate(definition);
    });
  }

  Future<void> _generateP14_2AnswerSheetPdf() async {
    setState(() {
      _generatingPdf = true;
      _error = null;
    });
    final definition = _activeDefinition;
    final result = await _controller.generatePdfFor(
      definition,
      layoutConfig: LayoutConfig.a4AnswerSheet(),
    );
    if (!mounted) return;
    setState(() {
      _generatingPdf = false;
      _pdf = result.valueOrNull;
      _exportOutcome = null;
      _preview = result.isSuccess
          ? TemplateLayoutPreview(
              definition: result.value.definition,
              layout: result.value.layout,
            )
          : null;
      _error = result.errorOrNull;
      _validation = _validator.validate(definition);
    });
  }

  Future<void> _generateDensePdf() async {
    setState(() {
      _generatingPdf = true;
      _error = null;
    });
    final result = await _densePdfGenerator();
    if (!mounted) return;
    setState(() {
      _generatingPdf = false;
      _pdf = result.valueOrNull;
      _exportOutcome = null;
      _preview = result.isSuccess
          ? TemplateLayoutPreview(
              definition: result.value.definition,
              layout: result.value.layout,
            )
          : null;
      _error = result.errorOrNull;
      _validation = result.isSuccess
          ? _validator.validate(result.value.definition)
          : null;
    });
  }

  Future<EngineResult<TemplatePdfArtifact>> _generateDenseArtifact() async {
    final inputs = buildP13_6DenseValidationInputs();
    final rendered = await PdfEngine().render(inputs.template, inputs.layout);
    if (rendered.isFailure) {
      return EngineResult.failure(rendered.error);
    }
    return EngineResult.success(
      TemplatePdfArtifact(
        definition: inputs.template,
        layout: inputs.layout,
        bytes: rendered.value,
      ),
    );
  }

  Future<void> _generateMultiPagePdf() async {
    setState(() {
      _generatingPdf = true;
      _error = null;
    });
    final result = await _multiPagePdfGenerator();
    if (!mounted) return;
    setState(() {
      _generatingPdf = false;
      _pdf = result.valueOrNull;
      _exportOutcome = null;
      _preview = result.isSuccess
          ? TemplateLayoutPreview(
              definition: result.value.definition,
              layout: result.value.layout,
            )
          : null;
      _error = result.errorOrNull;
      _validation = result.isSuccess
          ? _validator.validate(result.value.definition)
          : null;
    });
  }

  Future<EngineResult<TemplatePdfArtifact>> _generateMultiPageArtifact() async {
    final inputs = buildP11ScannerValidationSheetInputs();
    final rendered = await PdfEngine().render(inputs.template, inputs.layout);
    if (rendered.isFailure) return EngineResult.failure(rendered.error);
    return EngineResult.success(
      TemplatePdfArtifact(
        definition: inputs.template,
        layout: inputs.layout,
        bytes: rendered.value,
      ),
    );
  }

  Future<void> _publishDenseArtifact() async {
    setState(() {
      _publishing = true;
      _error = null;
      _densePublicationMessage = null;
      _multiPagePublicationMessage = null;
    });
    final result = await _densePublicationService.publish(
      draft: buildP13_6DenseValidationTemplate(),
      layoutConfig: LayoutConfig.a4Dense(),
    );
    if (!mounted) return;
    setState(() {
      _publishing = false;
      _error = result.errorOrNull;
      if (result.isSuccess) {
        final artifact = result.value;
        _pdf = TemplatePdfArtifact(
          definition: artifact.template,
          layout: artifact.layout,
          bytes: artifact.pdfBytes,
        );
        _preview = TemplateLayoutPreview(
          definition: artifact.template,
          layout: artifact.layout,
        );
        _densePublicationMessage =
            'Dense Template v${artifact.templateVersion.value} saved locally '
            'with exact PDF and PageLayout.';
      }
    });
  }

  Future<void> _generateAnswerSheetPackets() async {
    final published = _publishedAnswerSheetArtifact;
    final count = int.tryParse(_packetCountController.text.trim());
    if (published == null || count == null || count <= 0) {
      setState(() {
        _error = EngineError(
          code: 'PACKET_COUNT_INVALID',
          message: published == null
              ? 'Publish an answer sheet before generating packets.'
              : 'Packet count must be a positive integer.',
        );
      });
      return;
    }
    setState(() {
      _generatingPackets = true;
      _error = null;
    });
    final generated = await _packetGenerationService.generatePackets(
      published,
      count: count,
    );
    final responses = generated.isSuccess
        ? await _packetGenerationService.repository.listResponses()
        : null;
    if (!mounted) return;
    setState(() {
      _generatingPackets = false;
      _error = generated.errorOrNull ?? responses?.errorOrNull;
      if (generated.isSuccess) {
        _generatedPackets = [..._generatedPackets, ...generated.value];
        _responseCount = responses?.valueOrNull?.length ?? _responseCount;
      }
    });
  }

  Future<void> _publishP14_2AnswerSheetArtifact() async {
    if (!_isEditable) return;
    final draft = _controller.buildDefinition();
    setState(() {
      _publishing = true;
      _error = null;
      _pdf = null;
      _preview = null;
      _exportOutcome = null;
      _answerSheetPublicationMessage = null;
      _densePublicationMessage = null;
      _multiPagePublicationMessage = null;
    });
    final result = await _answerSheetPublicationService.publish(
      draft: draft,
      layoutConfig: LayoutConfig.a4AnswerSheet(),
    );
    EngineResult<List<PublishedTemplateArtifact>>? history;
    if (result.isSuccess) {
      history = await _answerSheetPublicationService.list();
    }
    if (!mounted) return;
    setState(() {
      _publishing = false;
      _error = result.errorOrNull ?? history?.errorOrNull;
      _validation = _validator.validate(draft);
      if (result.isSuccess) {
        final artifact = result.value;
        _publishedAnswerSheetArtifact = artifact;
        _publishedDefinition = artifact.template;
        _publishedVersions = history == null || history.isFailure
            ? _mergePublishedVersion(artifact.template)
            : history.value
                  .where(
                    (stored) =>
                        stored.templateId == artifact.templateId &&
                        stored.layoutProfile == LayoutProfile.answerSheet,
                  )
                  .map((stored) => stored.template)
                  .toList(growable: false);
        _pdf = TemplatePdfArtifact(
          definition: artifact.template,
          layout: artifact.layout,
          bytes: artifact.pdfBytes,
        );
        _preview = TemplateLayoutPreview(
          definition: artifact.template,
          layout: artifact.layout,
        );
        _exportOutcome = null;
        _answerSheetPublicationMessage =
            'Answer Sheet v${artifact.templateVersion.value} published '
            'locally with exact PDF and PageLayout.';
      }
    });
  }

  List<TemplateDefinition> _mergePublishedVersion(
    TemplateDefinition published,
  ) {
    final merged = <TemplateDefinition>[
      ..._publishedVersions.where(
        (item) => item.id != published.id || item.version != published.version,
      ),
      published,
    ]..sort((left, right) => left.version.value.compareTo(right.version.value));
    return List.unmodifiable(merged);
  }

  Future<void> _publishMultiPageArtifact() async {
    setState(() {
      _publishing = true;
      _error = null;
      _densePublicationMessage = null;
      _multiPagePublicationMessage = null;
    });
    final result = await _densePublicationService.publish(
      draft: buildP11ScannerValidationTemplate(),
      layoutConfig: LayoutConfig.a4Default(),
    );
    if (!mounted) return;
    setState(() {
      _publishing = false;
      _error = result.errorOrNull;
      if (result.isSuccess) {
        final artifact = result.value;
        _pdf = TemplatePdfArtifact(
          definition: artifact.template,
          layout: artifact.layout,
          bytes: artifact.pdfBytes,
        );
        _preview = TemplateLayoutPreview(
          definition: artifact.template,
          layout: artifact.layout,
        );
        _multiPagePublicationMessage =
            'Multi-Page Validation Template '
            'v${artifact.templateVersion.value} saved locally with exact '
            '3-page PDF and PageLayout.';
      }
    });
  }

  Future<void> _publish() async {
    if (!_isEditable) return;
    final draft = _controller.buildDefinition();
    setState(() {
      _publishing = true;
      _error = null;
      _lifecycleMessage = null;
    });
    final result = await _publicationService.publish(draft);
    EngineResult<List<TemplateDefinition>>? versionsResult;
    if (result.isSuccess) {
      versionsResult = await _publicationService.listPublishedVersions(
        draft.id,
      );
    }
    if (!mounted) return;
    setState(() {
      _publishing = false;
      _publishedDefinition = result.valueOrNull;
      _publishedVersions = versionsResult?.valueOrNull ?? _publishedVersions;
      _validation = _validator.validate(_activeDefinition);
      _preview = null;
      _pdf = null;
      _exportOutcome = null;
      _error = result.errorOrNull ?? versionsResult?.errorOrNull;
      if (result.isSuccess) {
        _lifecycleMessage =
            'Published successfully: v${result.value.version.value}';
      }
    });
  }

  void _createRevision() {
    final published = _publishedDefinition;
    if (published == null) return;
    final result = _publicationService.createRevision(published);
    setState(() {
      if (result.isSuccess) {
        _controller = TemplateBuilderController.fromDraft(result.value);
        _publishedDefinition = null;
        _validation = null;
        _preview = null;
        _pdf = null;
        _exportOutcome = null;
        _error = null;
        _lifecycleMessage =
            'Created editable revision: v${result.value.version.value}';
        _answerSheetPublicationMessage = null;
      } else {
        _error = result.error;
      }
    });
  }

  void _viewPublished(TemplateDefinition published) {
    setState(() {
      _publishedDefinition = published;
      _validation = null;
      _preview = null;
      _pdf = null;
      _exportOutcome = null;
      _error = null;
      _lifecycleMessage =
          'Viewing immutable published v${published.version.value}';
    });
  }

  Future<void> _savePdf() async {
    final pdf = _pdf;
    if (pdf == null) return;
    setState(() {
      _savingPdf = true;
      _exportOutcome = null;
      _error = null;
    });
    final result = await _exporter.export(
      bytes: pdf.bytes,
      suggestedFileName: templatePdfFileName(
        pdf.definition.name,
        pdf.definition.version,
      ),
    );
    if (!mounted) return;
    setState(() {
      _savingPdf = false;
      _exportOutcome = result.valueOrNull;
      _error = result.errorOrNull;
    });
  }

  void _loadDemo() {
    setState(() {
      _controller = buildP12MixedTemplateDemo();
      _publishedDefinition = null;
      _publishedVersions = const [];
      _lifecycleMessage = null;
      _answerSheetPublicationMessage = null;
      _validation = null;
      _preview = null;
      _pdf = null;
      _exportOutcome = null;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final definition = _activeDefinition;
    final editable = _isEditable;
    final publishedVersionLabel = _publishedVersions
        .map((item) => 'v${item.version.value}')
        .join(', ');
    return Scaffold(
      appBar: AppBar(title: const Text('P12/P13 Template Builder')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            key: const Key('template-lifecycle-diagnostics'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Template ID: ${definition.id.value}\n'
                'Version: ${definition.version.value}\n'
                'Status: ${definition.status.name}\n'
                'Published versions: ${publishedVersionLabel.isEmpty ? 'none' : publishedVersionLabel}'
                '${_lifecycleMessage == null ? '' : '\n$_lifecycleMessage'}',
              ),
            ),
          ),
          if (_publishedVersions.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                for (final published in _publishedVersions)
                  TextButton(
                    key: Key('view-published-v${published.version.value}'),
                    onPressed: () => _viewPublished(published),
                    child: Text('View Published v${published.version.value}'),
                  ),
              ],
            ),
          TextFormField(
            key: ValueKey(
              'name-${definition.id.value}-v${definition.version.value}',
            ),
            initialValue: definition.name,
            enabled: editable,
            decoration: const InputDecoration(labelText: 'Template name'),
            onChanged: (value) => _mutate(() => _controller.updateName(value)),
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey(
              'description-${definition.id.value}-v${definition.version.value}',
            ),
            initialValue: definition.description,
            enabled: editable,
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
                onPressed: editable
                    ? () => _mutate(_controller.addSection)
                    : null,
                icon: const Icon(Icons.add),
                label: const Text('Add Section'),
              ),
              OutlinedButton(
                key: const Key('load-mixed-demo'),
                onPressed: editable ? _loadDemo : null,
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
              editable: editable,
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
                onPressed: _generatingPdf || _savingPdf || _publishing
                    ? null
                    : _generatePdf,
                child: Text(
                  _generatingPdf ? 'Generating...' : 'Generate Preview PDF',
                ),
              ),
              FilledButton.tonal(
                key: const Key('generate-p14-1-dense-preview-pdf'),
                onPressed: _generatingPdf || _savingPdf || _publishing
                    ? null
                    : _generateP14_1DensePreviewPdf,
                child: const Text('Generate p14.1 Dense Preview PDF'),
              ),
              FilledButton.tonal(
                key: const Key('generate-p14-2-answer-sheet-pdf'),
                onPressed: _generatingPdf || _savingPdf || _publishing
                    ? null
                    : _generateP14_2AnswerSheetPdf,
                child: const Text('Generate p14.2 Answer Sheet PDF'),
              ),
              FilledButton.tonal(
                key: const Key('publish-p14-2-answer-sheet'),
                onPressed:
                    editable && !_generatingPdf && !_savingPdf && !_publishing
                    ? _publishP14_2AnswerSheetArtifact
                    : null,
                child: Text(
                  _publishing ? 'Publishing...' : 'Publish p14.2 Answer Sheet',
                ),
              ),
              OutlinedButton(
                key: const Key('generate-dense-validation-pdf'),
                onPressed: _generatingPdf || _savingPdf || _publishing
                    ? null
                    : _generateDensePdf,
                child: const Text('Generate Dense Validation PDF'),
              ),
              OutlinedButton(
                key: const Key('generate-multi-page-validation-pdf'),
                onPressed: _generatingPdf || _savingPdf || _publishing
                    ? null
                    : _generateMultiPagePdf,
                child: const Text('Generate Multi-Page Validation PDF'),
              ),
              FilledButton.tonal(
                key: const Key('publish-dense-template-v1'),
                onPressed: _publishing || _generatingPdf || _savingPdf
                    ? null
                    : _publishDenseArtifact,
                child: const Text('Publish Dense Template v1'),
              ),
              FilledButton.tonal(
                key: const Key('publish-multi-page-template-v1'),
                onPressed: _publishing || _generatingPdf || _savingPdf
                    ? null
                    : _publishMultiPageArtifact,
                child: const Text('Publish Multi-Page Validation Template v1'),
              ),
              FilledButton.tonal(
                key: const Key('publish-template'),
                onPressed: editable && !_generatingPdf && !_savingPdf
                    ? _publish
                    : null,
                child: Text(_publishing ? 'Publishing...' : 'Publish Template'),
              ),
              OutlinedButton(
                key: const Key('create-revision'),
                onPressed:
                    definition.status == TemplateStatus.published &&
                        !_generatingPdf &&
                        !_savingPdf &&
                        (_publishedVersions.isEmpty ||
                            definition == _publishedVersions.last)
                    ? _createRevision
                    : null,
                child: const Text('Create Revision'),
              ),
            ],
          ),
          if (_validation case final validation?)
            _ValidationPanel(validation: validation),
          if (_densePublicationMessage case final message?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText(
                message,
                key: const Key('dense-publication-result'),
              ),
            ),
          if (_multiPagePublicationMessage case final message?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText(
                message,
                key: const Key('multi-page-publication-result'),
              ),
            ),
          if (_answerSheetPublicationMessage case final message?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SelectableText(
                message,
                key: const Key('answer-sheet-publication-result'),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            key: const Key('answer-sheet-packet-controls'),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Generate Answer Sheet Packets',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('packet-count'),
                    controller: _packetCountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Packet count',
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(
                    key: const Key('generate-answer-sheet-packets'),
                    onPressed:
                        _generatingPackets ||
                            _publishing ||
                            _publishedAnswerSheetArtifact == null
                        ? null
                        : _generateAnswerSheetPackets,
                    child: Text(
                      _generatingPackets ? 'Generating...' : 'Generate',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Generated packets: ${_generatedPackets.length}\n'
                    'Responses: $_responseCount',
                    key: const Key('packet-generation-summary'),
                  ),
                  if (_generatedPackets.isNotEmpty)
                    ExpansionTile(
                      key: const Key('generated-packet-inspection'),
                      title: const Text('Inspect generated packets'),
                      children: [
                        for (final artifact in _generatedPackets)
                          ListTile(
                            dense: true,
                            title: Text(artifact.packet.packetId.value),
                            subtitle: Text(
                              'Template v${artifact.packet.templateVersion.value} '
                              '• ${artifact.packet.pages.length} page(s) '
                              '• ${artifact.packet.status.name.toUpperCase()}',
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (_error case final error?) _ErrorPanel(error: error),
          if (_preview case final preview?)
            _LayoutPreviewPanel(preview: preview),
          if (_pdf case final pdf?)
            Card(
              key: const Key('pdf-export-result'),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      'PDF generated successfully\n'
                      'File: ${templatePdfFileName(pdf.definition.name, pdf.definition.version)}\n'
                      'Bytes: ${pdf.bytes.length}\n'
                      'Pages: ${pdf.layout.pages.length}',
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      key: const Key('save-pdf'),
                      onPressed: _savingPdf || _publishing || _generatingPdf
                          ? null
                          : _savePdf,
                      icon: const Icon(Icons.save_alt),
                      label: Text(_savingPdf ? 'Saving...' : 'Save PDF'),
                    ),
                    if (_exportOutcome case final outcome?) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        outcome.userCancelled
                            ? 'Save cancelled. The generated PDF is still available to save.'
                            : 'PDF saved successfully.\n'
                                  'URI: ${outcome.locationUri}',
                        key: const Key('pdf-save-outcome'),
                      ),
                    ],
                  ],
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
    required this.editable,
  });

  final TemplateSection section;
  final int sectionIndex;
  final int sectionCount;
  final TemplateBuilderController controller;
  final void Function(void Function()) mutate;
  final bool editable;

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
                  enabled: editable,
                  decoration: const InputDecoration(labelText: 'Section title'),
                  onChanged: (value) => mutate(
                    () => controller.updateSectionTitle(section.id, value),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Move section up',
                onPressed: !editable || sectionIndex == 0
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
                onPressed: !editable || sectionIndex == sectionCount - 1
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
                onPressed: editable
                    ? () => mutate(() => controller.removeSection(section.id))
                    : null,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          TextFormField(
            key: ValueKey('section-instruction-${section.id.value}'),
            initialValue: section.instruction,
            enabled: editable,
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
              editable: editable,
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: Key('add-question-${section.id.value}'),
              onPressed: editable
                  ? () => mutate(() => controller.addQuestion(section.id))
                  : null,
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
    required this.editable,
  });

  final SectionId sectionId;
  final TemplateQuestion question;
  final int questionIndex;
  final int questionCount;
  final TemplateBuilderController controller;
  final void Function(void Function()) mutate;
  final bool editable;

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
                enabled: editable,
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
              onPressed: !editable || questionIndex == 0
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
              onPressed: !editable || questionIndex == questionCount - 1
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
              onPressed: editable
                  ? () => mutate(
                      () => controller.removeQuestion(sectionId, question.id),
                    )
                  : null,
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
          onChanged: editable
              ? (type) {
                  if (type != null) {
                    mutate(
                      () => controller.changeQuestionType(
                        sectionId,
                        question.id,
                        type,
                      ),
                    );
                  }
                }
              : null,
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
            editable: editable,
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
            onChanged: editable
                ? (value) {
                    if (value != null) {
                      mutate(
                        () => controller.setLikertScale(
                          sectionId,
                          question.id,
                          value,
                        ),
                      );
                    }
                  }
                : null,
          ),
          _OptionEditor(
            sectionId: sectionId,
            question: question,
            controller: controller,
            mutate: mutate,
            editable: editable,
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
            onChanged: editable
                ? (value) {
                    if (value != null) {
                      mutate(
                        () => controller.setNumericColumnCount(
                          sectionId,
                          question.id,
                          value,
                        ),
                      );
                    }
                  }
                : null,
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
    required this.editable,
    this.allowAddRemove = true,
  });

  final SectionId sectionId;
  final TemplateQuestion question;
  final TemplateBuilderController controller;
  final void Function(void Function()) mutate;
  final bool editable;
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
                enabled: editable,
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
              onPressed: !editable || index == 0
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
              onPressed: !editable || index == question.options.length - 1
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
                onPressed: !editable || question.options.length <= 2
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
            onPressed: editable
                ? () =>
                      mutate(() => controller.addOption(sectionId, question.id))
                : null,
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
            if (preview.layout.selectionDiagnostics case final diagnostics?)
              Text('Selected columns: ${diagnostics.selectedColumnCount}'),
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
