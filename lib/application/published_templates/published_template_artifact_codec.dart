import '../../core/geometry/normalized_geometry.dart';
import '../../core/geometry/page_spec.dart';
import '../../core/geometry/physical_geometry.dart';
import '../../core/ids/identifiers.dart';
import '../../engines/layout/domain/layout_regions.dart';
import '../../engines/layout/domain/layout_selection.dart';
import '../../engines/layout/domain/page_layout.dart';
import '../../engines/template/domain/numeric_grid_spec.dart';
import '../../engines/template/domain/question_type.dart';
import '../../engines/template/domain/template_content.dart';
import '../../engines/template/domain/template_definition.dart';
import '../../engines/template/domain/template_option.dart';
import '../../engines/template/domain/template_question.dart';
import '../../engines/template/domain/template_section.dart';
import '../../engines/template/domain/template_status.dart';

/// Versioned JSON codec for the semantic and geometric part of an artifact.
///
/// Every physical and normalized coordinate is stored; loading never invokes
/// LayoutEngine and therefore remains stable across engine upgrades.
final class PublishedTemplateArtifactCodec {
  const PublishedTemplateArtifactCodec();

  static const int schemaVersion = 1;

  Map<String, Object?> encode({
    required TemplateDefinition template,
    required LayoutDocument layout,
  }) => {
    'schemaVersion': schemaVersion,
    'template': _encodeTemplate(template),
    'layout': _encodeLayout(layout),
  };

  ({TemplateDefinition template, LayoutDocument layout}) decode(
    Map<String, Object?> value,
  ) {
    final version = value['schemaVersion'];
    if (version != schemaVersion) {
      throw FormatException('Unsupported artifact schema version: $version');
    }
    return (
      template: _decodeTemplate(_map(value['template'])),
      layout: _decodeLayout(_map(value['layout'])),
    );
  }

  static Map<String, Object?> _encodeTemplate(TemplateDefinition template) => {
    'id': template.id.value,
    'version': template.version.value,
    'name': template.name,
    'description': template.description,
    'status': template.status.name,
    'sections': [
      for (final section in template.sections)
        {
          'id': section.id.value,
          'title': section.title,
          'instruction': section.instruction,
          'humanReadableTextField': section.humanReadableTextField == null
              ? null
              : {
                  'label': section.humanReadableTextField!.label,
                  'instruction': section.humanReadableTextField!.instruction,
                },
          'questions': [
            for (final question in section.questions)
              {
                'id': question.id.value,
                'type': question.type.name,
                'prompt': question.prompt,
                'required': question.required,
                'description': question.description,
                'numericGridSpec': question.numericGridSpec == null
                    ? null
                    : {
                        'columnCount': question.numericGridSpec!.columnCount,
                        'allowedDigits':
                            question.numericGridSpec!.allowedDigits,
                      },
                'options': [
                  for (final option in question.options)
                    {
                      'id': option.id.value,
                      'label': option.label,
                      'value': option.value,
                    },
                ],
              },
          ],
        },
    ],
  };

  static TemplateDefinition _decodeTemplate(Map<String, Object?> value) =>
      TemplateDefinition(
        id: TemplateId(_string(value, 'id')),
        version: TemplateVersion(_integer(value, 'version')),
        name: _string(value, 'name'),
        description: value['description'] as String?,
        status: TemplateStatus.values.byName(_string(value, 'status')),
        sections: [
          for (final rawSection in _list(value, 'sections'))
            _decodeSection(_map(rawSection)),
        ],
      );

  static TemplateSection _decodeSection(Map<String, Object?> value) {
    final rawField = value['humanReadableTextField'];
    return TemplateSection(
      id: SectionId(_string(value, 'id')),
      title: _string(value, 'title'),
      instruction: value['instruction'] as String?,
      humanReadableTextField: rawField == null
          ? null
          : HumanReadableTextField(
              label: _string(_map(rawField), 'label'),
              instruction: _map(rawField)['instruction'] as String?,
            ),
      questions: [
        for (final rawQuestion in _list(value, 'questions'))
          _decodeQuestion(_map(rawQuestion)),
      ],
    );
  }

