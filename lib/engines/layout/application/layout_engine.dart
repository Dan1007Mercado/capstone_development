import 'dart:math' as math;

import '../../../core/errors/engine_error.dart';
import '../../../core/geometry/geometry_converter.dart';
import '../../../core/geometry/normalized_geometry.dart';
import '../../../core/geometry/physical_geometry.dart';
import '../../../core/ids/identifiers.dart';
import '../../../core/result/engine_result.dart';
import '../../template/application/template_validator.dart';
import '../../template/domain/question_type.dart';
import '../../template/domain/template_definition.dart';
import '../../template/domain/template_question.dart';
import '../../template/domain/template_section.dart';
import '../domain/layout_config.dart';
import '../domain/layout_regions.dart';
import '../domain/page_layout.dart';

/// Deterministic bridge from validated template semantics to page geometry.
final class LayoutEngine {
  LayoutEngine({TemplateValidator? templateValidator})
    : _templateValidator = templateValidator ?? TemplateValidator();

  final TemplateValidator _templateValidator;

  EngineResult<LayoutDocument> build(
    TemplateDefinition template,
    LayoutConfig config,
  ) {
    final templateValidation = _templateValidator.validate(template);
    if (!templateValidation.isValid) {
      return EngineResult.failure(
        EngineError(
          code: 'TEMPLATE_INVALID',
          message: 'Template validation failed before layout.',
          details: {
            'issueCodes': templateValidation.errors
                .map((issue) => issue.code)
                .toList(growable: false),
          },
        ),
      );
    }

    final configError = _validateConfig(config);
    if (configError != null) return EngineResult.failure(configError);

    try {
      final geometry = _createStaticGeometry(config);
      final draftsResult = _placeTemplate(template, config, geometry);
      if (draftsResult.isFailure) {
        return EngineResult.failure(draftsResult.error);
      }

      final drafts = draftsResult.value;
      final totalPageCount = drafts.length;
      final pages = drafts
          .map(
            (draft) => _materializePage(
              template,
              config,
              geometry,
              draft,
              totalPageCount,
            ),
          )
          .toList(growable: false);

      final geometryError = _validateGeneratedGeometry(pages);
      if (geometryError != null) return EngineResult.failure(geometryError);

      return EngineResult.success(
        LayoutDocument(
          templateId: template.id,
          templateVersion: template.version,
          pages: pages,
        ),
      );
    } on ArgumentError catch (error) {
      return EngineResult.failure(
        EngineError(
          code: 'GEOMETRY_INVALID',
          message: 'Generated layout geometry was invalid.',
          details: {'cause': error.toString()},
        ),
      );
    }
  }

