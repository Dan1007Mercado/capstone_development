import 'dart:math' as math;

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/errors/engine_error.dart';
import '../../../core/ids/identifiers.dart';
import '../../../core/result/engine_result.dart';
import '../../template/application/template_validator.dart';
import '../../template/domain/question_type.dart';
import '../../template/domain/template_definition.dart';
import '../../template/domain/template_question.dart';
import '../../template/domain/template_section.dart';
import '../../template/domain/template_status.dart';
import '../domain/pdf_render_fonts.dart';
import '../domain/pdf_units.dart';
import '../domain/questionnaire_pdf_plan.dart';
import '../domain/questionnaire_pdf_style.dart';
import '../infrastructure/bundled_pdf_render_font_loader.dart';

/// Renders a published semantic snapshot as a separate two-column document.
///
/// This engine deliberately does not consume or create [PageLayout]. Its
/// pagination is presentation-only and cannot alter answer-sheet geometry.
final class QuestionnairePdfEngine {
  QuestionnairePdfEngine({
    PdfRenderFontLoader? fontLoader,
    TemplateValidator? validator,
    this.style = const QuestionnairePdfStyle(),
  }) : fontLoader = fontLoader ?? BundledPdfRenderFontLoader(),
       validator = validator ?? TemplateValidator();

  final PdfRenderFontLoader fontLoader;
  final TemplateValidator validator;
  final QuestionnairePdfStyle style;

  Future<EngineResult<QuestionnairePdfArtifact>> render(
    TemplateDefinition template,
  ) async {
    if (template.status != TemplateStatus.published) {
      return EngineResult.failure(
        _error(
          'QUESTIONNAIRE_REQUIRES_PUBLISHED_TEMPLATE',
          'Questionnaires must be generated from an immutable published version.',
          template,
        ),
      );
    }
    final validation = validator.validate(template);
    if (!validation.isValid) {
      return EngineResult.failure(
        _error(
          'QUESTIONNAIRE_TEMPLATE_INVALID',
          'The published template is not valid for questionnaire generation.',
          template,
          details: {
            'issues': [
              for (final issue in validation.errors)
                {'code': issue.code, 'path': issue.path},
            ],
          },
        ),
      );
    }
    try {
      style.validate();
    } on Object catch (error) {
      return EngineResult.failure(
        _error(
          'QUESTIONNAIRE_STYLE_INVALID',
          'Questionnaire rendering settings are invalid.',
          template,
          details: {'cause': error.toString()},
        ),
      );
    }

    final fonts = await fontLoader.load();
    if (fonts.isFailure) return EngineResult.failure(fonts.error);

    try {
      final document = pw.Document(
        title: template.name,
        author: 'TalaanScan',
        creator: 'TalaanScan Questionnaire PDF Engine',
        subject:
            '${template.id.value} version ${template.version.value} questionnaire',
      );
      final context = pw.Context(document: document.document);
      final builder = _QuestionnairePlanBuilder(
        template: template,
        fonts: fonts.value,
        context: context,
        style: style,
      );
      final plan = builder.build();
      final planError = _validatePlan(template, plan);
      if (planError != null) return EngineResult.failure(planError);

      for (final page in plan.pages) {
        document.addPage(_buildPage(page, fonts.value));
      }
      final bytes = await document.save();
      if (bytes.isEmpty) {
        return EngineResult.failure(
          _error(
            'QUESTIONNAIRE_RENDER_FAILED',
            'Questionnaire rendering produced no PDF bytes.',
            template,
          ),
        );
      }
      return EngineResult.success(
        QuestionnairePdfArtifact(plan: plan, bytes: bytes),
      );
    } on _PaginationException catch (error) {
      return EngineResult.failure(_error(error.code, error.message, template));
    } on Object catch (error) {
      return EngineResult.failure(
        _error(
          'QUESTIONNAIRE_RENDER_FAILED',
          'Questionnaire PDF generation failed.',
          template,
          details: {'cause': error.toString()},
        ),
      );
    }
  }