  static TemplateQuestion _decodeQuestion(Map<String, Object?> value) {
    final rawSpec = value['numericGridSpec'];
    return TemplateQuestion(
      id: QuestionId(_string(value, 'id')),
      type: QuestionType.values.byName(_string(value, 'type')),
      prompt: _string(value, 'prompt'),
      required: value['required'] as bool,
      description: value['description'] as String?,
      numericGridSpec: rawSpec == null
          ? null
          : NumericGridSpec(
              columnCount: _integer(_map(rawSpec), 'columnCount'),
              allowedDigits: [
                for (final digit in _list(_map(rawSpec), 'allowedDigits'))
                  (digit as num).toInt(),
              ],
            ),
      options: [
        for (final rawOption in _list(value, 'options'))
          TemplateOption(
            id: OptionId(_string(_map(rawOption), 'id')),
            label: _string(_map(rawOption), 'label'),
            value: _map(rawOption)['value'],
          ),
      ],
    );
  }

  static Map<String, Object?> _encodeLayout(LayoutDocument layout) => {
    'templateId': layout.templateId.value,
    'templateVersion': layout.templateVersion.value,
    'pages': [for (final page in layout.pages) _encodePage(page)],
    'selectionDiagnostics': layout.selectionDiagnostics == null
        ? null
        : {
            'selectedColumnCount':
                layout.selectionDiagnostics!.selectedColumnCount,
            'candidates': [
              for (final candidate in layout.selectionDiagnostics!.candidates)
                {
                  'columnCount': candidate.columnCount,
                  'pageCount': candidate.pageCount,
                  'unusedAreaRatio': candidate.unusedAreaRatio,
                  'excessivePromptWrappingCount':
                      candidate.excessivePromptWrappingCount,
                  'questionModeFallbackCount':
                      candidate.questionModeFallbackCount,
                  'sectionFragmentCount': candidate.sectionFragmentCount,
                  'inlineQuestionCount': candidate.inlineQuestionCount,
                  'stackedQuestionCount': candidate.stackedQuestionCount,
                  'cost': candidate.cost,
                  'rejectedReasons': candidate.rejectedReasons,
                },
            ],
          },
  };

  static LayoutDocument _decodeLayout(Map<String, Object?> value) {
    final rawDiagnostics = value['selectionDiagnostics'];
    return LayoutDocument(
      templateId: TemplateId(_string(value, 'templateId')),
      templateVersion: TemplateVersion(_integer(value, 'templateVersion')),
      pages: [
        for (final rawPage in _list(value, 'pages')) _decodePage(_map(rawPage)),
      ],
      selectionDiagnostics: rawDiagnostics == null
          ? null
          : _decodeSelectionDiagnostics(_map(rawDiagnostics)),
    );
  }

  static LayoutSelectionDiagnostics _decodeSelectionDiagnostics(
    Map<String, Object?> value,
  ) => LayoutSelectionDiagnostics(
    selectedColumnCount: _integer(value, 'selectedColumnCount'),
    candidates: [
      for (final rawCandidate in _list(value, 'candidates'))
        LayoutCandidateDiagnostics(
          columnCount: _integer(_map(rawCandidate), 'columnCount'),
          pageCount: _integer(_map(rawCandidate), 'pageCount'),
          unusedAreaRatio: _number(_map(rawCandidate), 'unusedAreaRatio'),
          excessivePromptWrappingCount: _integer(
            _map(rawCandidate),
            'excessivePromptWrappingCount',
          ),
          questionModeFallbackCount: _integer(
            _map(rawCandidate),
            'questionModeFallbackCount',
          ),
          sectionFragmentCount: _integer(
            _map(rawCandidate),
            'sectionFragmentCount',
          ),
          inlineQuestionCount: _integer(
            _map(rawCandidate),
            'inlineQuestionCount',
          ),
          stackedQuestionCount: _integer(
            _map(rawCandidate),
            'stackedQuestionCount',
          ),
          cost: _number(_map(rawCandidate), 'cost'),
          rejectedReasons: [
            for (final reason in _list(_map(rawCandidate), 'rejectedReasons'))
              reason as String,
          ],
        ),
    ],
  );