  EngineError? _validateConfig(LayoutConfig config) {
    if (!config.markerIds.areUnique) {
      return EngineError(
        code: 'MARKER_IDS_DUPLICATE',
        message: 'All marker IDs must be unique.',
      );
    }
    if (config.markerIds.values.any((id) => id < 0)) {
      return EngineError(
        code: 'LAYOUT_CONFIG_INVALID',
        message: 'Marker IDs must be non-negative.',
      );
    }

    final positiveValues = <String, double>{
      'markerSizeMm': config.markerSizeMm,
      'bubbleDiameterMm': config.bubbleDiameterMm,
      'bubbleHorizontalGapMm': config.bubbleHorizontalGapMm,
      'bubbleVerticalGapMm': config.bubbleVerticalGapMm,
      'optionCellWidthMm': config.optionCellWidthMm,
      'questionVerticalGapMm': config.questionVerticalGapMm,
      'sectionGapMm': config.sectionGapMm,
      'headerHeightMm': config.headerHeightMm,
      'identityRegionHeightMm': config.identityRegionHeightMm,
      'minimumContentGapMm': config.minimumContentGapMm,
      'estimatedLineHeightMm': config.estimatedLineHeightMm,
      'humanReadableFieldHeightMm': config.humanReadableFieldHeightMm,
    };
    for (final entry in positiveValues.entries) {
      if (!entry.value.isFinite || entry.value <= 0) {
        return EngineError(
          code: 'LAYOUT_CONFIG_INVALID',
          message: '${entry.key} must be finite and positive.',
        );
      }
    }
    if (!config.markerInsetMm.isFinite || config.markerInsetMm < 0) {
      return EngineError(
        code: 'LAYOUT_CONFIG_INVALID',
        message: 'markerInsetMm must be finite and non-negative.',
      );
    }
    if (config.estimatedCharactersPerLine <= 0) {
      return EngineError(
        code: 'LAYOUT_CONFIG_INVALID',
        message: 'estimatedCharactersPerLine must be positive.',
      );
    }

    PhysicalRect printableBounds;
    try {
      printableBounds = config.margins.contentRect(config.pageSpec.size);
    } on RangeError {
      return EngineError(
        code: 'CONTENT_AREA_INVALID',
        message: 'Page margins do not leave a positive printable area.',
      );
    }

    final pageWidth = config.pageSpec.size.width.millimeters;
    final pageHeight = config.pageSpec.size.height.millimeters;
    final markerExtent = config.markerInsetMm + config.markerSizeMm;
    if (markerExtent > pageWidth / 2 || markerExtent > pageHeight / 2) {
      return EngineError(
        code: 'MARKER_GEOMETRY_INVALID',
        message: 'Marker size and inset do not fit the physical page.',
      );
    }

    final safeLeft = math.max(
      printableBounds.left.millimeters,
      markerExtent + config.minimumContentGapMm,
    );
    final safeRight = math.min(
      printableBounds.right.millimeters,
      pageWidth - markerExtent - config.minimumContentGapMm,
    );
    final safeTop = math.max(
      printableBounds.top.millimeters,
      markerExtent + config.minimumContentGapMm,
    );
    final safeBottom = math.min(
      printableBounds.bottom.millimeters,
      pageHeight - markerExtent - config.minimumContentGapMm,
    );
    final safeWidth = safeRight - safeLeft;
    final safeHeight = safeBottom - safeTop;
    final reservedTop =
        config.identityRegionHeightMm +
        config.minimumContentGapMm +
        config.headerHeightMm;
    if (safeWidth <= 0 || safeHeight <= reservedTop) {
      return EngineError(
        code: 'CONTENT_AREA_INVALID',
        message: 'Markers and reserved regions leave no usable content area.',
      );
    }
    return null;
  }

