import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/errors/engine_error.dart';
import '../../../core/geometry/physical_geometry.dart';
import '../../../core/result/engine_result.dart';
import '../../layout/domain/layout_regions.dart';
import '../../layout/domain/page_layout.dart';
import '../../template/domain/template_definition.dart';
import '../../template/domain/template_question.dart';
import '../../template/domain/template_section.dart';
import '../domain/aruco_marker_encoder.dart';
import '../domain/pdf_render_plan.dart';
import '../domain/pdf_render_style.dart';
import '../domain/pdf_units.dart';
import '../domain/template_page_identity_codec.dart';
import '../infrastructure/opencv_4x4_50_marker_encoder.dart';

/// Renders semantic template text over the exact geometry supplied by layout.
final class PdfEngine {
  PdfEngine({
    ArucoMarkerEncoder? markerEncoder,
    TemplatePageIdentityCodec? identityCodec,
    this.style = const PdfRenderStyle(),
  }) : markerEncoder =
           markerEncoder ?? const OpenCvDictionary4x4MarkerEncoder(),
       identityCodec = identityCodec ?? const TemplatePageIdentityCodec();

  final ArucoMarkerEncoder markerEncoder;
  final TemplatePageIdentityCodec identityCodec;
  final PdfRenderStyle style;

  EngineResult<PdfRenderPlan> buildPlan(
    TemplateDefinition template,
    LayoutDocument layout,
  ) {
    final identityError = _validateIdentity(template, layout);
    if (identityError != null) return EngineResult.failure(identityError);

    try {
      final sectionsById = {
        for (final section in template.sections) section.id: section,
      };
      final questionsById = {
        for (final section in template.sections)
          for (final question in section.questions) question.id: question,
      };
      final pages = <PdfPageRenderPlan>[];

      for (final page in layout.pages) {
        final pageError = _validatePage(page, layout.pages.length);
        if (pageError != null) return EngineResult.failure(pageError);

        final markers = <PdfMarkerCommand>[];
        for (final region in page.markerRegions) {
          ArucoMarkerMatrix marker;
          try {
            marker = markerEncoder.encode(region.markerId);
          } on Object catch (error) {
            return EngineResult.failure(
              EngineError(
                code: 'PDF_MARKER_ENCODING_FAILED',
                message: 'Unable to encode a printable marker.',
                details: {
                  'markerId': region.markerId,
                  'cause': error.toString(),
                },
              ),
            );
          }
          if (marker.markerId != region.markerId) {
            return EngineResult.failure(
              EngineError(
                code: 'PDF_MARKER_ENCODING_FAILED',
                message: 'Marker encoder returned a different marker ID.',
                details: {
                  'requested': region.markerId,
                  'encoded': marker.markerId,
                },
              ),
            );
          }
          markers.add(PdfMarkerCommand(region: region, marker: marker));
        }

        final text = <PdfTextCommand>[
          PdfTextCommand(
            role: PdfTextRole.header,
            text:
                '${template.name} - Page ${page.pageIndex + 1} of ${page.totalPageCount}',
            bounds: page.headerRegion.physicalBounds,
          ),
        ];

        for (final sectionRegion in page.sectionRegions) {
          final section = sectionsById[sectionRegion.sectionId];
          if (section == null) {
            return _invalidLayout('Layout references an unknown section.', {
              'sectionId': sectionRegion.sectionId.value,
            });
          }
          _addSectionText(text, section, sectionRegion);

          for (final questionRegion in sectionRegion.questionRegions) {
            final question = questionsById[questionRegion.questionId];
            if (question == null) {
              return _invalidLayout('Layout references an unknown question.', {
                'questionId': questionRegion.questionId.value,
              });
            }
            final questionError = _addQuestionText(
              text,
              question,
              questionRegion,
            );
            if (questionError != null) {
              return EngineResult.failure(questionError);
            }
          }
        }

        final payload = identityCodec.encode(
          templateId: page.templateId,
          templateVersion: page.templateVersion,
          pageId: page.pageId,
        );
        pages.add(
          PdfPageRenderPlan(
            layout: page,
            identity: PdfIdentityCommand(
              payload: payload,
              bounds: page.templateIdentityRegion.physicalBounds,
            ),
            markers: markers,
            text: text,
            bubbles: page.bubbleRegions,
          ),
        );
      }

      return EngineResult.success(PdfRenderPlan(pages: pages));
    } on Object catch (error) {
      return EngineResult.failure(
        EngineError(
          code: 'PDF_INVALID_LAYOUT',
          message:
              'Unable to build a PDF render plan from the supplied layout.',
          details: {'cause': error.toString()},
        ),
      );
    }
  }