  static Map<String, Object?> _encodePage(PageLayout page) => {
    'templateId': page.templateId.value,
    'templateVersion': page.templateVersion.value,
    'pageId': page.pageId.value,
    'pageIndex': page.pageIndex,
    'totalPageCount': page.totalPageCount,
    'pageSpec': {
      'width': page.pageSpec.size.width.millimeters,
      'height': page.pageSpec.size.height.millimeters,
      'orientation': page.pageSpec.orientation.name,
    },
    'canonicalPageSpec': {
      'widthPixels': page.canonicalPageSpec.widthPixels,
      'heightPixels': page.canonicalPageSpec.heightPixels,
    },
    'physicalPageBounds': _physicalRect(page.physicalPageBounds),
    'normalizedPageBounds': _normalizedRect(page.normalizedPageBounds),
    'printableBounds': _physicalRect(page.printableBounds),
    'normalizedPrintableBounds': _normalizedRect(
      page.normalizedPrintableBounds,
    ),
    'safeBounds': _physicalRect(page.safeBounds),
    'normalizedSafeBounds': _normalizedRect(page.normalizedSafeBounds),
    'markerRegions': [
      for (final marker in page.markerRegions)
        {
          'markerId': marker.markerId,
          'role': marker.role.name,
          'physicalBounds': _physicalRect(marker.physicalBounds),
          'normalizedBounds': _normalizedRect(marker.normalizedBounds),
          'physicalMarkerBounds': _physicalRect(marker.physicalMarkerBounds),
          'normalizedMarkerBounds': _normalizedRect(
            marker.normalizedMarkerBounds,
          ),
          'physicalRegistrationPoint': _physicalPoint(
            marker.physicalRegistrationPoint,
          ),
          'normalizedRegistrationPoint': _normalizedPoint(
            marker.normalizedRegistrationPoint,
          ),
        },
    ],
    'templateIdentityRegion': _encodeIdentity(page.templateIdentityRegion),
    'headerRegion': _encodeContent(page.headerRegion),
    'contentColumnRegions': [
      for (final column in page.contentColumnRegions)
        {
          'columnIndex': column.columnIndex,
          'physicalBounds': _physicalRect(column.physicalBounds),
          'normalizedBounds': _normalizedRect(column.normalizedBounds),
        },
    ],
    'sectionRegions': [
      for (final section in page.sectionRegions) _encodeSectionRegion(section),
    ],
    'questionRegions': [
      for (final question in page.questionRegions)
        _encodeQuestionRegion(question),
    ],
    'bubbleRegions': [
      for (final bubble in page.bubbleRegions) _encodeBubble(bubble),
    ],
  };

  static PageLayout _decodePage(Map<String, Object?> value) {
    final pageSpec = _map(value['pageSpec']);
    final canonical = _map(value['canonicalPageSpec']);
    return PageLayout(
      templateId: TemplateId(_string(value, 'templateId')),
      templateVersion: TemplateVersion(_integer(value, 'templateVersion')),
      pageId: PageId(_string(value, 'pageId')),
      pageIndex: _integer(value, 'pageIndex'),
      totalPageCount: _integer(value, 'totalPageCount'),
      pageSpec: PageSpec(
        size: PhysicalSize.millimeters(
          _number(pageSpec, 'width'),
          _number(pageSpec, 'height'),
        ),
        orientation: PageOrientation.values.byName(
          _string(pageSpec, 'orientation'),
        ),
      ),
      canonicalPageSpec: CanonicalPageSpec(
        widthPixels: _integer(canonical, 'widthPixels'),
        heightPixels: _integer(canonical, 'heightPixels'),
      ),
      physicalPageBounds: _decodePhysicalRect(
        _map(value['physicalPageBounds']),
      ),
      normalizedPageBounds: _decodeNormalizedRect(
        _map(value['normalizedPageBounds']),
      ),
      printableBounds: _decodePhysicalRect(_map(value['printableBounds'])),
      normalizedPrintableBounds: _decodeNormalizedRect(
        _map(value['normalizedPrintableBounds']),
      ),
      safeBounds: _decodePhysicalRect(_map(value['safeBounds'])),
      normalizedSafeBounds: _decodeNormalizedRect(
        _map(value['normalizedSafeBounds']),
      ),
      markerRegions: [
        for (final rawMarker in _list(value, 'markerRegions'))
          _decodeMarker(_map(rawMarker)),
      ],
      templateIdentityRegion: _decodeIdentity(
        _map(value['templateIdentityRegion']),
      ),
      headerRegion: _decodeContent(_map(value['headerRegion'])),
      contentColumnRegions: [
        for (final rawColumn in _list(value, 'contentColumnRegions'))
          LayoutColumnRegion(
            columnIndex: _integer(_map(rawColumn), 'columnIndex'),
            physicalBounds: _decodePhysicalRect(
              _map(_map(rawColumn)['physicalBounds']),
            ),
            normalizedBounds: _decodeNormalizedRect(
              _map(_map(rawColumn)['normalizedBounds']),
            ),
          ),
      ],
      sectionRegions: [
        for (final rawSection in _list(value, 'sectionRegions'))
          _decodeSectionRegion(_map(rawSection)),
      ],
      questionRegions: [
        for (final rawQuestion in _list(value, 'questionRegions'))
          _decodeQuestionRegion(_map(rawQuestion)),
      ],
      bubbleRegions: [
        for (final rawBubble in _list(value, 'bubbleRegions'))
          _decodeBubble(_map(rawBubble)),
      ],
    );
  }

