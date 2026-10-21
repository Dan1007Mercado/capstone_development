import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/layout/domain/layout_regions.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/recognition/application/mark_classification_engine.dart';
import 'package:capstone_development/engines/recognition/domain/bubble_measurement.dart';
import 'package:capstone_development/engines/recognition/domain/canonical_bubble_roi.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification_config.dart';
import 'package:capstone_development/engines/template/domain/numeric_grid_spec.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:capstone_development/engines/template/domain/template_definition.dart';
import 'package:capstone_development/engines/template/domain/template_option.dart';
import 'package:capstone_development/engines/template/domain/template_question.dart';
import 'package:flutter_test/flutter_test.dart';

import '../layout/layout_test_fixtures.dart';

void main() {
  const engine = MarkClassificationEngine();

  group('exclusive option questions', () {
    test('clear blank single-choice returns BLANK', () {
      final scenario = _singleChoice();
      expect(_classify(engine, scenario).state, MarkState.blank);
    });

    test('one weak print-noise signal remains BLANK', () {
      final scenario = _singleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.first
            ? _Evidence.weakOutlineNoise
            : _Evidence.blank,
      );

      expect(result.state, MarkState.blank);
      expect(
        result.bubbleDecisions.first.category,
        BubbleEvidenceCategory.clearBlank,
      );
    });

    test('one strong mark returns MARKED with its OptionId', () {
      final scenario = _singleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions[1]
            ? _Evidence.strong
            : _Evidence.blank,
      );

      expect(result.state, MarkState.marked);
      expect(result.selectedOptionIds, [
        scenario.page.bubbleRegions[1].optionId,
      ]);
    });

    test('two clear single-choice marks return MULTIPLE', () {
      final scenario = _singleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => scenario.page.bubbleRegions.indexOf(bubble) < 2
            ? _Evidence.strong
            : _Evidence.blank,
      );

      expect(result.state, MarkState.multiple);
      expect(result.selectedOptionIds, hasLength(2));
    });

    test('close top-two possible candidates return AMBIGUOUS', () {
      final scenario = _singleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) =>
            switch (scenario.page.bubbleRegions.indexOf(bubble)) {
              0 => _Evidence.possibleTop,
              1 => _Evidence.possibleClose,
              _ => _Evidence.blank,
            },
      );

      expect(result.state, MarkState.ambiguous);
      expect(result.diagnostics.reason, ClassificationReason.closeCandidates);
    });

    test('one possible but clearly dominant candidate returns MARKED', () {
      final scenario = _singleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.first
            ? _Evidence.possibleTop
            : _Evidence.blank,
      );

      expect(result.state, MarkState.marked);
      expect(
        result.bubbleDecisions.first.category,
        BubbleEvidenceCategory.possibleMark,
      );
      expect(result.selectedOptionIds, [
        scenario.page.bubbleRegions.first.optionId,
      ]);
      expect(
        result.diagnostics.scoreGap,
        greaterThanOrEqualTo(
          const MarkClassificationConfig().minimumTopSecondGap,
        ),
      );
    });

    test('faint but isolated multi-signal mark can return MARKED', () {
      final scenario = _singleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.first
            ? _Evidence.faintPencil
            : _Evidence.blank,
      );

      expect(result.state, MarkState.marked);
      expect(result.bubbleDecisions.first.fillRatio, lessThan(0.12));
      expect(
        result.bubbleDecisions.first.normalizedDarkness,
        greaterThanOrEqualTo(0.30),
      );
    });

    test('tiny random darkness differences remain BLANK (argmax trap)', () {
      final scenario = _singleChoice(optionCount: 4);
      const noise = [0.08, 0.10, 0.07, 0.09];
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) {
          final value = noise[scenario.page.bubbleRegions.indexOf(bubble)];
          return _Evidence(fill: value, normalized: 0.02, contrast: 4);
        },
      );

      expect(result.state, MarkState.blank);
      expect(result.selectedOptionIds, isEmpty);
    });

    test(
      'printed-paper outline noise across untouched bubbles stays BLANK',
      () {
        final scenario = _singleChoice(optionCount: 4);
        const fillNoise = [0.13, 0.16, 0.14, 0.18];
        final result = _classify(
          engine,
          scenario,
          evidence: (bubble) => _Evidence(
            fill: fillNoise[scenario.page.bubbleRegions.indexOf(bubble)],
            normalized: 0.03,
            contrast: 6,
          ),
        );

        expect(result.state, MarkState.blank);
        expect(
          result.bubbleDecisions.map((decision) => decision.category),
          everyElement(BubbleEvidenceCategory.clearBlank),
        );
      },
    );

    test('weak printed noise does not reject one credible winner', () {
      final scenario = _singleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.first
            ? _Evidence.strong
            : _Evidence.weakOutlineNoise,
      );

      expect(result.state, MarkState.marked);
      expect(result.selectedOptionIds, [
        scenario.page.bubbleRegions.first.optionId,
      ]);
    });

    test('binary-strong grayscale-weak conflict returns AMBIGUOUS', () {
      final scenario = _singleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.first
            ? _Evidence.binaryConflict
            : _Evidence.blank,
      );

      expect(result.state, MarkState.ambiguous);
      expect(
        result.bubbleDecisions.first.category,
        BubbleEvidenceCategory.conflicting,
      );
    });

    test('grayscale-strong binary-weak pencil remains recognizable', () {
      final scenario = _singleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.last
            ? _Evidence.faintPencil
            : _Evidence.blank,
      );

      expect(result.state, MarkState.marked);
      expect(
        result.selectedOptionIds.single,
        scenario.page.bubbleRegions.last.optionId,
      );
    });

    test('unreliable local baseline downgrades evidence to AMBIGUOUS', () {
      final scenario = _singleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.first
            ? _Evidence.strongUnreliable
            : _Evidence.blank,
      );

      expect(result.state, MarkState.ambiguous);
      expect(
        result.bubbleDecisions.first.category,
        BubbleEvidenceCategory.unreliable,
      );
    });

    test('severe sample quality returns INVALID', () {
      final scenario = _singleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.first
            ? _Evidence.strongInvalid
            : _Evidence.blank,
      );

      expect(result.state, MarkState.invalid);
      expect(result.diagnostics.reason, ClassificationReason.unusableQuality);
    });
  });

  group('question-type semantics', () {
    test('multiple-choice all clear blanks return BLANK', () {
      final result = _classify(engine, _multipleChoice());

      expect(result.state, MarkState.blank);
      expect(result.selectedOptionIds, isEmpty);
    });

    test('multiple-choice one clear mark returns MARKED', () {
      final scenario = _multipleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.first
            ? _Evidence.strong
            : _Evidence.blank,
      );
      expect(result.state, MarkState.marked);
      expect(result.selectedOptionIds, hasLength(1));
    });

    test('multiple-choice several clear marks are valid selections', () {
      final scenario = _multipleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.last
            ? _Evidence.blank
            : _Evidence.strong,
      );
      expect(result.state, MarkState.marked);
      expect(result.selectedOptionIds, hasLength(2));
      expect(result.state, isNot(MarkState.multiple));
    });

    test('multiple-choice one credible possible mark returns MARKED', () {
      final scenario = _multipleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.first
            ? _Evidence.possibleTop
            : _Evidence.blank,
      );

      expect(result.state, MarkState.marked);
      expect(result.selectedOptionIds, [
        scenario.page.bubbleRegions[0].optionId,
      ]);
      expect(
        result.bubbleDecisions[0].category,
        BubbleEvidenceCategory.possibleMark,
      );
      expect(result.bubbleDecisions[0].state, BubbleDecisionState.selected);
    });

    test('multiple-choice several possible marks select each bubble', () {
      final scenario = _multipleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.last
            ? _Evidence.blank
            : _Evidence.possibleTop,
      );

      expect(result.state, MarkState.marked);
      expect(result.selectedOptionIds, [
        scenario.page.bubbleRegions[0].optionId,
        scenario.page.bubbleRegions[1].optionId,
      ]);
    });

    test('multiple-choice strong and possible marks are both selected', () {
      final scenario = _multipleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) =>
            switch (scenario.page.bubbleRegions.indexOf(bubble)) {
              0 => _Evidence.strong,
              1 => _Evidence.possibleTop,
              _ => _Evidence.blank,
            },
      );

      expect(result.state, MarkState.marked);
      expect(result.selectedOptionIds, [
        scenario.page.bubbleRegions[0].optionId,
        scenario.page.bubbleRegions[1].optionId,
      ]);
    });

    test('multiple-choice possible mark plus conflict returns AMBIGUOUS', () {
      final scenario = _multipleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) =>
            switch (scenario.page.bubbleRegions.indexOf(bubble)) {
              0 => _Evidence.possibleTop,
              1 => _Evidence.binaryConflict,
              _ => _Evidence.blank,
            },
      );

      expect(result.state, MarkState.ambiguous);
      expect(result.diagnostics.reason, ClassificationReason.uncertainEvidence);
      expect(
        result.bubbleDecisions[1].category,
        BubbleEvidenceCategory.conflicting,
      );
      expect(result.bubbleDecisions[1].fillRatio, 0.80);
      expect(result.bubbleDecisions[1].normalizedDarkness, 0.01);
      expect(result.bubbleDecisions[1].darknessContrast, 3);
      expect(result.bubbleDecisions[1].combinedScore, greaterThan(0));
    });

    test('multiple-choice conflicting evidence returns AMBIGUOUS', () {
      final scenario = _multipleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.first
            ? _Evidence.binaryConflict
            : _Evidence.blank,
      );

      expect(result.state, MarkState.ambiguous);
    });

    test('multiple-choice unreliable measurement returns AMBIGUOUS', () {
      final scenario = _multipleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.first
            ? _Evidence.strongUnreliable
            : _Evidence.blank,
      );

      expect(result.state, MarkState.ambiguous);
      expect(
        result.bubbleDecisions.first.category,
        BubbleEvidenceCategory.unreliable,
      );
    });

    test('multiple-choice unusable measurement returns INVALID', () {
      final scenario = _multipleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.first
            ? _Evidence.strongInvalid
            : _Evidence.blank,
      );

      expect(result.state, MarkState.invalid);
    });

    test('multiple-choice weak outline noise remains unselected', () {
      final scenario = _multipleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.first
            ? _Evidence.weakOutlineNoise
            : _Evidence.blank,
      );

      expect(result.state, MarkState.blank);
      expect(result.selectedOptionIds, isEmpty);
      expect(
        result.bubbleDecisions.first.category,
        BubbleEvidenceCategory.clearBlank,
      );
    });

    test('multiple-choice unsupported faint evidence remains unselected', () {
      final scenario = _multipleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.first
            ? _Evidence.unsupportedFaint
            : _Evidence.blank,
      );

      expect(result.state, MarkState.blank);
      expect(result.selectedOptionIds, isEmpty);
    });

    test('multiple-choice selections preserve template option order', () {
      final scenario = _multipleChoice();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) {
          final index = scenario.page.bubbleRegions.indexOf(bubble);
          return index == 0 || index == 2
              ? _Evidence.possibleTop
              : _Evidence.blank;
        },
      );

      expect(result.state, isNot(MarkState.multiple));
      expect(result.selectedOptionIds, [
        scenario.page.bubbleRegions[0].optionId,
        scenario.page.bubbleRegions[2].optionId,
      ]);
    });

    test('yes/no preserves one clear selected option', () {
      final scenario = _yesNo();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.first
            ? _Evidence.strong
            : _Evidence.blank,
      );
      expect(result.state, MarkState.marked);
      expect(result.selectedOptionIds.single.value, 'yes');
    });

    test('yes/no with both selected returns MULTIPLE', () {
      final scenario = _yesNo();
      final result = _classify(
        engine,
        scenario,
        evidence: (_) => _Evidence.strong,
      );
      expect(result.state, MarkState.multiple);
    });

    test('Likert one clear selection returns MARKED', () {
      final scenario = _likert();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions[1]
            ? _Evidence.strong
            : _Evidence.blank,
      );
      expect(result.state, MarkState.marked);
      expect(result.selectedOptionIds.single.value, 'scale-2');
    });

    test('Likert two clear selections return MULTIPLE', () {
      final scenario = _likert();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.last
            ? _Evidence.blank
            : _Evidence.strong,
      );
      expect(result.state, MarkState.multiple);
    });
  });

  group('numeric grid', () {
    test('one digit per column returns MARKED', () {
      final scenario = _numericGrid();
      final result = _classifyNumeric(engine, scenario, const [1, 7, 4]);
      expect(result.state, MarkState.marked);
      expect(result.numericSelection!.completeDigitString, '174');
    });

    test('a blank column makes a partial number AMBIGUOUS', () {
      final scenario = _numericGrid();
      final result = _classifyNumeric(engine, scenario, const [1, null, 4]);
      expect(result.state, MarkState.ambiguous);
      expect(
        result.diagnostics.reason,
        ClassificationReason.incompleteNumericGrid,
      );
    });

    test('two clear digits in one column return MULTIPLE', () {
      final scenario = _numericGrid();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) {
          if (bubble.numericColumnIndex == 0 &&
              (bubble.numericDigitValue == 2 ||
                  bubble.numericDigitValue == 8)) {
            return _Evidence.strong;
          }
          if (bubble.numericColumnIndex == 1 && bubble.numericDigitValue == 3) {
            return _Evidence.strong;
          }
          if (bubble.numericColumnIndex == 2 && bubble.numericDigitValue == 4) {
            return _Evidence.strong;
          }
          return _Evidence.blank;
        },
      );
      expect(result.state, MarkState.multiple);
    });

    test('ambiguous numeric column returns AMBIGUOUS', () {
      final scenario = _numericGrid();
      final result = _classify(
        engine,
        scenario,
        evidence: (bubble) {
          if (bubble.numericColumnIndex == 0 && bubble.numericDigitValue == 1) {
            return _Evidence.possibleTop;
          }
          if (bubble.numericColumnIndex == 0 && bubble.numericDigitValue == 2) {
            return _Evidence.possibleClose;
          }
          if (bubble.numericColumnIndex == 1 && bubble.numericDigitValue == 3) {
            return _Evidence.strong;
          }
          if (bubble.numericColumnIndex == 2 && bubble.numericDigitValue == 4) {
            return _Evidence.strong;
          }
          return _Evidence.blank;
        },
      );
      expect(result.state, MarkState.ambiguous);
    });

    test('selected digits preserve numeric column order', () {
      final scenario = _numericGrid();
      final result = _classifyNumeric(engine, scenario, const [9, 2, 6]);
      expect(
        result.numericSelection!.columns.map((column) => column.selectedDigit),
        [9, 2, 6],
      );
    });

    test('leading zero remains in the structured/string result', () {
      final scenario = _numericGrid();
      final result = _classifyNumeric(engine, scenario, const [0, 1, 5]);
      expect(result.numericSelection!.completeDigitString, '015');
      expect(result.numericSelection!.columns.first.selectedDigit, 0);
    });
  });

  group('structure and determinism', () {
    test('missing expected measurement is a structured failure', () {
      final scenario = _singleChoice();
      final list = _measurements(scenario.page)..removeLast();
      final result = engine.classify(
        scenario.template,
        scenario.page,
        BubbleMeasurementSet(pageId: scenario.page.pageId, measurements: list),
      );
      expect(result.error.code, 'MARK_CLASSIFICATION_MEASUREMENT_MISMATCH');
    });

    test('duplicate target measurement is detected', () {
      final scenario = _singleChoice();
      final list = _measurements(scenario.page)
        ..add(_measurements(scenario.page).first);
      final result = engine.classify(
        scenario.template,
        scenario.page,
        BubbleMeasurementSet(pageId: scenario.page.pageId, measurements: list),
      );
      expect(result.error.code, 'MARK_CLASSIFICATION_MEASUREMENT_MISMATCH');
    });

    test('unknown QuestionId is rejected', () {
      final scenario = _singleChoice();
      final list = _measurements(scenario.page);
      list[0] = _copyMeasurement(list[0], questionId: QuestionId('unknown'));
      final result = engine.classify(
        scenario.template,
        scenario.page,
        BubbleMeasurementSet(pageId: scenario.page.pageId, measurements: list),
      );
      expect(result.error.code, 'MARK_CLASSIFICATION_MEASUREMENT_MISMATCH');
    });

    test('question output ordering matches PageLayout', () {
      final template = fullTemplate();
      final page = buildLayout(template).pages.first;
      final result = engine.classify(
        template,
        page,
        BubbleMeasurementSet(
          pageId: page.pageId,
          measurements: _measurements(page),
        ),
      );
      expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
      expect(
        result.value.questions.map((question) => question.questionId),
        page.questionRegions.map((region) => region.questionId),
      );
    });

    test('same measurements and config classify identically', () {
      final scenario = _singleChoice();
      final set = BubbleMeasurementSet(
        pageId: scenario.page.pageId,
        measurements: _measurements(
          scenario.page,
          evidence: (bubble) => bubble == scenario.page.bubbleRegions.first
              ? _Evidence.strong
              : _Evidence.blank,
        ),
      );
      final first = engine
          .classify(scenario.template, scenario.page, set)
          .value;
      final second = engine
          .classify(scenario.template, scenario.page, set)
          .value;
      expect(first.questions.single.state, second.questions.single.state);
      expect(
        first.questions.single.bubbleDecisions.map(
          (decision) => decision.combinedScore,
        ),
        second.questions.single.bubbleDecisions.map(
          (decision) => decision.combinedScore,
        ),
      );
    });

    test('classifier does not mutate BubbleMeasurementSet', () {
      final scenario = _singleChoice();
      final originals = _measurements(scenario.page);
      final set = BubbleMeasurementSet(
        pageId: scenario.page.pageId,
        measurements: originals,
      );
      final before = set.measurements
          .map((measurement) => measurement.fillRatio)
          .toList();

      final result = engine.classify(scenario.template, scenario.page, set);

      expect(result.isSuccess, isTrue);
      expect(
        set.measurements.map((measurement) => measurement.fillRatio),
        before,
      );
      expect(set.measurements, orderedEquals(originals));
    });

    test('threshold boundary behavior is deterministic and inclusive', () {
      final scenario = _singleChoice();
      const boundary = _Evidence(fill: 0.45, normalized: 0.30, contrast: 60);
      QuestionClassification run() => _classify(
        engine,
        scenario,
        evidence: (bubble) => bubble == scenario.page.bubbleRegions.first
            ? boundary
            : _Evidence.blank,
      );
      expect(run().state, MarkState.marked);
      expect(
        run().bubbleDecisions.first.category,
        BubbleEvidenceCategory.strongMark,
      );
    });

    test('invalid config returns a structured failure', () {
      final scenario = _singleChoice();
      final result = engine.classify(
        scenario.template,
        scenario.page,
        BubbleMeasurementSet(
          pageId: scenario.page.pageId,
          measurements: _measurements(scenario.page),
        ),
        const MarkClassificationConfig(fillWeight: 0.9),
      );
      expect(result.error.code, 'MARK_CLASSIFICATION_INVALID_CONFIG');
    });
  });
}

