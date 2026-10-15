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
import '../domain/page_marker_id_allocator.dart';

/// Deterministic bridge from validated template semantics to page geometry.
final class LayoutEngine {
  LayoutEngine({
    TemplateValidator? templateValidator,
    this.pageMarkerIdAllocator = const PageMarkerIdAllocator(),
  }) : _templateValidator = templateValidator ?? TemplateValidator();

  final TemplateValidator _templateValidator;
  final PageMarkerIdAllocator pageMarkerIdAllocator;

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
      final pages = <PageLayout>[];
      final allocatedIds = <int>{};
      for (final draft in drafts) {
        final allocation = pageMarkerIdAllocator.allocate(
          config.markerIds,
          draft.pageIndex,
        );
        if (allocation.isFailure) return EngineResult.failure(allocation.error);
        if (allocation.value.values.any((id) => !allocatedIds.add(id))) {
          return EngineResult.failure(
            EngineError(
              code: 'ARUCO_PAGE_ID_CAPACITY_EXCEEDED',
              message: 'Page marker signatures must not collide.',
            ),
          );
        }
        pages.add(
          _materializePage(
            template,
            config,
            geometry,
            draft,
            totalPageCount,
            allocation.value,
          ),
        );
      }

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
      'estimatedTextWidthMm': config.estimatedTextWidthMm,
      'humanReadableFieldHeightMm': config.humanReadableFieldHeightMm,
      'columnGapMm': config.columnGapMm,
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
    if (config.columnCount <= 0 || config.maximumColumnPromptLines <= 0) {
      return EngineError(
        code: 'LAYOUT_CONFIG_INVALID',
        message: 'Column count and prompt-line limit must be positive.',
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
    final totalColumnGaps = (config.columnCount - 1) * config.columnGapMm;
    if (safeWidth <= totalColumnGaps) {
      return EngineError(
        code: 'CONTENT_AREA_INVALID',
        message: 'Column gaps leave no usable content width.',
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
          final markerBounds = ArucoMarkerPrintContract.detectableMarkerBounds(
            bounds,
          );
          final registrationPoint =
              ArucoMarkerPrintContract.pageFacingRegistrationPoint(
                definition.$2,
                markerBounds,
              );
          return MarkerRegion(
            markerId: definition.$1,
            role: definition.$2,
            physicalBounds: bounds,
            normalizedBounds: GeometryConverter.physicalRectToNormalized(
              bounds,
              pageSize,
            ),
            physicalMarkerBounds: markerBounds,
            normalizedMarkerBounds: GeometryConverter.physicalRectToNormalized(
              markerBounds,
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
    final columnWidth =
        (safeBounds.width.millimeters -
            (config.columnCount - 1) * config.columnGapMm) /
        config.columnCount;
    final contentColumnRegions = [
      for (var index = 0; index < config.columnCount; index++)
        LayoutColumnRegion(
          columnIndex: index,
          physicalBounds: PhysicalRect.millimeters(
            left: safeLeft + index * (columnWidth + config.columnGapMm),
            top: contentTop,
            width: columnWidth,
            height: safeBounds.bottom.millimeters - contentTop,
          ),
          normalizedBounds: GeometryConverter.physicalRectToNormalized(
            PhysicalRect.millimeters(
              left: safeLeft + index * (columnWidth + config.columnGapMm),
              top: contentTop,
              width: columnWidth,
              height: safeBounds.bottom.millimeters - contentTop,
            ),
            pageSize,
          ),
        ),
    ];

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
      contentColumnRegions: contentColumnRegions,
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
      var sectionStarted = false;
      _SectionDraft? sectionDraft;

      if (section.questions.isEmpty) {
        if (page.fullWidthLocked) {
          page = _appendPage(template, pages, geometry);
        }
        final column = page.activeColumn;
        final leadPlan = _planSectionLead(
          section,
          column.physicalBounds.width.millimeters,
          config,
        );
        if (leadPlan.height > contentHeight) {
          return _sectionTooLarge(section);
        }
        final gap = page.activeColumnHasContent ? config.sectionGapMm : 0;
        if (page.cursorY + gap + leadPlan.height > geometry.contentBottom &&
            page.activeColumnHasContent) {
          page = _advanceFlow(template, pages, geometry, page);
        }
        if (page.activeColumnHasContent) {
          page.cursorY += config.sectionGapMm;
        }
        final target = page.activeColumn;
        sectionDraft = page.startSection(
          section.id,
          page.cursorY,
          left: target.physicalBounds.left.millimeters,
          width: target.physicalBounds.width.millimeters,
          columnIndex: target.columnIndex,
          leadPlacement: _placeSectionLead(
            leadPlan,
            target.physicalBounds.left.millimeters,
            page.cursorY,
            target.physicalBounds.width.millimeters,
          ),
        );
        page.cursorY += leadPlan.height;
        sectionDraft.endY = page.cursorY;
        continue;
      }

      for (final question in section.questions) {
        if (page.fullWidthLocked) {
          page = _appendPage(template, pages, geometry);
          sectionDraft = null;
        }

        var column = page.activeColumn;
        var columnPlan = _planQuestion(
          question,
          column.physicalBounds.width.millimeters,
          config,
        );
        final columnSuitable =
            !columnPlan.isTooWide &&
            columnPlan.promptLineCount <= config.maximumColumnPromptLines &&
            (question.type == QuestionType.numericGrid ||
                columnPlan.usesHorizontalOptions);

        if (!columnSuitable && config.columnCount > 1) {
          final fullPlan = _planQuestion(
            question,
            geometry.safeBounds.width.millimeters,
            config,
          );
          final leadPlan = sectionStarted
              ? null
              : _planSectionLead(
                  section,
                  geometry.safeBounds.width.millimeters,
                  config,
                );
          final requiredHeight = (leadPlan?.height ?? 0) + fullPlan.height;
          if (fullPlan.isTooWide || requiredHeight > contentHeight) {
            return _questionTooLarge(question);
          }
          if (page.hasContent) {
            page = _appendPage(template, pages, geometry);
          }
          sectionDraft = page.startSection(
            section.id,
            page.cursorY,
            left: geometry.safeBounds.left.millimeters,
            width: geometry.safeBounds.width.millimeters,
            columnIndex: null,
            leadPlacement: leadPlan == null
                ? null
                : _placeSectionLead(
                    leadPlan,
                    geometry.safeBounds.left.millimeters,
                    page.cursorY,
                    geometry.safeBounds.width.millimeters,
                  ),
          );
          if (leadPlan != null) page.cursorY += leadPlan.height;
          final questionRegion = _placeQuestion(
            question,
            fullPlan,
            page.pageId,
            geometry.safeBounds.left.millimeters,
            page.cursorY,
            geometry.safeBounds.width.millimeters,
            null,
            config,
          );
          sectionDraft.questionRegions.add(questionRegion);
          sectionDraft.endY = questionRegion.physicalBounds.bottom.millimeters;
          page.cursorY =
              questionRegion.physicalBounds.bottom.millimeters +
              config.questionVerticalGapMm;
          page.fullWidthLocked = true;
          sectionStarted = true;
          continue;
        }

        if (columnPlan.isTooWide || columnPlan.height > contentHeight) {
          return _questionTooLarge(question);
        }

        if (!sectionStarted) {
          var leadPlan = _planSectionLead(
            section,
            column.physicalBounds.width.millimeters,
            config,
          );
          if (leadPlan.height > contentHeight) {
            return _sectionTooLarge(section);
          }
          var gap = page.activeColumnHasContent ? config.sectionGapMm : 0;
          if (page.cursorY + gap + leadPlan.height + columnPlan.height >
                  geometry.contentBottom &&
              page.activeColumnHasContent) {
            page = _advanceFlow(template, pages, geometry, page);
            column = page.activeColumn;
            columnPlan = _planQuestion(
              question,
              column.physicalBounds.width.millimeters,
              config,
            );
            leadPlan = _planSectionLead(
              section,
              column.physicalBounds.width.millimeters,
              config,
            );
            gap = 0;
          }
          page.cursorY += gap;
          sectionDraft = page.startSection(
            section.id,
            page.cursorY,
            left: column.physicalBounds.left.millimeters,
            width: column.physicalBounds.width.millimeters,
            columnIndex: column.columnIndex,
            leadPlacement: _placeSectionLead(
              leadPlan,
              column.physicalBounds.left.millimeters,
              page.cursorY,
              column.physicalBounds.width.millimeters,
            ),
          );
          page.cursorY += leadPlan.height;
          sectionDraft.endY = page.cursorY;
          sectionStarted = true;
        }

        if (page.cursorY + columnPlan.height > geometry.contentBottom) {
          page = _advanceFlow(template, pages, geometry, page);
          column = page.activeColumn;
          columnPlan = _planQuestion(
            question,
            column.physicalBounds.width.millimeters,
            config,
          );
          sectionDraft = page.startSection(
            section.id,
            page.cursorY,
            left: column.physicalBounds.left.millimeters,
            width: column.physicalBounds.width.millimeters,
            columnIndex: column.columnIndex,
          );
        }

        sectionDraft ??= page.startSection(
          section.id,
          page.cursorY,
          left: column.physicalBounds.left.millimeters,
          width: column.physicalBounds.width.millimeters,
          columnIndex: column.columnIndex,
        );

        final questionRegion = _placeQuestion(
          question,
          columnPlan,
          page.pageId,
          column.physicalBounds.left.millimeters,
          page.cursorY,
          column.physicalBounds.width.millimeters,
          column.columnIndex,
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

  EngineResult<List<_PageDraft>> _sectionTooLarge(TemplateSection section) =>
      EngineResult.failure(
        EngineError(
          code: 'LAYOUT_OVERFLOW',
          message: 'Section content is too large for a fresh page.',
          details: {'sectionId': section.id.value},
        ),
      );

  _PageDraft _appendPage(
    TemplateDefinition template,
    List<_PageDraft> pages,
    _StaticPageGeometry geometry,
  ) {
    final page = _newPage(template, pages.length, geometry);
    pages.add(page);
    return page;
  }

  _PageDraft _advanceFlow(
    TemplateDefinition template,
    List<_PageDraft> pages,
    _StaticPageGeometry geometry,
    _PageDraft page,
  ) {
    if (page.advanceColumn()) return page;
    return _appendPage(template, pages, geometry);
  }

  _PageDraft _newPage(
    TemplateDefinition template,
    int pageIndex,
    _StaticPageGeometry geometry,
  ) => _PageDraft(
    pageIndex: pageIndex,
    pageId: PageId(
      '${template.id.value}-v${template.version.value}-p${pageIndex + 1}',
    ),
    contentTop: geometry.contentTop,
    columns: geometry.contentColumnRegions,
  );

  _SectionLeadPlan _planSectionLead(
    TemplateSection section,
    double availableWidth,
    LayoutConfig config,
  ) {
    final titleHeight = _estimateTextHeight(
      section.title,
      availableWidth,
      config,
    );
    var cursor = titleHeight;
    double? instructionTop;
    double? instructionHeight;
    if (section.instruction != null) {
      cursor += config.minimumContentGapMm;
      instructionTop = cursor;
      instructionHeight = _estimateTextHeight(
        section.instruction!,
        availableWidth,
        config,
      );
      cursor += instructionHeight;
    }
    double? humanReadableFieldTop;
    double? humanReadableFieldHeight;
    final textField = section.humanReadableTextField;
    if (textField != null) {
      cursor += config.minimumContentGapMm;
      humanReadableFieldTop = cursor;
      humanReadableFieldHeight = _estimateTextHeight(
        textField.label,
        availableWidth,
        config,
      );
      if (textField.instruction != null) {
        humanReadableFieldHeight += _estimateTextHeight(
          textField.instruction!,
          availableWidth,
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
    var promptLineCount = _estimateLineCount(
      question.prompt,
      availableWidth,
      config,
    );
    if (question.description != null) {
      promptLineCount += _estimateLineCount(
        question.description!,
        availableWidth,
        config,
      );
    }
    final promptHeight = promptLineCount * config.estimatedLineHeightMm;

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
        promptLineCount: promptLineCount,
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
      promptLineCount: promptLineCount,
      usesHorizontalOptions: horizontal,
      isTooWide: false,
    );
  }

  int _estimateLineCount(
    String text,
    double availableWidth,
    LayoutConfig config,
  ) {
    final charactersPerLine = math.max(
      1,
      (config.estimatedCharactersPerLine *
              availableWidth /
              config.estimatedTextWidthMm)
          .floor(),
    );
    return math.max(1, (text.length / charactersPerLine).ceil());
  }

  double _estimateTextHeight(
    String text,
    double availableWidth,
    LayoutConfig config,
  ) {
    final lineCount = math.max(
      1,
      _estimateLineCount(text, availableWidth, config),
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
    int? columnIndex,
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
      columnIndex: columnIndex,
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
    MarkerIds markerIds,
  ) {
    final sections = draft.sections
        .map((section) {
          final bounds = PhysicalRect.millimeters(
            left: section.left,
            top: section.startY,
            width: section.width,
            height: section.endY - section.startY,
          );
          return SectionRegion(
            sectionId: section.sectionId,
            columnIndex: section.columnIndex,
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
      markerRegions: [
        for (final marker in geometry.markerRegions)
          MarkerRegion(
            markerId: switch (marker.role) {
              MarkerRole.topLeft => markerIds.topLeft,
              MarkerRole.topRight => markerIds.topRight,
              MarkerRole.bottomLeft => markerIds.bottomLeft,
              MarkerRole.bottomRight => markerIds.bottomRight,
            },
            role: marker.role,
            physicalBounds: marker.physicalBounds,
            normalizedBounds: marker.normalizedBounds,
            physicalMarkerBounds: marker.physicalMarkerBounds,
            normalizedMarkerBounds: marker.normalizedMarkerBounds,
            physicalRegistrationPoint: marker.physicalRegistrationPoint,
            normalizedRegistrationPoint: marker.normalizedRegistrationPoint,
          ),
      ],
      templateIdentityRegion: geometry.identityRegion,
      headerRegion: geometry.headerRegion,
      contentColumnRegions: geometry.contentColumnRegions,
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
      for (final marker in page.markerRegions) {
        final expectedMarkerBounds =
            ArucoMarkerPrintContract.detectableMarkerBounds(
              marker.physicalBounds,
            );
        final expectedRegistrationPoint =
            ArucoMarkerPrintContract.pageFacingRegistrationPoint(
              marker.role,
              marker.physicalMarkerBounds,
            );
        if (!marker.physicalBounds.containsRect(marker.physicalMarkerBounds) ||
            marker.physicalMarkerBounds != expectedMarkerBounds ||
            marker.physicalRegistrationPoint != expectedRegistrationPoint) {
          return EngineError(
            code: 'GEOMETRY_INVALID',
            message: 'Marker print and detection geometry are inconsistent.',
          );
        }
      }
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

      for (var index = 0; index < page.contentColumnRegions.length; index++) {
        final column = page.contentColumnRegions[index];
        if (column.columnIndex != index ||
            !page.safeBounds.containsRect(column.physicalBounds) ||
            page.markerRegions.any(
              (marker) =>
                  column.physicalBounds.intersects(marker.physicalBounds),
            )) {
          return EngineError(
            code: 'GEOMETRY_INVALID',
            message: 'Content column geometry is invalid.',
          );
        }
        for (
          var otherIndex = index + 1;
          otherIndex < page.contentColumnRegions.length;
          otherIndex++
        ) {
          if (column.physicalBounds.intersects(
            page.contentColumnRegions[otherIndex].physicalBounds,
          )) {
            return EngineError(
              code: 'GEOMETRY_INVALID',
              message: 'Content columns overlap.',
            );
          }
        }
      }

      for (
        var sectionIndex = 0;
        sectionIndex < page.sectionRegions.length;
        sectionIndex++
      ) {
        final section = page.sectionRegions[sectionIndex];
        if (!page.safeBounds.containsRect(section.physicalBounds) ||
            !_matchesColumnAssignment(
              section.physicalBounds,
              section.columnIndex,
              page,
            )) {
          return EngineError(
            code: 'GEOMETRY_INVALID',
            message: 'Section fragment is outside its assigned flow area.',
          );
        }
        for (
          var otherIndex = sectionIndex + 1;
          otherIndex < page.sectionRegions.length;
          otherIndex++
        ) {
          if (section.physicalBounds.intersects(
            page.sectionRegions[otherIndex].physicalBounds,
          )) {
            return EngineError(
              code: 'GEOMETRY_INVALID',
              message: 'Generated section fragments overlap.',
            );
          }
        }
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
              ) ||
              page.questionRegions.any(
                (question) =>
                    region.physicalBounds.intersects(question.physicalBounds),
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

      for (
        var questionIndex = 0;
        questionIndex < page.questionRegions.length;
        questionIndex++
      ) {
        final question = page.questionRegions[questionIndex];
        if (!page.safeBounds.containsRect(question.physicalBounds) ||
            !_matchesColumnAssignment(
              question.physicalBounds,
              question.columnIndex,
              page,
            ) ||
            page.markerRegions.any(
              (marker) =>
                  question.physicalBounds.intersects(marker.physicalBounds),
            ) ||
            question.bubbleRegions.any(
              (bubble) =>
                  !question.physicalBounds.containsRect(bubble.physicalBounds),
            )) {
          return EngineError(
            code: 'GEOMETRY_INVALID',
            message: 'Question geometry is outside its assigned flow area.',
          );
        }
        for (
          var otherIndex = questionIndex + 1;
          otherIndex < page.questionRegions.length;
          otherIndex++
        ) {
          if (question.physicalBounds.intersects(
            page.questionRegions[otherIndex].physicalBounds,
          )) {
            return EngineError(
              code: 'GEOMETRY_INVALID',
              message: 'Generated question regions overlap.',
            );
          }
        }
      }
    }
    return null;
  }

  bool _matchesColumnAssignment(
    PhysicalRect bounds,
    int? columnIndex,
    PageLayout page,
  ) {
    if (columnIndex == null) {
      return bounds.left == page.safeBounds.left &&
          bounds.right == page.safeBounds.right;
    }
    if (columnIndex < 0 || columnIndex >= page.contentColumnRegions.length) {
      return false;
    }
    return page.contentColumnRegions[columnIndex].physicalBounds.containsRect(
      bounds,
    );
  }
}

final class _QuestionPlan {
  const _QuestionPlan({
    required this.height,
    required this.promptHeight,
    required this.promptLineCount,
    required this.usesHorizontalOptions,
    required this.isTooWide,
  });

  final double height;
  final double promptHeight;
  final int promptLineCount;
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
    required this.contentColumnRegions,
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
  final List<LayoutColumnRegion> contentColumnRegions;
  final double contentTop;
  final double contentBottom;
}

final class _PageDraft {
  _PageDraft({
    required this.pageIndex,
    required this.pageId,
    required double contentTop,
    required this.columns,
  }) : _columnCursors = List.filled(columns.length, contentTop);

  final int pageIndex;
  final PageId pageId;
  final List<LayoutColumnRegion> columns;
  final List<double> _columnCursors;
  var activeColumnIndex = 0;
  bool fullWidthLocked = false;
  final List<_SectionDraft> sections = [];

  bool get hasContent => sections.isNotEmpty;
  LayoutColumnRegion get activeColumn => columns[activeColumnIndex];
  double get cursorY => _columnCursors[activeColumnIndex];
  set cursorY(double value) => _columnCursors[activeColumnIndex] = value;
  bool get activeColumnHasContent =>
      sections.any((section) => section.columnIndex == activeColumnIndex);

  bool advanceColumn() {
    if (activeColumnIndex + 1 >= columns.length) return false;
    activeColumnIndex++;
    return true;
  }

  _SectionDraft startSection(
    SectionId sectionId,
    double startY, {
    required double left,
    required double width,
    required int? columnIndex,
    _SectionLeadPlacement? leadPlacement,
  }) {
    final section = _SectionDraft(
      sectionId: sectionId,
      startY: startY,
      endY: startY,
      left: left,
      width: width,
      columnIndex: columnIndex,
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
    required this.left,
    required this.width,
    required this.columnIndex,
    required this.leadPlacement,
  });

  final SectionId sectionId;
  final double startY;
  double endY;
  final double left;
  final double width;
  final int? columnIndex;
  final _SectionLeadPlacement? leadPlacement;
  final List<QuestionRegion> questionRegions = [];
}