  static Map<String, Object?> _encodeSectionRegion(SectionRegion section) => {
    'sectionId': section.sectionId.value,
    'columnIndex': section.columnIndex,
    'physicalBounds': _physicalRect(section.physicalBounds),
    'normalizedBounds': _normalizedRect(section.normalizedBounds),
    'titleRegion': section.titleRegion == null
        ? null
        : _encodeContent(section.titleRegion!),
    'instructionRegion': section.instructionRegion == null
        ? null
        : _encodeContent(section.instructionRegion!),
    'humanReadableFieldRegion': section.humanReadableFieldRegion == null
        ? null
        : _encodeContent(section.humanReadableFieldRegion!),
    'questionRegions': [
      for (final question in section.questionRegions)
        _encodeQuestionRegion(question),
    ],
  };

  static SectionRegion _decodeSectionRegion(Map<String, Object?> value) =>
      SectionRegion(
        sectionId: SectionId(_string(value, 'sectionId')),
        columnIndex: (value['columnIndex'] as num?)?.toInt(),
        physicalBounds: _decodePhysicalRect(_map(value['physicalBounds'])),
        normalizedBounds: _decodeNormalizedRect(
          _map(value['normalizedBounds']),
        ),
        titleRegion: _nullableContent(value['titleRegion']),
        instructionRegion: _nullableContent(value['instructionRegion']),
        humanReadableFieldRegion: _nullableContent(
          value['humanReadableFieldRegion'],
        ),
        questionRegions: [
          for (final rawQuestion in _list(value, 'questionRegions'))
            _decodeQuestionRegion(_map(rawQuestion)),
        ],
      );

  static Map<String, Object?> _encodeQuestionRegion(QuestionRegion question) =>
      {
        'questionId': question.questionId.value,
        'questionType': question.questionType.name,
        'columnIndex': question.columnIndex,
        'physicalBounds': _physicalRect(question.physicalBounds),
        'normalizedBounds': _normalizedRect(question.normalizedBounds),
        'promptRegion': _encodeContent(question.promptRegion),
        'renderMode': question.renderMode.name,
        'promptLineCount': question.promptLineCount,
        'bubbleRegions': [
          for (final bubble in question.bubbleRegions) _encodeBubble(bubble),
        ],
      };