  pw.Page _buildPage(QuestionnairePagePlan page, PdfRenderFonts fonts) =>
      pw.Page(
        pageFormat: PdfPageFormat(page.pageWidthPoints, page.pageHeightPoints),
        margin: pw.EdgeInsets.zero,
        clip: true,
        build: (_) => pw.Stack(
          fit: pw.StackFit.expand,
          children: [
            for (final placement in page.text)
              _positioned(
                placement.bounds,
                pw.Text(
                  placement.text,
                  maxLines: 1,
                  softWrap: false,
                  overflow: pw.TextOverflow.clip,
                  style: pw.TextStyle(
                    font: placement.bold ? fonts.bold : fonts.regular,
                    fontFallback: fonts.fallback,
                    fontSize: placement.fontSizePoints,
                    color: PdfColors.black,
                  ),
                ),
              ),
            pw.Positioned(
              left: page.columns.first.left + page.columns.first.width,
              top: page.columns.first.top,
              child: pw.Container(
                width:
                    page.columns.last.left -
                    (page.columns.first.left + page.columns.first.width),
                height: page.columns.first.height,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    left: pw.BorderSide(color: PdfColors.grey400, width: 0.4),
                  ),
                ),
              ),
            ),
            pw.Positioned(
              left: page.headerBounds.left,
              top: page.headerBounds.top + page.headerBounds.height - 1,
              child: pw.Container(
                width: page.headerBounds.width,
                height: 0.5,
                color: PdfColors.grey500,
              ),
            ),
            _positioned(
              page.footerBounds,
              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  'Page ${page.pageNumber} of ${page.totalPageCount}',
                  style: pw.TextStyle(
                    font: fonts.regular,
                    fontFallback: fonts.fallback,
                    fontSize: style.identityFontSizePoints,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
            ),
          ],
        ),
      );

  pw.Widget _positioned(PdfPointRect bounds, pw.Widget child) => pw.Positioned(
    left: bounds.left,
    top: bounds.top,
    child: pw.SizedBox(
      width: bounds.width,
      height: bounds.height,
      child: child,
    ),
  );

  EngineError? _validatePlan(
    TemplateDefinition template,
    QuestionnairePdfPlan plan,
  ) {
    if (plan.templateId != template.id ||
        plan.templateVersion != template.version ||
        plan.pages.isEmpty) {
      return _error(
        'QUESTIONNAIRE_PLAN_INVALID',
        'Questionnaire plan identity or page metadata is invalid.',
        template,
      );
    }
    final expectedQuestions = [
      for (final section in template.sections)
        for (final question in section.questions) question.id,
    ];
    final actualQuestions = [
      for (final page in plan.pages)
        for (final placement in page.text)
          if (placement.startsQuestion) placement.questionId!,
    ];
    if (!_sameValues(expectedQuestions, actualQuestions)) {
      return _error(
        'QUESTIONNAIRE_PLAN_INVALID',
        'Question order or identity changed during pagination.',
        template,
      );
    }
    for (var index = 0; index < plan.pages.length; index++) {
      final page = plan.pages[index];
      if (page.pageNumber != index + 1 ||
          page.totalPageCount != plan.pages.length ||
          page.columns.length != 2 ||
          (page.columns[0].width - page.columns[1].width).abs() > 1e-8) {
        return _error(
          'QUESTIONNAIRE_PLAN_INVALID',
          'Every page must expose two equal columns and consistent numbering.',
          template,
        );
      }
      for (final placement in page.text.where(
        (item) => item.role.index >= QuestionnaireTextRole.sectionTitle.index,
      )) {
        if (!page.columns.any(
          (column) => _contains(column, placement.bounds),
        )) {
          return _error(
            'QUESTIONNAIRE_PLAN_INVALID',
            'Questionnaire content escaped its assigned column.',
            template,
          );
        }
      }
    }
    return null;
  }

  bool _contains(PdfPointRect outer, PdfPointRect inner) =>
      inner.left >= outer.left - 1e-8 &&
      inner.top >= outer.top - 1e-8 &&
      inner.left + inner.width <= outer.left + outer.width + 1e-8 &&
      inner.top + inner.height <= outer.top + outer.height + 1e-8;

  bool _sameValues<T>(List<T> first, List<T> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  EngineError _error(
    String code,
    String message,
    TemplateDefinition template, {
    Map<String, Object?> details = const {},
  }) => EngineError(
    code: code,
    message: message,
    details: {
      'templateId': template.id.value,
      'templateVersion': template.version.value,
      ...details,
    },
  );
}

