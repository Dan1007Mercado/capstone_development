import 'package:capstone_development/application/answer_sheet_packets/packet_models.dart';
import 'package:capstone_development/application/answer_sheet_packets/packet_response_repository.dart';
import 'package:capstone_development/application/answer_sheet_packets/packet_response_service.dart';
import 'package:capstone_development/application/real_scanner/scan_acceptance_policy.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessed_page.dart';
import 'package:capstone_development/engines/recognition/domain/mark_classification.dart';
import 'package:capstone_development/engines/scanner/domain/scan_result.dart';
import 'package:capstone_development/engines/template/domain/question_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = ScanAcceptancePolicy();

  test('all blank page requires rescan', () {
    final result = policy.evaluate(
      _scan([
        _question('q1', MarkState.blank),
        _question('q2', MarkState.blank),
      ]),
    );
    expect(result.decision, ScanAcceptanceDecision.rescanBlankPage);
  });

  test('optional blank is allowed when another response is valid', () {
    final result = policy.evaluate(
      _scan([
        _question('q1', MarkState.marked),
        _question('q2', MarkState.blank),
      ]),
    );
    expect(result.decision, ScanAcceptanceDecision.accept);
  });

  test('ambiguous, invalid, and exclusive multiple require rescan', () {
    expect(
      policy.evaluate(_scan([_question('q1', MarkState.ambiguous)])).decision,
      ScanAcceptanceDecision.rescanAmbiguous,
    );
    expect(
      policy.evaluate(_scan([_question('q1', MarkState.invalid)])).decision,
      ScanAcceptanceDecision.rescanInvalid,
    );
    expect(
      policy.evaluate(_scan([_question('q1', MarkState.multiple)])).decision,
      ScanAcceptanceDecision.rescanAmbiguous,
    );
  });

  test('valid multiple-choice selections are accepted', () {
    final question = _question(
      'q1',
      MarkState.marked,
      type: QuestionType.multipleChoice,
      selected: [OptionId('a'), OptionId('b')],
    );
    expect(policy.evaluate(_scan([question])).accepted, isTrue);
  });

  test('incomplete numeric grid requires rescan', () {
    final question = _question(
      'q1',
      MarkState.ambiguous,
      type: QuestionType.numericGrid,
      numericSelection: NumericGridSelection([
        NumericColumnClassification(
          columnIndex: 0,
          state: MarkState.marked,
          selectedDigit: 1,
          decisions: const [],
        ),
        NumericColumnClassification(
          columnIndex: 1,
          state: MarkState.blank,
          selectedDigit: null,
          decisions: const [],
        ),
      ]),
    );
    expect(
      policy.evaluate(_scan([question])).decision,
      ScanAcceptanceDecision.rescanAmbiguous,
    );
  });

  test('rejected scan never reaches packet repository', () async {
    final repository = _RecordingPacketRepository();
    final result = await PacketResponseService(
      repository: repository,
    ).claim(_scan([_question('q1', MarkState.blank)]));
    expect(result.isFailure, isTrue);
    expect(repository.claimCalls, 0);
  });
}

QuestionClassification _question(
  String id,
  MarkState state, {
  QuestionType type = QuestionType.singleChoice,
  List<OptionId> selected = const [],
  NumericGridSelection? numericSelection,
}) => QuestionClassification(
  questionId: QuestionId(id),
  questionNumber: 1,
  questionType: type,
  state: state,
  selectedOptionIds: selected,
  numericSelection: numericSelection,
  bubbleDecisions: const [],
  diagnostics: const QuestionClassificationDiagnostics(
    topScore: 1,
    secondScore: 0,
    scoreGap: 1,
    reason: ClassificationReason.singleStrongMark,
  ),
);

ScanResult _scan(List<QuestionClassification> questions) {
  const statistics = ImageStatistics(
    meanIntensity: 200,
    intensityStandardDeviation: 20,
    minimumIntensity: 0,
    maximumIntensity: 255,
    darkPixelRatio: 0.1,
    brightPixelRatio: 0.8,
  );
  return ScanResult(
    templateId: TemplateId('template'),
    templateVersion: TemplateVersion(1),
    pageId: PageId('page-1'),
    questions: questions,
    pageState: ScanPageState.accepted,
    reviewReasons: const [],
    reviewQuestionIds: const [],
    diagnostics: ScanDiagnostics(
      totalProcessingDuration: Duration.zero,
      stageDurations: const ScanStageDurations(
        alignment: Duration.zero,
        preprocessing: Duration.zero,
        measurement: Duration.zero,
        classification: Duration.zero,
      ),
      alignment: PageAlignmentDiagnostics(
        expectedMarkerIds: const [1, 2, 3, 4],
        detectedMarkerIds: const [1, 2, 3, 4],
        sourceMarkerSideLengths: const [20, 20, 20, 20],
        sourceRegistrationPoints: const [],
        destinationRegistrationPoints: const [],
        registrationQuality: const RegistrationQuality(
          quadrilateralAreaRatio: 0.5,
          minimumMarkerSidePixels: 20,
          maximumPerspectiveRatio: 1,
        ),
        reprojectionErrors: const [0, 0, 0, 0],
        meanReprojectionError: 0,
        maxReprojectionError: 0,
        processingDuration: Duration.zero,
      ),
      preprocessing: const PreprocessingDiagnostics(
        sourceStatistics: statistics,
        normalizedStatistics: statistics,
        binaryForegroundRatio: 0.1,
        processingDuration: Duration.zero,
      ),
      summary: ScanSummary(
        totalQuestions: questions.length,
        marked: questions.where((q) => q.state == MarkState.marked).length,
        blank: questions.where((q) => q.state == MarkState.blank).length,
        multiple: questions.where((q) => q.state == MarkState.multiple).length,
        ambiguous: questions
            .where((q) => q.state == MarkState.ambiguous)
            .length,
        invalid: questions.where((q) => q.state == MarkState.invalid).length,
        requiredBlank: 0,
        measuredBubbles: 0,
      ),
    ),
  );
}

final class _RecordingPacketRepository implements PacketResponseRepository {
  int claimCalls = 0;

  @override
  Future<EngineResult<PacketPageClaimResult>> claimPage({
    required PacketId packetId,
    required int pageIndex,
    required ScanResult result,
    required DateTime scannedAt,
  }) async {
    claimCalls++;
    throw StateError('Rejected results must not reach this method.');
  }

  @override
  Future<EngineResult<AnswerSheetPacket?>> getPacket(PacketId packetId) =>
      throw UnimplementedError();
  @override
  Future<EngineResult<List<AnswerSheetPacket>>> listPackets() =>
      throw UnimplementedError();
  @override
  Future<EngineResult<List<PaperResponse>>> listResponses() =>
      throw UnimplementedError();
  @override
  Future<EngineResult<List<int>>> reservePacketSequences(int count) =>
      throw UnimplementedError();
  @override
  Future<EngineResult<List<AnswerSheetPacket>>> saveGeneratedPackets(
    Iterable<AnswerSheetPacket> packets,
  ) => throw UnimplementedError();
}