final class _Scenario {
  const _Scenario(this.template, this.page);

  final TemplateDefinition template;
  final PageLayout page;
}

_Scenario _singleChoice({int optionCount = 3}) =>
    _scenario(choiceQuestion('single', optionCount: optionCount));

_Scenario _multipleChoice() => _scenario(
  choiceQuestion('multiple', type: QuestionType.multipleChoice, optionCount: 3),
);

_Scenario _yesNo() => _scenario(
  TemplateQuestion.yesNo(
    id: QuestionId('yes-no'),
    prompt: 'Choose yes or no',
    yesOptionId: OptionId('yes'),
    noOptionId: OptionId('no'),
  ),
);

_Scenario _likert() => _scenario(
  TemplateQuestion(
    id: QuestionId('likert'),
    type: QuestionType.likert,
    prompt: 'Choose a scale value',
    options: [
      TemplateOption(id: OptionId('scale-1'), label: 'One', value: 1),
      TemplateOption(id: OptionId('scale-2'), label: 'Two', value: 2),
      TemplateOption(id: OptionId('scale-3'), label: 'Three', value: 3),
    ],
  ),
);

_Scenario _numericGrid() => _scenario(
  TemplateQuestion.numericGrid(
    id: QuestionId('numeric'),
    prompt: 'Enter digits',
    spec: NumericGridSpec(columnCount: 3),
  ),
);