  static QuestionRegion _decodeQuestionRegion(Map<String, Object?> value) {
    final physicalBounds = _decodePhysicalRect(_map(value['physicalBounds']));
    final normalizedBounds = _decodeNormalizedRect(
      _map(value['normalizedBounds']),
    );
    final bubbles = [
      for (final rawBubble in _list(value, 'bubbleRegions'))
        _decodeBubble(_map(rawBubble)),
    ];
    final rawPrompt = value['promptRegion'];
    final promptRegion = rawPrompt == null
        ? _legacyPromptRegion(physicalBounds, normalizedBounds, bubbles)
        : _decodeContent(_map(rawPrompt));
    return QuestionRegion(
      questionId: QuestionId(_string(value, 'questionId')),
      questionType: QuestionType.values.byName(_string(value, 'questionType')),
      columnIndex: (value['columnIndex'] as num?)?.toInt(),
      physicalBounds: physicalBounds,
      normalizedBounds: normalizedBounds,
      promptRegion: promptRegion,
      renderMode: value['renderMode'] == null
          ? QuestionRenderMode.stackedHorizontal
          : QuestionRenderMode.values.byName(_string(value, 'renderMode')),
      promptLineCount: (value['promptLineCount'] as num?)?.toInt() ?? 1,
      bubbleRegions: bubbles,
    );
  }

  static ContentRegion _legacyPromptRegion(
    PhysicalRect question,
    NormalizedRect normalizedQuestion,
    List<BubbleRegion> bubbles,
  ) {
    final firstBubbleTop = bubbles
        .map((bubble) => bubble.physicalBounds.top.millimeters)
        .reduce((left, right) => left < right ? left : right);
    final height = firstBubbleTop - question.top.millimeters;
    return ContentRegion(
      physicalBounds: PhysicalRect.millimeters(
        left: question.left.millimeters,
        top: question.top.millimeters,
        width: question.width.millimeters,
        height: height,
      ),
      normalizedBounds: NormalizedRect.values(
        left: normalizedQuestion.left.value,
        top: normalizedQuestion.top.value,
        width: normalizedQuestion.width.value,
        height:
            normalizedQuestion.height.value *
            height /
            question.height.millimeters,
      ),
    );
  }

  static Map<String, Object?> _encodeBubble(BubbleRegion bubble) => {
    'pageId': bubble.pageId.value,
    'questionId': bubble.questionId.value,
    'optionId': bubble.optionId?.value,
    'numericColumnIndex': bubble.numericColumnIndex,
    'numericDigitValue': bubble.numericDigitValue,
    'physicalBounds': _physicalRect(bubble.physicalBounds),
    'normalizedBounds': _normalizedRect(bubble.normalizedBounds),
    'physicalCenter': _physicalPoint(bubble.physicalCenter),
    'normalizedCenter': _normalizedPoint(bubble.normalizedCenter),
    'physicalDiameter': bubble.physicalDiameter.millimeters,
  };

  static BubbleRegion _decodeBubble(Map<String, Object?> value) {
    final common = (
      pageId: PageId(_string(value, 'pageId')),
      questionId: QuestionId(_string(value, 'questionId')),
      physicalBounds: _decodePhysicalRect(_map(value['physicalBounds'])),
      normalizedBounds: _decodeNormalizedRect(_map(value['normalizedBounds'])),
      physicalCenter: _decodePhysicalPoint(_map(value['physicalCenter'])),
      normalizedCenter: _decodeNormalizedPoint(_map(value['normalizedCenter'])),
      physicalDiameter: PhysicalLength(_number(value, 'physicalDiameter')),
    );
    final optionId = value['optionId'] as String?;
    if (optionId != null) {
      return BubbleRegion.option(
        pageId: common.pageId,
        questionId: common.questionId,
        optionId: OptionId(optionId),
        physicalBounds: common.physicalBounds,
        normalizedBounds: common.normalizedBounds,
        physicalCenter: common.physicalCenter,
        normalizedCenter: common.normalizedCenter,
        physicalDiameter: common.physicalDiameter,
      );
    }
    return BubbleRegion.numericCell(
      pageId: common.pageId,
      questionId: common.questionId,
      columnIndex: _integer(value, 'numericColumnIndex'),
      digitValue: _integer(value, 'numericDigitValue'),
      physicalBounds: common.physicalBounds,
      normalizedBounds: common.normalizedBounds,
      physicalCenter: common.physicalCenter,
      normalizedCenter: common.normalizedCenter,
      physicalDiameter: common.physicalDiameter,
    );
  }