  Future<EngineResult<Uint8List>> render(
    TemplateDefinition template,
    LayoutDocument layout,
  ) async {
    final planResult = buildPlan(template, layout);
    if (planResult.isFailure) {
      return EngineResult.failure(planResult.error);
    }

    try {
      final document = pw.Document(
        title: template.name,
        creator: 'TalaanScan PDF Engine',
        producer: 'TalaanScan',
      );
      for (final page in planResult.value.pages) {
        document.addPage(_buildPage(page));
      }
      final bytes = await document.save();
      if (bytes.isEmpty) {
        return EngineResult.failure(
          EngineError(
            code: 'PDF_RENDER_FAILED',
            message: 'PDF renderer produced no bytes.',
          ),
        );
      }
      return EngineResult.success(bytes);
    } on Object catch (error) {
      return EngineResult.failure(
        EngineError(
          code: 'PDF_RENDER_FAILED',
          message: 'PDF generation failed.',
          details: {'cause': error.toString()},
        ),
      );
    }
  }

  EngineError? _validateIdentity(
    TemplateDefinition template,
    LayoutDocument layout,
  ) {
    if (layout.templateId != template.id) {
      return EngineError(
        code: 'PDF_TEMPLATE_LAYOUT_MISMATCH',
        message: 'Template and layout IDs do not match.',
      );
    }
    if (layout.templateVersion != template.version) {
      return EngineError(
        code: 'PDF_TEMPLATE_LAYOUT_MISMATCH',
        message: 'Template and layout versions do not match.',
      );
    }
    return null;
  }

  EngineError? _validatePage(PageLayout page, int actualPageCount) {
    final pageBounds = page.physicalPageBounds;
    if (page.totalPageCount != actualPageCount ||
        page.pageIndex < 0 ||
        page.pageIndex >= actualPageCount ||
        pageBounds.left.millimeters != 0 ||
        pageBounds.top.millimeters != 0 ||
        pageBounds.width != page.pageSpec.size.width ||
        pageBounds.height != page.pageSpec.size.height) {
      return EngineError(
        code: 'PDF_INVALID_LAYOUT',
        message: 'Page metadata or physical dimensions are inconsistent.',
        details: {'pageId': page.pageId.value},
      );
    }
    if (page.markerRegions.length != 4 ||
        page.markerRegions.map((marker) => marker.markerId).toSet().length !=
            4) {
      return EngineError(
        code: 'PDF_INVALID_LAYOUT',
        message: 'Each printable page requires four unique marker IDs.',
        details: {'pageId': page.pageId.value},
      );
    }

    final regions = <PhysicalRect>[
      page.printableBounds,
      page.safeBounds,
      page.templateIdentityRegion.physicalBounds,
      page.headerRegion.physicalBounds,
      ...page.markerRegions.map((region) => region.physicalBounds),
      ...page.sectionRegions.map((region) => region.physicalBounds),
      ...page.sectionRegions.expand(
        (section) => [
          section.titleRegion?.physicalBounds,
          section.instructionRegion?.physicalBounds,
          section.humanReadableFieldRegion?.physicalBounds,
        ].whereType<PhysicalRect>(),
      ),
      ...page.questionRegions.map((region) => region.physicalBounds),
      ...page.bubbleRegions.map((region) => region.physicalBounds),
    ];
    if (regions.any((region) => !pageBounds.containsRect(region))) {
      return EngineError(
        code: 'PDF_INVALID_LAYOUT',
        message: 'A supplied region lies outside the physical page.',
        details: {'pageId': page.pageId.value},
      );
    }
    return null;
  }

  void _addSectionText(
    List<PdfTextCommand> output,
    TemplateSection section,
    SectionRegion region,
  ) {
    final titleRegion = region.titleRegion;
    if (titleRegion != null) {
      output.add(
        PdfTextCommand(
          role: PdfTextRole.sectionTitle,
          text: section.title,
          bounds: titleRegion.physicalBounds,
          sectionId: section.id,
        ),
      );
    }
    final instructionRegion = region.instructionRegion;
    if (instructionRegion != null && section.instruction != null) {
      output.add(
        PdfTextCommand(
          role: PdfTextRole.sectionInstruction,
          text: section.instruction!,
          bounds: instructionRegion.physicalBounds,
          sectionId: section.id,
        ),
      );
    }
    final fieldRegion = region.humanReadableFieldRegion;
    final field = section.humanReadableTextField;
    if (fieldRegion != null && field != null) {
      output.add(
        PdfTextCommand(
          role: PdfTextRole.humanReadableField,
          text: [
            field.label,
            if (field.instruction != null) field.instruction!,
          ].join('\n'),
          bounds: fieldRegion.physicalBounds,
          sectionId: section.id,
        ),
      );
    }
  }