_Scenario _scenario(TemplateQuestion question) {
  final template = templateWithQuestions([question]);
  return _Scenario(template, buildLayout(template).pages.single);
}

QuestionClassification _classify(
  MarkClassificationEngine engine,
  _Scenario scenario, {
  _Evidence Function(BubbleRegion bubble)? evidence,
}) {
  final result = engine.classify(
    scenario.template,
    scenario.page,
    BubbleMeasurementSet(
      pageId: scenario.page.pageId,
      measurements: _measurements(scenario.page, evidence: evidence),
    ),
  );
  expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
  return result.value.questions.single;
}

QuestionClassification _classifyNumeric(
  MarkClassificationEngine engine,
  _Scenario scenario,
  List<int?> digits,
) => _classify(
  engine,
  scenario,
  evidence: (bubble) =>
      digits[bubble.numericColumnIndex!] == bubble.numericDigitValue
      ? _Evidence.strong
      : _Evidence.blank,
);

List<BubbleMeasurement> _measurements(
  PageLayout page, {
  _Evidence Function(BubbleRegion bubble)? evidence,
}) => [
  for (var index = 0; index < page.bubbleRegions.length; index++)
    _measurement(
      page.bubbleRegions[index],
      evidence?.call(page.bubbleRegions[index]) ?? _Evidence.blank,
      index,
    ),
];