  _StaticPageGeometry _createStaticGeometry(LayoutConfig config) {
    final pageSize = config.pageSpec.size;
    final pageWidth = pageSize.width.millimeters;
    final pageHeight = pageSize.height.millimeters;
    final markerSize = config.markerSizeMm;
    final inset = config.markerInsetMm;
    final printableBounds = config.margins.contentRect(pageSize);
    final physicalPageBounds = PhysicalRect.millimeters(
      left: 0,
      top: 0,
      width: pageWidth,
      height: pageHeight,
    );

    final markerDefinitions = <(int, MarkerRole, PhysicalRect)>[
      (
        config.markerIds.topLeft,
        MarkerRole.topLeft,
        PhysicalRect.millimeters(
          left: inset,
          top: inset,
          width: markerSize,
          height: markerSize,
        ),
      ),
      (
        config.markerIds.topRight,
        MarkerRole.topRight,
        PhysicalRect.millimeters(
          left: pageWidth - inset - markerSize,
          top: inset,
          width: markerSize,
          height: markerSize,
        ),
      ),
      (
        config.markerIds.bottomLeft,
        MarkerRole.bottomLeft,
        PhysicalRect.millimeters(
          left: inset,
          top: pageHeight - inset - markerSize,
          width: markerSize,
          height: markerSize,
        ),
      ),
      (
        config.markerIds.bottomRight,
        MarkerRole.bottomRight,
        PhysicalRect.millimeters(
          left: pageWidth - inset - markerSize,
          top: pageHeight - inset - markerSize,
          width: markerSize,
          height: markerSize,
        ),
      ),
    ];

    final markerRegions = markerDefinitions
        .map((definition) {
          final bounds = definition.$3;
          final registrationPoint = switch (definition.$2) {
            MarkerRole.topLeft => PhysicalPoint(
              x: bounds.right,
              y: bounds.bottom,
            ),
            MarkerRole.topRight => PhysicalPoint(
              x: bounds.left,
              y: bounds.bottom,
            ),
            MarkerRole.bottomLeft => PhysicalPoint(
              x: bounds.right,
              y: bounds.top,
            ),
            MarkerRole.bottomRight => PhysicalPoint(
              x: bounds.left,
              y: bounds.top,
            ),
          };
          return MarkerRegion(
            markerId: definition.$1,
            role: definition.$2,
            physicalBounds: bounds,
            normalizedBounds: GeometryConverter.physicalRectToNormalized(
              bounds,
              pageSize,
            ),
            physicalRegistrationPoint: registrationPoint,
            normalizedRegistrationPoint:
                GeometryConverter.physicalPointToNormalized(
                  registrationPoint,
                  pageSize,
                ),
          );
        })
        .toList(growable: false);

    final markerExtent = inset + markerSize;
    final safeLeft = math.max(
      printableBounds.left.millimeters,
      markerExtent + config.minimumContentGapMm,
    );
    final safeRight = math.min(
      printableBounds.right.millimeters,
      pageWidth - markerExtent - config.minimumContentGapMm,
    );
    final safeTop = math.max(
      printableBounds.top.millimeters,
      markerExtent + config.minimumContentGapMm,
    );
    final safeBottom = math.min(
      printableBounds.bottom.millimeters,
      pageHeight - markerExtent - config.minimumContentGapMm,
    );
    final safeBounds = PhysicalRect.millimeters(
      left: safeLeft,
      top: safeTop,
      width: safeRight - safeLeft,
      height: safeBottom - safeTop,
    );
    final identityBounds = PhysicalRect.millimeters(
      left: safeLeft,
      top: safeTop,
      width: safeBounds.width.millimeters,
      height: config.identityRegionHeightMm,
    );
    final headerBounds = PhysicalRect.millimeters(
      left: safeLeft,
      top: identityBounds.bottom.millimeters + config.minimumContentGapMm,
      width: safeBounds.width.millimeters,
      height: config.headerHeightMm,
    );
    final contentTop = headerBounds.bottom.millimeters;

    return _StaticPageGeometry(
      physicalPageBounds: physicalPageBounds,
      normalizedPageBounds: GeometryConverter.physicalRectToNormalized(
        physicalPageBounds,
        pageSize,
      ),
      printableBounds: printableBounds,
      normalizedPrintableBounds: GeometryConverter.physicalRectToNormalized(
        printableBounds,
        pageSize,
      ),
      safeBounds: safeBounds,
      normalizedSafeBounds: GeometryConverter.physicalRectToNormalized(
        safeBounds,
        pageSize,
      ),
      markerRegions: markerRegions,
      identityRegion: TemplateIdentityRegion(
        physicalBounds: identityBounds,
        normalizedBounds: GeometryConverter.physicalRectToNormalized(
          identityBounds,
          pageSize,
        ),
      ),
      headerRegion: ContentRegion(
        physicalBounds: headerBounds,
        normalizedBounds: GeometryConverter.physicalRectToNormalized(
          headerBounds,
          pageSize,
        ),
      ),
      contentTop: contentTop,
      contentBottom: safeBounds.bottom.millimeters,
    );
  }

  EngineResult<List<_PageDraft>> _placeTemplate(
    TemplateDefinition template,
    LayoutConfig config,
    _StaticPageGeometry geometry,
  ) {
    final pages = <_PageDraft>[];
    var page = _newPage(template, pages.length, geometry);
    pages.add(page);
    final contentHeight = geometry.contentBottom - geometry.contentTop;

    for (final section in template.sections) {
      final leadPlan = _planSectionLead(section, config);
      final firstPlan = section.questions.isEmpty
          ? null
          : _planQuestion(
              section.questions.first,
              geometry.safeBounds.width.millimeters,
              config,
            );
      if (firstPlan?.isTooWide ?? false) {
        return _questionTooLarge(section.questions.first);
      }
      final sectionGap = page.hasContent ? config.sectionGapMm : 0;
      final preferredInitialHeight =
          sectionGap + leadPlan.height + (firstPlan?.height ?? 0);
      if (page.cursorY + preferredInitialHeight > geometry.contentBottom &&
          page.hasContent) {
        page = _newPage(template, pages.length, geometry);
        pages.add(page);
      }
      if (leadPlan.height > contentHeight) {
        return EngineResult.failure(
          EngineError(
            code: 'LAYOUT_OVERFLOW',
            message: 'Section content is too large for a fresh page.',
            details: {'sectionId': section.id.value},
          ),
        );
      }

      if (page.hasContent) page.cursorY += config.sectionGapMm;
      var sectionDraft = page.startSection(
        section.id,
        page.cursorY,
        leadPlacement: _placeSectionLead(
          leadPlan,
          geometry.safeBounds.left.millimeters,
          page.cursorY,
          geometry.safeBounds.width.millimeters,
        ),
      );
      page.cursorY += leadPlan.height;
      sectionDraft.endY = page.cursorY;

      for (final question in section.questions) {
        final plan = _planQuestion(
          question,
          geometry.safeBounds.width.millimeters,
          config,
        );
        if (plan.isTooWide || plan.height > contentHeight) {
          return _questionTooLarge(question);
        }

        if (page.cursorY + plan.height > geometry.contentBottom) {
          page = _newPage(template, pages.length, geometry);
          pages.add(page);
          sectionDraft = page.startSection(section.id, page.cursorY);
        }

        final questionRegion = _placeQuestion(
          question,
          plan,
          page.pageId,
          geometry.safeBounds.left.millimeters,
          page.cursorY,
          geometry.safeBounds.width.millimeters,
          config,
        );
        sectionDraft.questionRegions.add(questionRegion);
        sectionDraft.endY = questionRegion.physicalBounds.bottom.millimeters;
        page.cursorY =
            questionRegion.physicalBounds.bottom.millimeters +
            config.questionVerticalGapMm;
      }
    }

    return EngineResult.success(pages);
  }