final class _QuestionnairePlanBuilder {
  _QuestionnairePlanBuilder({
    required this.template,
    required this.fonts,
    required this.context,
    required this.style,
  }) : measurer = _PdfTextMeasurer(context, fonts);

  final TemplateDefinition template;
  final PdfRenderFonts fonts;
  final pw.Context context;
  final QuestionnairePdfStyle style;
  final _PdfTextMeasurer measurer;
  final List<_MutablePage> _pages = [];
  var _pageIndex = 0;
  var _columnIndex = 0;
  var _cursorY = 0.0;

  QuestionnairePdfPlan build() {
    _addPage();
    var questionNumber = 0;
    for (final section in template.sections) {
      final sectionGroup = _sectionGroup(section);
      final firstQuestion = section.questions.firstOrNull;
      final firstGroup = firstQuestion == null
          ? null
          : _questionGroup(firstQuestion, questionNumber + 1, section.id);
      final firstOpening = firstGroup == null
          ? 0.0
          : firstGroup.totalHeight <= _column.height
          ? firstGroup.totalHeight
          : firstGroup.openingHeight;
      final combinedOpening = sectionGroup.totalHeight + firstOpening;
      if (combinedOpening <= _column.height && combinedOpening > _remaining) {
        _advanceColumn();
      }
      _placeGroup(sectionGroup);

      for (final question in section.questions) {
        questionNumber++;
        _placeGroup(_questionGroup(question, questionNumber, section.id));
      }
    }

    final total = _pages.length;
    return QuestionnairePdfPlan(
      templateId: template.id,
      templateVersion: template.version,
      pages: [
        for (var index = 0; index < _pages.length; index++)
          _pages[index].freeze(index + 1, total),
      ],
    );
  }

  _FlowGroup _sectionGroup(TemplateSection section) {
    final lines = <_FlowLine>[];
    lines.addAll(
      _flowLines(
        section.title,
        role: QuestionnaireTextRole.sectionTitle,
        fontSize: style.sectionFontSizePoints,
        bold: true,
        sectionId: section.id,
        startsSection: true,
      ),
    );
    if (section.instruction case final instruction?) {
      lines.addAll(
        _flowLines(
          instruction,
          role: QuestionnaireTextRole.sectionInstruction,
          fontSize: style.instructionFontSizePoints,
          sectionId: section.id,
        ),
      );
    }
    if (section.humanReadableTextField case final field?) {
      lines.addAll(
        _flowLines(
          [field.label, ?field.instruction].join(' - '),
          role: QuestionnaireTextRole.humanReadableField,
          fontSize: style.optionFontSizePoints,
          sectionId: section.id,
        ),
      );
    }
    return _FlowGroup(lines, trailingGap: style.sectionGapPoints);
  }