BubbleMeasurement _measurement(
  BubbleRegion bubble,
  _Evidence evidence,
  int index,
) {
  final baseline = 240.0;
  return BubbleMeasurement(
    pageId: bubble.pageId,
    questionId: bubble.questionId,
    optionId: bubble.optionId,
    numericColumnIndex: bubble.numericColumnIndex,
    numericDigitValue: bubble.numericDigitValue,
    roi: CanonicalBubbleRoi(
      center: ImagePoint(index + 10, 10),
      printedRadius: 5,
      interiorRadius: 3.4,
      baselineInnerRadius: 6.25,
      baselineOuterRadius: 10,
    ),
    sampledInteriorPixelCount: 100,
    sampledBaselinePixelCount: 120,
    interiorMeanIntensity: baseline - evidence.contrast,
    interiorMedianIntensity: baseline - evidence.contrast,
    localBaselineIntensity: baseline,
    darknessContrast: evidence.contrast,
    normalizedDarkness: evidence.normalized,
    foregroundPixelCount: (evidence.fill * 100).round(),
    fillRatio: evidence.fill,
    quality: evidence.quality,
  );
}

BubbleMeasurement _copyMeasurement(
  BubbleMeasurement source, {
  QuestionId? questionId,
}) => BubbleMeasurement(
  pageId: source.pageId,
  questionId: questionId ?? source.questionId,
  optionId: source.optionId,
  numericColumnIndex: source.numericColumnIndex,
  numericDigitValue: source.numericDigitValue,
  roi: source.roi,
  sampledInteriorPixelCount: source.sampledInteriorPixelCount,
  sampledBaselinePixelCount: source.sampledBaselinePixelCount,
  interiorMeanIntensity: source.interiorMeanIntensity,
  interiorMedianIntensity: source.interiorMedianIntensity,
  localBaselineIntensity: source.localBaselineIntensity,
  darknessContrast: source.darknessContrast,
  normalizedDarkness: source.normalizedDarkness,
  foregroundPixelCount: source.foregroundPixelCount,
  fillRatio: source.fillRatio,
  quality: source.quality,
);