  EngineResult<List<_PageDraft>> _questionTooLarge(TemplateQuestion question) =>
      EngineResult.failure(
        EngineError(
          code: 'QUESTION_TOO_LARGE',
          message: 'Question cannot fit within a fresh page content area.',
          details: {'questionId': question.id.value},
        ),
      );

  _PageDraft _newPage(
    TemplateDefinition template,
    int pageIndex,
    _StaticPageGeometry geometry,
  ) => _PageDraft(
    pageIndex: pageIndex,
    pageId: PageId(
      '${template.id.value}-v${template.version.value}-p${pageIndex + 1}',
    ),
    cursorY: geometry.contentTop,
  );

  _SectionLeadPlan _planSectionLead(
    TemplateSection section,
    LayoutConfig config,
  ) {
    final titleHeight = _estimateTextHeight(section.title, config);
    var cursor = titleHeight;
    double? instructionTop;
    double? instructionHeight;
    if (section.instruction != null) {
      cursor += config.minimumContentGapMm;
      instructionTop = cursor;
      instructionHeight = _estimateTextHeight(section.instruction!, config);
      cursor += instructionHeight;
    }
    double? humanReadableFieldTop;
    double? humanReadableFieldHeight;
    final textField = section.humanReadableTextField;
    if (textField != null) {
      cursor += config.minimumContentGapMm;
      humanReadableFieldTop = cursor;
      humanReadableFieldHeight = _estimateTextHeight(textField.label, config);
      if (textField.instruction != null) {
        humanReadableFieldHeight += _estimateTextHeight(
          textField.instruction!,
          config,
        );
      }
      humanReadableFieldHeight += config.humanReadableFieldHeightMm;
      cursor += humanReadableFieldHeight;
    }
    return _SectionLeadPlan(
      height: cursor + config.minimumContentGapMm,
      titleHeight: titleHeight,
      instructionTop: instructionTop,
      instructionHeight: instructionHeight,
      humanReadableFieldTop: humanReadableFieldTop,
      humanReadableFieldHeight: humanReadableFieldHeight,
    );
  }

  _SectionLeadPlacement _placeSectionLead(
    _SectionLeadPlan plan,
    double left,
    double top,
    double width,
  ) => _SectionLeadPlacement(
    titleBounds: PhysicalRect.millimeters(
      left: left,
      top: top,
      width: width,
      height: plan.titleHeight,
    ),
    instructionBounds:
        plan.instructionTop == null || plan.instructionHeight == null
        ? null
        : PhysicalRect.millimeters(
            left: left,
            top: top + plan.instructionTop!,
            width: width,
            height: plan.instructionHeight!,
          ),
    humanReadableFieldBounds:
        plan.humanReadableFieldTop == null ||
            plan.humanReadableFieldHeight == null
        ? null
        : PhysicalRect.millimeters(
            left: left,
            top: top + plan.humanReadableFieldTop!,
            width: width,
            height: plan.humanReadableFieldHeight!,
          ),
  );