  _FlowGroup _questionGroup(
    TemplateQuestion question,
    int number,
    SectionId sectionId,
  ) {
    final lines = <_FlowLine>[];
    lines.addAll(
      _flowLines(
        '$number. ${question.prompt}',
        role: QuestionnaireTextRole.questionPrompt,
        fontSize: style.questionFontSizePoints,
        bold: true,
        sectionId: sectionId,
        questionId: question.id,
        questionNumber: number,
        startsQuestion: true,
      ),
    );
    if (question.description case final description?) {
      lines.addAll(
        _flowLines(
          description,
          role: QuestionnaireTextRole.questionDescription,
          fontSize: style.optionFontSizePoints,
          sectionId: sectionId,
          questionId: question.id,
          questionNumber: number,
          indent: style.optionIndentPoints,
        ),
      );
    }

    if (question.type == QuestionType.numericGrid) {
      final spec = question.numericGridSpec!;
      lines.addAll(
        _flowLines(
          'Response format: ${spec.columnCount} digit${spec.columnCount == 1 ? '' : 's'}; '
          'allowed values ${spec.allowedDigits.join(', ')}.',
          role: QuestionnaireTextRole.numericInstruction,
          fontSize: style.optionFontSizePoints,
          sectionId: sectionId,
          questionId: question.id,
          questionNumber: number,
          indent: style.optionIndentPoints,
        ),
      );
    } else {
      for (var index = 0; index < question.options.length; index++) {
        final option = question.options[index];
        final prefix = switch (question.type) {
          QuestionType.multipleChoice => '[ ]',
          QuestionType.likert => '${option.value ?? index + 1} -',
          _ => '${_alphabeticLabel(index)}.',
        };
        lines.addAll(
          _flowLines(
            '$prefix ${option.label}',
            role: QuestionnaireTextRole.option,
            fontSize: style.optionFontSizePoints,
            sectionId: sectionId,
            questionId: question.id,
            optionId: option.id,
            questionNumber: number,
            indent: style.optionIndentPoints,
          ),
        );
      }
    }
    final firstResponse = lines.indexWhere(
      (line) =>
          line.role == QuestionnaireTextRole.option ||
          line.role == QuestionnaireTextRole.numericInstruction,
    );
    final openingEnd = firstResponse < 0
        ? math.min(1, lines.length)
        : firstResponse + 1;
    final openingHeight = lines
        .take(openingEnd)
        .fold<double>(0, (height, line) => height + line.height);
    return _FlowGroup(
      lines,
      trailingGap: style.questionGapPoints,
      openingHeight: openingHeight,
    );
  }

  List<_FlowLine> _flowLines(
    String text, {
    required QuestionnaireTextRole role,
    required double fontSize,
    bool bold = false,
    double indent = 0,
    SectionId? sectionId,
    QuestionId? questionId,
    OptionId? optionId,
    int? questionNumber,
    bool startsSection = false,
    bool startsQuestion = false,
  }) {
    final font = bold ? fonts.bold : fonts.regular;
    final wrapped = measurer.wrap(
      text,
      maxWidth: _columnWidth - indent,
      font: font,
      fontSize: fontSize,
    );
    return [
      for (var index = 0; index < wrapped.length; index++)
        _FlowLine(
          text: wrapped[index],
          role: role,
          height: fontSize * style.lineHeightFactor,
          fontSize: fontSize,
          bold: bold,
          indent: indent,
          sectionId: sectionId,
          questionId: questionId,
          optionId: index == 0 ? optionId : null,
          questionNumber: questionNumber,
          startsSection: startsSection && index == 0,
          startsQuestion: startsQuestion && index == 0,
        ),
    ];
  }

  void _placeGroup(_FlowGroup group) {
    if (group.lines.isEmpty) return;
    if (group.totalHeight <= _column.height && group.totalHeight > _remaining) {
      _advanceColumn();
    } else if (group.totalHeight > _column.height &&
        group.openingHeight > _remaining &&
        group.openingHeight <= _column.height) {
      _advanceColumn();
    }

    for (final line in group.lines) {
      if (line.height > _remaining) _advanceColumn();
      final column = _column;
      _page.text.add(
        QuestionnaireTextPlacement(
          role: line.role,
          text: line.text,
          bounds: PdfPointRect(
            left: column.left + line.indent,
            top: _cursorY,
            width: column.width - line.indent,
            height: line.height,
          ),
          fontSizePoints: line.fontSize,
          bold: line.bold,
          sectionId: line.sectionId,
          questionId: line.questionId,
          optionId: line.optionId,
          questionNumber: line.questionNumber,
          startsSection: line.startsSection,
          startsQuestion: line.startsQuestion,
        ),
      );
      _cursorY += line.height;
    }
    _cursorY = math.min(
      _column.top + _column.height,
      _cursorY + group.trailingGap,
    );
  }

  void _addPage() {
    if (_pages.length >= style.maxPages) {
      throw const _PaginationException(
        'QUESTIONNAIRE_PAGE_LIMIT_EXCEEDED',
        'Questionnaire pagination exceeded the configured page limit.',
      );
    }
    final page = _createPage(_pages.length);
    _pages.add(page);
    _pageIndex = _pages.length - 1;
    _columnIndex = 0;
    _cursorY = page.columns.first.top;
  }