final class _Evidence {
  const _Evidence({
    required this.fill,
    required this.normalized,
    required this.contrast,
    this.quality = goodQuality,
  });

  final double fill;
  final double normalized;
  final double contrast;
  final BubbleMeasurementQuality quality;

  static const blank = _Evidence(fill: 0.02, normalized: 0.02, contrast: 3);
  static const weakOutlineNoise = _Evidence(
    fill: 0.16,
    normalized: 0.03,
    contrast: 6,
  );
  static const strong = _Evidence(fill: 0.80, normalized: 0.45, contrast: 90);
  static const possibleTop = _Evidence(
    fill: 0.30,
    normalized: 0.15,
    contrast: 30,
  );
  static const possibleClose = _Evidence(
    fill: 0.28,
    normalized: 0.15,
    contrast: 30,
  );
  static const faintPencil = _Evidence(
    fill: 0.08,
    normalized: 0.35,
    contrast: 70,
  );
  static const unsupportedFaint = _Evidence(
    fill: 0.07,
    normalized: 0.07,
    contrast: 10,
  );
  static const binaryConflict = _Evidence(
    fill: 0.80,
    normalized: 0.01,
    contrast: 3,
  );
  static const strongUnreliable = _Evidence(
    fill: 0.80,
    normalized: 0.45,
    contrast: 90,
    quality: unreliableQuality,
  );
  static const strongInvalid = _Evidence(
    fill: 0.80,
    normalized: 0.45,
    contrast: 90,
    quality: invalidQuality,
  );
}

const goodQuality = BubbleMeasurementQuality(
  interiorValidSampleRatio: 1,
  baselineValidSampleRatio: 1,
  clipping: BubbleRoiClipping.none,
  baselineForegroundRatio: 0.02,
  localBaselineReliable: true,
  neighborMaskedPixelCount: 0,
);

const unreliableQuality = BubbleMeasurementQuality(
  interiorValidSampleRatio: 1,
  baselineValidSampleRatio: 1,
  clipping: BubbleRoiClipping.none,
  baselineForegroundRatio: 0.45,
  localBaselineReliable: false,
  neighborMaskedPixelCount: 0,
);

const invalidQuality = BubbleMeasurementQuality(
  interiorValidSampleRatio: 0.60,
  baselineValidSampleRatio: 0.60,
  clipping: BubbleRoiClipping.partial,
  baselineForegroundRatio: 0.75,
  localBaselineReliable: false,
  neighborMaskedPixelCount: 0,
);