  _QuestionPlan _planQuestion(
    TemplateQuestion question,
    double availableWidth,
    LayoutConfig config,
  ) {
    var promptHeight = _estimateTextHeight(question.prompt, config);
    if (question.description != null) {
      promptHeight += _estimateTextHeight(question.description!, config);
    }

    if (question.type == QuestionType.numericGrid) {
      final spec = question.numericGridSpec!;
      final gridWidth =
          spec.columnCount * config.bubbleDiameterMm +
          (spec.columnCount - 1) * config.bubbleHorizontalGapMm;
      final gridHeight =
          spec.allowedDigits.length * config.bubbleDiameterMm +
          (spec.allowedDigits.length - 1) * config.bubbleVerticalGapMm;
      return _QuestionPlan(
        height: promptHeight + config.minimumContentGapMm + gridHeight,
        promptHeight: promptHeight,
        usesHorizontalOptions: false,
        isTooWide: gridWidth > availableWidth,
      );
    }

    final optionCount = question.options.length;
    final requestedWidth =
        optionCount * config.optionCellWidthMm +
        math.max(0, optionCount - 1) * config.bubbleHorizontalGapMm;
    final horizontal = requestedWidth <= availableWidth;
    final optionHeight = horizontal
        ? config.bubbleDiameterMm
        : optionCount * config.bubbleDiameterMm +
              math.max(0, optionCount - 1) * config.bubbleVerticalGapMm;
    return _QuestionPlan(
      height: promptHeight + config.minimumContentGapMm + optionHeight,
      promptHeight: promptHeight,
      usesHorizontalOptions: horizontal,
      isTooWide: false,
    );
  }

  double _estimateTextHeight(String text, LayoutConfig config) {
    final lineCount = math.max(
      1,
      (text.length / config.estimatedCharactersPerLine).ceil(),
    );
    return lineCount * config.estimatedLineHeightMm;
  }

  QuestionRegion _placeQuestion(
    TemplateQuestion question,
    _QuestionPlan plan,
    PageId pageId,
    double left,
    double top,
    double width,
    LayoutConfig config,
  ) {
    final pageSize = config.pageSpec.size;
    final bubbleTop = top + plan.promptHeight + config.minimumContentGapMm;
    final bubbles = <BubbleRegion>[];

    if (question.type == QuestionType.numericGrid) {
      final spec = question.numericGridSpec!;
      // Column-major order: each digit row is emitted top-to-bottom before the
      // next numeric position. This mirrors vertical digit columns on paper.
      for (var column = 0; column < spec.columnCount; column++) {
        for (
          var digitIndex = 0;
          digitIndex < spec.allowedDigits.length;
          digitIndex++
        ) {
          final bounds = PhysicalRect.millimeters(
            left:
                left +
                column *
                    (config.bubbleDiameterMm + config.bubbleHorizontalGapMm),
            top:
                bubbleTop +
                digitIndex *
                    (config.bubbleDiameterMm + config.bubbleVerticalGapMm),
            width: config.bubbleDiameterMm,
            height: config.bubbleDiameterMm,
          );
          bubbles.add(
            BubbleRegion.numericCell(
              pageId: pageId,
              questionId: question.id,
              columnIndex: column,
              digitValue: spec.allowedDigits[digitIndex],
              physicalBounds: bounds,
              normalizedBounds: GeometryConverter.physicalRectToNormalized(
                bounds,
                pageSize,
              ),
              physicalCenter: bounds.center,
              normalizedCenter: GeometryConverter.physicalPointToNormalized(
                bounds.center,
                pageSize,
              ),
              physicalDiameter: PhysicalLength(config.bubbleDiameterMm),
            ),
          );
        }
      }
    } else {
      for (var index = 0; index < question.options.length; index++) {
        final bounds = PhysicalRect.millimeters(
          left: plan.usesHorizontalOptions
              ? left +
                    index *
                        (config.optionCellWidthMm +
                            config.bubbleHorizontalGapMm)
              : left,
          top: plan.usesHorizontalOptions
              ? bubbleTop
              : bubbleTop +
                    index *
                        (config.bubbleDiameterMm + config.bubbleVerticalGapMm),
          width: config.bubbleDiameterMm,
          height: config.bubbleDiameterMm,
        );
        bubbles.add(
          BubbleRegion.option(
            pageId: pageId,
            questionId: question.id,
            optionId: question.options[index].id,
            physicalBounds: bounds,
            normalizedBounds: GeometryConverter.physicalRectToNormalized(
              bounds,
              pageSize,
            ),
            physicalCenter: bounds.center,
            normalizedCenter: GeometryConverter.physicalPointToNormalized(
              bounds.center,
              pageSize,
            ),
            physicalDiameter: PhysicalLength(config.bubbleDiameterMm),
          ),
        );
      }
    }

    final bounds = PhysicalRect.millimeters(
      left: left,
      top: top,
      width: width,
      height: plan.height,
    );
    return QuestionRegion(
      questionId: question.id,
      questionType: question.type,
      physicalBounds: bounds,
      normalizedBounds: GeometryConverter.physicalRectToNormalized(
        bounds,
        pageSize,
      ),
      bubbleRegions: bubbles,
    );
  }