  _MutablePage _createPage(int index) {
    final pageWidth = PdfPageFormat.a4.width;
    final pageHeight = PdfPageFormat.a4.height;
    final margin = style.outerMarginPoints;
    final contentWidth = pageWidth - margin * 2;
    var y = margin;
    final headerText = <QuestionnaireTextPlacement>[];

    void addHeaderLines(
      String text,
      QuestionnaireTextRole role,
      double fontSize,
      bool bold,
    ) {
      final font = bold ? fonts.bold : fonts.regular;
      final lines = measurer.wrap(
        text,
        maxWidth: contentWidth,
        font: font,
        fontSize: fontSize,
      );
      for (final line in lines) {
        final height = fontSize * style.lineHeightFactor;
        headerText.add(
          QuestionnaireTextPlacement(
            role: role,
            text: line,
            bounds: PdfPointRect(
              left: margin,
              top: y,
              width: contentWidth,
              height: height,
            ),
            fontSizePoints: fontSize,
            bold: bold,
          ),
        );
        y += height;
      }
    }

    addHeaderLines(
      template.name,
      QuestionnaireTextRole.title,
      index == 0
          ? style.titleFontSizePoints
          : style.repeatedTitleFontSizePoints,
      true,
    );
    addHeaderLines(
      'Template ${template.id.value} | Version ${template.version.value}',
      QuestionnaireTextRole.documentIdentity,
      style.identityFontSizePoints,
      false,
    );
    if (index == 0) {
      if (template.description case final description?) {
        y += 2;
        addHeaderLines(
          description,
          QuestionnaireTextRole.documentInstruction,
          style.instructionFontSizePoints,
          false,
        );
      }
    }
    final headerBottom = y + style.headerGapPoints;
    final footer = PdfPointRect(
      left: margin,
      top: pageHeight - margin - style.footerHeightPoints,
      width: contentWidth,
      height: style.footerHeightPoints,
    );
    final columnTop = headerBottom + style.headerGapPoints;
    final columnBottom = footer.top - style.headerGapPoints;
    final columnHeight = columnBottom - columnTop;
    final columnWidth = (contentWidth - style.columnGutterPoints) / 2;
    if (columnHeight <=
            style.questionFontSizePoints * style.lineHeightFactor * 3 ||
        columnWidth <= 0) {
      throw const _PaginationException(
        'QUESTIONNAIRE_HEADER_TOO_LARGE',
        'The title or general instructions leave no readable column area.',
      );
    }
    return _MutablePage(
      width: pageWidth,
      height: pageHeight,
      headerBounds: PdfPointRect(
        left: margin,
        top: margin,
        width: contentWidth,
        height: headerBottom - margin,
      ),
      footerBounds: footer,
      columns: [
        PdfPointRect(
          left: margin,
          top: columnTop,
          width: columnWidth,
          height: columnHeight,
        ),
        PdfPointRect(
          left: margin + columnWidth + style.columnGutterPoints,
          top: columnTop,
          width: columnWidth,
          height: columnHeight,
        ),
      ],
      text: headerText,
    );
  }

  void _advanceColumn() {
    if (_columnIndex == 0) {
      _columnIndex = 1;
      _cursorY = _column.top;
    } else {
      _addPage();
    }
  }

  _MutablePage get _page => _pages[_pageIndex];
  PdfPointRect get _column => _page.columns[_columnIndex];
  double get _remaining => _column.top + _column.height - _cursorY;
  double get _columnWidth {
    final pageWidth = PdfPageFormat.a4.width;
    final contentWidth = pageWidth - style.outerMarginPoints * 2;
    return (contentWidth - style.columnGutterPoints) / 2;
  }
}

final class _PdfTextMeasurer {
  const _PdfTextMeasurer(this.context, this.fonts);

  final pw.Context context;
  final PdfRenderFonts fonts;

