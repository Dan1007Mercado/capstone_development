import 'package:capstone_development/application/real_scanner/published_scanner_resolver.dart';
import 'package:capstone_development/application/real_scanner/scanner_validation_session.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/debug/real_scanner_validation_screen.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/layout/application/layout_engine.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessed_page.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification.dart';
import 'package:capstone_development/engines/scanner/domain/scan_result.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/domain/template_option.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:capstone_development/engines/template/domain/template_section.dart';
import 'package:capstone_development/engines/template/domain/template_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('result UI shows Q1-Q8 in authoritative numeric order', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final template = _template();
    final layout = LayoutEngine()
        .build(template, LayoutConfig.a4AnswerSheet())
        .value;
    final page = layout.pages.single;
    final classifications = [
      for (final region in page.questionRegions.reversed)
        QuestionClassification(
          questionId: region.questionId,
          questionNumber: region.questionNumber,
          questionType: region.questionType,
          state: MarkState.blank,
          selectedOptionIds: const [],
          numericSelection: null,
          bubbleDecisions: const [],
          diagnostics: const QuestionClassificationDiagnostics(
            topScore: 0,
            secondScore: 0,
            scoreGap: 0,
            reason: ClassificationReason.clearBlank,
          ),
        ),
    ];
    final result = ScanResult(
      templateId: template.id,
      templateVersion: template.version,
      pageId: page.pageId,
      questions: classifications,
      pageState: ScanPageState.accepted,
      reviewReasons: const [],
      reviewQuestionIds: const [],
      diagnostics: _diagnostics(classifications.length),
    );
    final session = ScannerValidationSession.start(
      artifact: PublishedScannerArtifact(template: template, layout: layout),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ScannerPageResultScreen(
          session: session,
          result: result,
          onContinue: () {},
        ),
      ),
    );

    final positions = <double>[];
    for (var number = 1; number <= 8; number++) {
      final row = find.byKey(Key('scanner-result-question-$number'));
      expect(row, findsOneWidget);
      expect(find.text('Q$number  Question $number'), findsOneWidget);
      positions.add(tester.getTopLeft(row).dy);
    }
    expect(positions, orderedEquals([...positions]..sort()));
    expect(find.byKey(const Key('scanner-result-question-7')), findsOneWidget);
    expect(find.byKey(const Key('scanner-result-question-8')), findsOneWidget);
  });
}

TemplateDefinition _template() => TemplateDefinition(
  id: TemplateId('p14-3-ui-mapping'),
  version: TemplateVersion(1),
  name: 'P14.3 UI mapping',
  status: TemplateStatus.draft,
  sections: [
    TemplateSection(
      id: SectionId('responses'),
      title: 'RESPONSES',
      questions: [
        for (var number = 1; number <= 7; number++)
          _question(number, QuestionType.singleChoice),
        _question(8, QuestionType.multipleChoice),
      ],
    ),
  ],
);

TemplateQuestion _question(int number, QuestionType type) => TemplateQuestion(
  id: QuestionId('q$number'),
  type: type,
  prompt: 'Question $number',
  options: [
    TemplateOption(id: OptionId('q$number-a'), label: 'A'),
    TemplateOption(id: OptionId('q$number-b'), label: 'B'),
  ],
);

ScanDiagnostics _diagnostics(int totalQuestions) => ScanDiagnostics(
  totalProcessingDuration: Duration.zero,
  stageDurations: const ScanStageDurations(
    alignment: Duration.zero,
    preprocessing: Duration.zero,
    measurement: Duration.zero,
    classification: Duration.zero,
  ),
  alignment: PageAlignmentDiagnostics(
    expectedMarkerIds: const [],
    detectedMarkerIds: const [],
    sourceMarkerSideLengths: const [],
    sourceRegistrationPoints: const [],
    destinationRegistrationPoints: const [],
    registrationQuality: const RegistrationQuality(
      quadrilateralAreaRatio: 1,
      minimumMarkerSidePixels: 10,
      maximumPerspectiveRatio: 1,
    ),
    reprojectionErrors: const [],
    meanReprojectionError: 0,
    maxReprojectionError: 0,
    processingDuration: Duration.zero,
  ),
  preprocessing: const PreprocessingDiagnostics(
    sourceStatistics: _statistics,
    normalizedStatistics: _statistics,
    binaryForegroundRatio: 0,
    processingDuration: Duration.zero,
  ),
  summary: ScanSummary(
    totalQuestions: totalQuestions,
    marked: 0,
    blank: totalQuestions,
    multiple: 0,
    ambiguous: 0,
    invalid: 0,
    requiredBlank: 0,
    measuredBubbles: 0,
  ),
);

const _statistics = ImageStatistics(
  meanIntensity: 200,
  intensityStandardDeviation: 20,
  minimumIntensity: 0,
  maximumIntensity: 255,
  darkPixelRatio: 0,
  brightPixelRatio: 0,
);