  static MarkerRegion _decodeMarker(Map<String, Object?> value) => MarkerRegion(
    markerId: _integer(value, 'markerId'),
    role: MarkerRole.values.byName(_string(value, 'role')),
    physicalBounds: _decodePhysicalRect(_map(value['physicalBounds'])),
    normalizedBounds: _decodeNormalizedRect(_map(value['normalizedBounds'])),
    physicalMarkerBounds: _decodePhysicalRect(
      _map(value['physicalMarkerBounds']),
    ),
    normalizedMarkerBounds: _decodeNormalizedRect(
      _map(value['normalizedMarkerBounds']),
    ),
    physicalRegistrationPoint: _decodePhysicalPoint(
      _map(value['physicalRegistrationPoint']),
    ),
    normalizedRegistrationPoint: _decodeNormalizedPoint(
      _map(value['normalizedRegistrationPoint']),
    ),
  );

  static Map<String, Object?> _encodeIdentity(TemplateIdentityRegion region) =>
      {
        'physicalBounds': _physicalRect(region.physicalBounds),
        'normalizedBounds': _normalizedRect(region.normalizedBounds),
      };

  static TemplateIdentityRegion _decodeIdentity(Map<String, Object?> value) =>
      TemplateIdentityRegion(
        physicalBounds: _decodePhysicalRect(_map(value['physicalBounds'])),
        normalizedBounds: _decodeNormalizedRect(
          _map(value['normalizedBounds']),
        ),
      );

  static Map<String, Object?> _encodeContent(ContentRegion region) => {
    'physicalBounds': _physicalRect(region.physicalBounds),
    'normalizedBounds': _normalizedRect(region.normalizedBounds),
  };

  static ContentRegion _decodeContent(Map<String, Object?> value) =>
      ContentRegion(
        physicalBounds: _decodePhysicalRect(_map(value['physicalBounds'])),
        normalizedBounds: _decodeNormalizedRect(
          _map(value['normalizedBounds']),
        ),
      );

  static ContentRegion? _nullableContent(Object? value) =>
      value == null ? null : _decodeContent(_map(value));

  static Map<String, Object?> _physicalRect(PhysicalRect rect) => {
    'left': rect.left.millimeters,
    'top': rect.top.millimeters,
    'width': rect.width.millimeters,
    'height': rect.height.millimeters,
  };

  static PhysicalRect _decodePhysicalRect(Map<String, Object?> value) =>
      PhysicalRect.millimeters(
        left: _number(value, 'left'),
        top: _number(value, 'top'),
        width: _number(value, 'width'),
        height: _number(value, 'height'),
      );

  static Map<String, Object?> _normalizedRect(NormalizedRect rect) => {
    'left': rect.left.value,
    'top': rect.top.value,
    'width': rect.width.value,
    'height': rect.height.value,
  };

  static NormalizedRect _decodeNormalizedRect(Map<String, Object?> value) =>
      NormalizedRect.values(
        left: _number(value, 'left'),
        top: _number(value, 'top'),
        width: _number(value, 'width'),
        height: _number(value, 'height'),
      );

  static Map<String, Object?> _physicalPoint(PhysicalPoint point) => {
    'x': point.x.millimeters,
    'y': point.y.millimeters,
  };

  static PhysicalPoint _decodePhysicalPoint(Map<String, Object?> value) =>
      PhysicalPoint.millimeters(_number(value, 'x'), _number(value, 'y'));

  static Map<String, Object?> _normalizedPoint(NormalizedPoint point) => {
    'x': point.x.value,
    'y': point.y.value,
  };

  static NormalizedPoint _decodeNormalizedPoint(Map<String, Object?> value) =>
      NormalizedPoint.values(_number(value, 'x'), _number(value, 'y'));

  static Map<String, Object?> _map(Object? value) =>
      Map<String, Object?>.from(value! as Map);

  static List<Object?> _list(Map<String, Object?> value, String key) =>
      List<Object?>.from(value[key]! as List);

  static String _string(Map<String, Object?> value, String key) =>
      value[key]! as String;

  static int _integer(Map<String, Object?> value, String key) =>
      (value[key]! as num).toInt();

  static double _number(Map<String, Object?> value, String key) =>
      (value[key]! as num).toDouble();
}