  List<String> wrap(
    String text, {
    required double maxWidth,
    required pw.Font font,
    required double fontSize,
  }) {
    final output = <String>[];
    for (final paragraph in text.replaceAll('\r\n', '\n').split('\n')) {
      if (paragraph.trim().isEmpty) {
        output.add('');
        continue;
      }
      var line = '';
      for (final originalWord in paragraph.trim().split(RegExp(r'\s+'))) {
        final pieces = _splitLongWord(originalWord, maxWidth, font, fontSize);
        for (final word in pieces) {
          final candidate = line.isEmpty ? word : '$line $word';
          if (line.isNotEmpty && _width(candidate, font, fontSize) > maxWidth) {
            output.add(line);
            line = word;
          } else {
            line = candidate;
          }
        }
      }
      if (line.isNotEmpty) output.add(line);
    }
    return output.isEmpty ? [''] : output;
  }

  List<String> _splitLongWord(
    String word,
    double maxWidth,
    pw.Font font,
    double fontSize,
  ) {
    if (_width(word, font, fontSize) <= maxWidth) return [word];
    final result = <String>[];
    var current = '';
    for (final rune in word.runes) {
      final next = '$current${String.fromCharCode(rune)}';
      if (current.isNotEmpty && _width(next, font, fontSize) > maxWidth) {
        result.add(current);
        current = String.fromCharCode(rune);
      } else {
        current = next;
      }
    }
    if (current.isNotEmpty) result.add(current);
    return result;
  }

  double _width(String text, pw.Font preferred, double fontSize) {
    final choices = [preferred, ...fonts.fallback];
    var width = 0.0;
    pw.Font? currentFont;
    final buffer = StringBuffer();

    void flush() {
      final selectedFont = currentFont;
      if (buffer.isEmpty || selectedFont == null) return;
      width +=
          selectedFont.getFont(context).stringMetrics(buffer.toString()).width *
          fontSize;
      buffer.clear();
    }

    for (final rune in text.runes) {
      final selected = choices.firstWhere(
        (candidate) => candidate.getFont(context).isRuneSupported(rune),
        orElse: () => preferred,
      );
      if (!identical(selected, currentFont)) {
        flush();
        currentFont = selected;
      }
      buffer.writeCharCode(rune);
    }
    flush();
    return width;
  }
}

final class _FlowLine {
  const _FlowLine({
    required this.text,
    required this.role,
    required this.height,
    required this.fontSize,
    required this.bold,
    required this.indent,
    this.sectionId,
    this.questionId,
    this.optionId,
    this.questionNumber,
    this.startsSection = false,
    this.startsQuestion = false,
  });

  final String text;
  final QuestionnaireTextRole role;
  final double height;
  final double fontSize;
  final bool bold;
  final double indent;
  final SectionId? sectionId;
  final QuestionId? questionId;
  final OptionId? optionId;
  final int? questionNumber;
  final bool startsSection;
  final bool startsQuestion;
}

final class _FlowGroup {
  const _FlowGroup(
    this.lines, {
    required this.trailingGap,
    double? openingHeight,
  }) : openingHeight = openingHeight ?? 0;

  final List<_FlowLine> lines;
  final double trailingGap;
  final double openingHeight;
  double get totalHeight =>
      lines.fold<double>(0, (height, line) => height + line.height) +
      trailingGap;
}

final class _MutablePage {
  const _MutablePage({
    required this.width,
    required this.height,
    required this.headerBounds,
    required this.footerBounds,
    required this.columns,
    required this.text,
  });

  final double width;
  final double height;
  final PdfPointRect headerBounds;
  final PdfPointRect footerBounds;
  final List<PdfPointRect> columns;
  final List<QuestionnaireTextPlacement> text;

  QuestionnairePagePlan freeze(int pageNumber, int totalPageCount) =>
      QuestionnairePagePlan(
        pageNumber: pageNumber,
        totalPageCount: totalPageCount,
        pageWidthPoints: width,
        pageHeightPoints: height,
        headerBounds: headerBounds,
        footerBounds: footerBounds,
        columns: columns,
        text: text,
      );
}

final class _PaginationException implements Exception {
  const _PaginationException(this.code, this.message);

  final String code;
  final String message;
}

String _alphabeticLabel(int index) {
  var value = index;
  final output = StringBuffer();
  do {
    output.writeCharCode(65 + value % 26);
    value = value ~/ 26 - 1;
  } while (value >= 0);
  return output.toString().split('').reversed.join();
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