  EngineError? _addQuestionText(
    List<PdfTextCommand> output,
    TemplateQuestion question,
    QuestionRegion region,
  ) {
    if (region.bubbleRegions.isEmpty) {
      return EngineError(
        code: 'PDF_INVALID_LAYOUT',
        message: 'A printable question has no bubble regions.',
        details: {'questionId': question.id.value},
      );
    }
    final firstBubbleTop = region.bubbleRegions
        .map((bubble) => bubble.physicalBounds.top.millimeters)
        .reduce(math.min);
    final promptHeight = firstBubbleTop - region.physicalBounds.top.millimeters;
    if (promptHeight <= 0) {
      return EngineError(
        code: 'PDF_INVALID_LAYOUT',
        message: 'Question prompt has no space before its bubbles.',
        details: {'questionId': question.id.value},
      );
    }
    output.add(
      PdfTextCommand(
        role: PdfTextRole.questionPrompt,
        text: [
          question.prompt,
          if (question.description != null) question.description!,
        ].join('\n'),
        bounds: PhysicalRect.millimeters(
          left: region.physicalBounds.left.millimeters,
          top: region.physicalBounds.top.millimeters,
          width: region.physicalBounds.width.millimeters,
          height: promptHeight,
        ),
        questionId: question.id,
      ),
    );

    for (final bubble in region.bubbleRegions) {
      final label = bubble.optionId == null
          ? bubble.numericDigitValue.toString()
          : question.options
                .where((option) => option.id == bubble.optionId)
                .firstOrNull
                ?.label;
      if (label == null) {
        return EngineError(
          code: 'PDF_INVALID_LAYOUT',
          message: 'Bubble does not map to template semantics.',
          details: {'questionId': question.id.value},
        );
      }
      final labelBounds = _labelBounds(region, bubble);
      output.add(
        PdfTextCommand(
          role: bubble.optionId == null
              ? PdfTextRole.numericDigit
              : PdfTextRole.optionLabel,
          text: label,
          bounds: labelBounds,
          questionId: question.id,
          optionId: bubble.optionId,
          numericColumnIndex: bubble.numericColumnIndex,
          numericDigitValue: bubble.numericDigitValue,
        ),
      );
    }
    return null;
  }

  PhysicalRect _labelBounds(QuestionRegion question, BubbleRegion bubble) {
    const labelGapMm = 1.0;
    final bounds = bubble.physicalBounds;
    var right = question.physicalBounds.right.millimeters;
    for (final other in question.bubbleRegions) {
      final otherBounds = other.physicalBounds;
      final sharesRow =
          otherBounds.top.millimeters < bounds.bottom.millimeters &&
          otherBounds.bottom.millimeters > bounds.top.millimeters;
      if (sharesRow &&
          otherBounds.left.millimeters > bounds.right.millimeters &&
          otherBounds.left.millimeters < right) {
        right = otherBounds.left.millimeters;
      }
    }
    final left = bounds.right.millimeters + labelGapMm;
    final width = right - left;
    if (width <= 0) {
      throw ArgumentError('No safe label area adjacent to bubble.');
    }
    return PhysicalRect.millimeters(
      left: left,
      top: bounds.top.millimeters,
      width: width,
      height: bounds.height.millimeters,
    );
  }

  EngineResult<PdfRenderPlan> _invalidLayout(
    String message,
    Map<String, Object?> details,
  ) => EngineResult.failure(
    EngineError(code: 'PDF_INVALID_LAYOUT', message: message, details: details),
  );

  pw.Page _buildPage(PdfPageRenderPlan plan) {
    final page = plan.layout;
    final pageWidth = PdfUnits.lengthToPoints(page.pageSpec.size.width);
    final pageHeight = PdfUnits.lengthToPoints(page.pageSpec.size.height);
    return pw.Page(
      pageFormat: PdfPageFormat(pageWidth, pageHeight),
      margin: pw.EdgeInsets.zero,
      clip: true,
      build: (_) {
        final children = <pw.Widget>[];
        if (style.debugOverlays) {
          children.addAll(_debugWidgets(page));
        }
        children.add(_identityWidget(plan.identity));
        children.addAll(plan.markers.map(_markerWidget));
        children.addAll(plan.text.map(_textWidget));
        children.addAll(plan.bubbles.map(_bubbleWidget));
        return pw.Stack(fit: pw.StackFit.expand, children: children);
      },
    );
  }