  PageLayout _materializePage(
    TemplateDefinition template,
    LayoutConfig config,
    _StaticPageGeometry geometry,
    _PageDraft draft,
    int totalPageCount,
  ) {
    final sections = draft.sections
        .map((section) {
          final bounds = PhysicalRect.millimeters(
            left: geometry.safeBounds.left.millimeters,
            top: section.startY,
            width: geometry.safeBounds.width.millimeters,
            height: section.endY - section.startY,
          );
          return SectionRegion(
            sectionId: section.sectionId,
            physicalBounds: bounds,
            normalizedBounds: GeometryConverter.physicalRectToNormalized(
              bounds,
              config.pageSpec.size,
            ),
            titleRegion: _materializeContentRegion(
              section.leadPlacement?.titleBounds,
              config,
            ),
            instructionRegion: _materializeContentRegion(
              section.leadPlacement?.instructionBounds,
              config,
            ),
            humanReadableFieldRegion: _materializeContentRegion(
              section.leadPlacement?.humanReadableFieldBounds,
              config,
            ),
            questionRegions: section.questionRegions,
          );
        })
        .toList(growable: false);
    final questions = sections
        .expand((section) => section.questionRegions)
        .toList(growable: false);
    final bubbles = questions
        .expand((question) => question.bubbleRegions)
        .toList(growable: false);

    return PageLayout(
      templateId: template.id,
      templateVersion: template.version,
      pageId: draft.pageId,
      pageIndex: draft.pageIndex,
      totalPageCount: totalPageCount,
      pageSpec: config.pageSpec,
      canonicalPageSpec: config.canonicalPageSpec,
      physicalPageBounds: geometry.physicalPageBounds,
      normalizedPageBounds: geometry.normalizedPageBounds,
      printableBounds: geometry.printableBounds,
      normalizedPrintableBounds: geometry.normalizedPrintableBounds,
      safeBounds: geometry.safeBounds,
      normalizedSafeBounds: geometry.normalizedSafeBounds,
      markerRegions: geometry.markerRegions,
      templateIdentityRegion: geometry.identityRegion,
      headerRegion: geometry.headerRegion,
      sectionRegions: sections,
      questionRegions: questions,
      bubbleRegions: bubbles,
    );
  }

  ContentRegion? _materializeContentRegion(
    PhysicalRect? bounds,
    LayoutConfig config,
  ) => bounds == null
      ? null
      : ContentRegion(
          physicalBounds: bounds,
          normalizedBounds: GeometryConverter.physicalRectToNormalized(
            bounds,
            config.pageSpec.size,
          ),
        );