  pw.Widget _identityWidget(PdfIdentityCommand command) {
    final rect = PdfUnits.rectToPoints(command.bounds);
    final qrSize = math.min(rect.width, rect.height);
    return _positioned(
      command.bounds,
      pw.Align(
        alignment: pw.Alignment.centerLeft,
        child: pw.SizedBox(
          width: qrSize,
          height: qrSize,
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: command.payload,
            drawText: false,
            backgroundColor: PdfColors.white,
          ),
        ),
      ),
    );
  }

  pw.Widget _markerWidget(PdfMarkerCommand command) {
    final modules = command.marker.modules;
    return _positioned(
      command.region.physicalBounds,
      pw.LayoutBuilder(
        builder: (_, constraints) {
          final cellWidth = constraints!.maxWidth / modules.length;
          final cellHeight = constraints.maxHeight / modules.length;
          return pw.Container(
            color: PdfColors.white,
            child: pw.Stack(
              fit: pw.StackFit.expand,
              children: [
                for (var row = 0; row < modules.length; row++)
                  for (var column = 0; column < modules.length; column++)
                    if (modules[row][column])
                      pw.Positioned(
                        left: column * cellWidth,
                        top: row * cellHeight,
                        child: pw.Container(
                          width: cellWidth,
                          height: cellHeight,
                          color: PdfColors.black,
                        ),
                      ),
              ],
            ),
          );
        },
      ),
    );
  }

  pw.Widget _bubbleWidget(BubbleRegion bubble) => _positioned(
    bubble.physicalBounds,
    pw.Container(
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border.all(
          color: PdfColors.black,
          width: style.bubbleStrokeWidthPoints,
        ),
      ),
    ),
  );

  pw.Widget _textWidget(PdfTextCommand command) {
    if (command.role == PdfTextRole.humanReadableField) {
      return _positioned(
        command.bounds,
        pw.Stack(
          fit: pw.StackFit.expand,
          children: [
            pw.Positioned.fill(
              bottom: PdfUnits.millimetersToPoints(3),
              child: _clampedText(command.text, style.bodyFontSizePoints),
            ),
            pw.Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: pw.Container(
                height: PdfUnits.millimetersToPoints(3),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: PdfColors.black,
                    width: style.fieldStrokeWidthPoints,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final fontSize = switch (command.role) {
      PdfTextRole.header => style.headerFontSizePoints,
      PdfTextRole.sectionTitle => style.sectionTitleFontSizePoints,
      PdfTextRole.optionLabel ||
      PdfTextRole.numericDigit => style.labelFontSizePoints,
      _ => style.bodyFontSizePoints,
    };
    return _positioned(command.bounds, _clampedText(command.text, fontSize));
  }

  pw.Widget _clampedText(String text, double fontSize) => pw.ClipRect(
    child: pw.FittedBox(
      fit: pw.BoxFit.scaleDown,
      alignment: pw.Alignment.topLeft,
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: fontSize, color: PdfColors.black),
      ),
    ),
  );

  Iterable<pw.Widget> _debugWidgets(PageLayout page) sync* {
    yield _outline(page.safeBounds, PdfColors.blue);
    yield _outline(page.templateIdentityRegion.physicalBounds, PdfColors.green);
    yield _outline(page.headerRegion.physicalBounds, PdfColors.orange);
    for (final section in page.sectionRegions) {
      yield _outline(section.physicalBounds, PdfColors.purple);
    }
    for (final question in page.questionRegions) {
      yield _outline(question.physicalBounds, PdfColors.grey);
    }
  }

  pw.Widget _outline(PhysicalRect bounds, PdfColor color) => _positioned(
    bounds,
    pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: color,
          width: style.diagnosticStrokeWidthPoints,
        ),
      ),
    ),
  );

  pw.Widget _positioned(PhysicalRect bounds, pw.Widget child) {
    final rect = PdfUnits.rectToPoints(bounds);
    return pw.Positioned(
      left: rect.left,
      top: rect.top,
      child: pw.SizedBox(width: rect.width, height: rect.height, child: child),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