  EngineError? _validateGeneratedGeometry(List<PageLayout> pages) {
    for (final page in pages) {
      if (page.markerRegions.any(
        (marker) => page.templateIdentityRegion.physicalBounds.intersects(
          marker.physicalBounds,
        ),
      )) {
        return EngineError(
          code: 'GEOMETRY_INVALID',
          message: 'Template identity region intersects a marker region.',
        );
      }
      if (!page.safeBounds.containsRect(page.headerRegion.physicalBounds) ||
          page.templateIdentityRegion.physicalBounds.intersects(
            page.headerRegion.physicalBounds,
          )) {
        return EngineError(
          code: 'GEOMETRY_INVALID',
          message: 'Header region is outside safe bounds or overlaps identity.',
        );
      }

      for (final section in page.sectionRegions) {
        final leadRegions = [
          section.titleRegion,
          section.instructionRegion,
          section.humanReadableFieldRegion,
        ].whereType<ContentRegion>();
        for (final region in leadRegions) {
          if (!section.physicalBounds.containsRect(region.physicalBounds) ||
              page.bubbleRegions.any(
                (bubble) =>
                    region.physicalBounds.intersects(bubble.physicalBounds),
              )) {
            return EngineError(
              code: 'GEOMETRY_INVALID',
              message: 'Section lead geometry is invalid.',
            );
          }
        }
      }

      for (var index = 0; index < page.bubbleRegions.length; index++) {
        final bubble = page.bubbleRegions[index];
        if (!page.safeBounds.containsRect(bubble.physicalBounds)) {
          return EngineError(
            code: 'GEOMETRY_INVALID',
            message: 'Bubble lies outside the safe content area.',
          );
        }
        if (page.markerRegions.any(
          (marker) => marker.physicalBounds.intersects(bubble.physicalBounds),
        )) {
          return EngineError(
            code: 'GEOMETRY_INVALID',
            message: 'Bubble intersects a marker region.',
          );
        }
        for (
          var otherIndex = index + 1;
          otherIndex < page.bubbleRegions.length;
          otherIndex++
        ) {
          if (bubble.physicalBounds.intersects(
            page.bubbleRegions[otherIndex].physicalBounds,
          )) {
            return EngineError(
              code: 'GEOMETRY_INVALID',
              message: 'Generated bubble regions overlap.',
            );
          }
        }
      }

      for (final question in page.questionRegions) {
        if (question.bubbleRegions.any(
          (bubble) =>
              !question.physicalBounds.containsRect(bubble.physicalBounds),
        )) {
          return EngineError(
            code: 'GEOMETRY_INVALID',
            message: 'Question bounds do not contain all of their bubbles.',
          );
        }
      }
    }
    return null;
  }
}

final class _QuestionPlan {
  const _QuestionPlan({
    required this.height,
    required this.promptHeight,
    required this.usesHorizontalOptions,
    required this.isTooWide,
  });

  final double height;
  final double promptHeight;
  final bool usesHorizontalOptions;
  final bool isTooWide;
}

final class _SectionLeadPlan {
  const _SectionLeadPlan({
    required this.height,
    required this.titleHeight,
    required this.instructionTop,
    required this.instructionHeight,
    required this.humanReadableFieldTop,
    required this.humanReadableFieldHeight,
  });

  final double height;
  final double titleHeight;
  final double? instructionTop;
  final double? instructionHeight;
  final double? humanReadableFieldTop;
  final double? humanReadableFieldHeight;
}

final class _SectionLeadPlacement {
  const _SectionLeadPlacement({
    required this.titleBounds,
    required this.instructionBounds,
    required this.humanReadableFieldBounds,
  });

  final PhysicalRect titleBounds;
  final PhysicalRect? instructionBounds;
  final PhysicalRect? humanReadableFieldBounds;
}

final class _StaticPageGeometry {
  const _StaticPageGeometry({
    required this.physicalPageBounds,
    required this.normalizedPageBounds,
    required this.printableBounds,
    required this.normalizedPrintableBounds,
    required this.safeBounds,
    required this.normalizedSafeBounds,
    required this.markerRegions,
    required this.identityRegion,
    required this.headerRegion,
    required this.contentTop,
    required this.contentBottom,
  });

  final PhysicalRect physicalPageBounds;
  final NormalizedRect normalizedPageBounds;
  final PhysicalRect printableBounds;
  final NormalizedRect normalizedPrintableBounds;
  final PhysicalRect safeBounds;
  final NormalizedRect normalizedSafeBounds;
  final List<MarkerRegion> markerRegions;
  final TemplateIdentityRegion identityRegion;
  final ContentRegion headerRegion;
  final double contentTop;
  final double contentBottom;
}

final class _PageDraft {
  _PageDraft({
    required this.pageIndex,
    required this.pageId,
    required this.cursorY,
  });

  final int pageIndex;
  final PageId pageId;
  double cursorY;
  final List<_SectionDraft> sections = [];

  bool get hasContent => sections.isNotEmpty;

  _SectionDraft startSection(
    SectionId sectionId,
    double startY, {
    _SectionLeadPlacement? leadPlacement,
  }) {
    final section = _SectionDraft(
      sectionId: sectionId,
      startY: startY,
      endY: startY,
      leadPlacement: leadPlacement,
    );
    sections.add(section);
    return section;
  }
}

final class _SectionDraft {
  _SectionDraft({
    required this.sectionId,
    required this.startY,
    required this.endY,
    required this.leadPlacement,
  });

  final SectionId sectionId;
  final double startY;
  double endY;
  final _SectionLeadPlacement? leadPlacement;
  final List<QuestionRegion> questionRegions = [];
}
