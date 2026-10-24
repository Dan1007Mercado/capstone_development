import '../../core/errors/engine_error.dart';
import '../../core/ids/identifiers.dart';
import '../../core/result/engine_result.dart';
import '../../engines/scanner/domain/scan_result.dart';
import 'packet_models.dart';
import 'packet_response_repository.dart';

final class InMemoryPacketResponseRepository
    implements PacketResponseRepository {
  InMemoryPacketResponseRepository();

  InMemoryPacketResponseRepository.restore({
    required int nextPacketSequence,
    required int nextResponseSequence,
    required Iterable<AnswerSheetPacket> packets,
    required Iterable<PaperResponse> responses,
  }) : _nextPacketSequence = nextPacketSequence,
       _nextResponseSequence = nextResponseSequence,
       _packets = {for (final packet in packets) packet.packetId: packet},
       _responses = {
         for (final response in responses) response.responseId: response,
       };

  int _nextPacketSequence = 0;
  int _nextResponseSequence = 1;
  Map<PacketId, AnswerSheetPacket> _packets = {};
  Map<ResponseId, PaperResponse> _responses = {};

  PacketRepositorySnapshot snapshot() => PacketRepositorySnapshot(
    nextPacketSequence: _nextPacketSequence,
    nextResponseSequence: _nextResponseSequence,
    packets: _packets.values,
    responses: _responses.values,
  );

  @override
  Future<EngineResult<List<int>>> reservePacketSequences(int count) async {
    if (count <= 0) return EngineResult.failure(_invalidCount(count));
    final last = _nextPacketSequence + count - 1;
    if (last > 999) return EngineResult.failure(_capacity(last));
    final values = [
      for (var value = _nextPacketSequence; value <= last; value++) value,
    ];
    _nextPacketSequence = last + 1;
    return EngineResult.success(List.unmodifiable(values));
  }

  @override
  Future<EngineResult<List<AnswerSheetPacket>>> saveGeneratedPackets(
    Iterable<AnswerSheetPacket> packets,
  ) async {
    final values = packets.toList(growable: false);
    final ids = values.map((packet) => packet.packetId).toSet();
    final markerKeys = values
        .expand((packet) => packet.pages)
        .map((page) => page.identityMarkerIds.join(','))
        .toList(growable: false);
    final existingMarkerKeys = _packets.values
        .expand((packet) => packet.pages)
        .map((page) => page.identityMarkerIds.join(','))
        .toSet();
    if (ids.length != values.length ||
        values.any((packet) => _packets.containsKey(packet.packetId)) ||
        markerKeys.toSet().length != markerKeys.length ||
        markerKeys.any(existingMarkerKeys.contains)) {
      return EngineResult.failure(
        EngineError(
          code: 'PACKET_IDENTITY_ALREADY_EXISTS',
          message: 'Generated packet or page identity already exists.',
        ),
      );
    }
    for (final packet in values) {
      _packets[packet.packetId] = packet;
    }
    return EngineResult.success(List.unmodifiable(values));
  }

  @override
  Future<EngineResult<AnswerSheetPacket?>> getPacket(PacketId packetId) async =>
      EngineResult.success(_packets[packetId]);

  @override
  Future<EngineResult<List<AnswerSheetPacket>>> listPackets() async =>
      EngineResult.success(List.unmodifiable(_packets.values));

  @override
  Future<EngineResult<List<PaperResponse>>> listResponses() async =>
      EngineResult.success(List.unmodifiable(_responses.values));

  @override
  Future<EngineResult<PacketPageClaimResult>> claimPage({
    required PacketId packetId,
    required int pageIndex,
    required ScanResult result,
    required DateTime scannedAt,
  }) async {
    final packet = _packets[packetId];
    if (packet == null) {
      return EngineResult.failure(
        EngineError(
          code: 'PACKET_NOT_FOUND',
          message: 'Decoded packet identity is unknown.',
          details: {'packetId': packetId.value},
        ),
      );
    }
    final page = packet.pages
        .where((candidate) => candidate.pageIndex == pageIndex)
        .firstOrNull;
    final scanIdentity = result.packetIdentity;
    if (page == null ||
        scanIdentity == null ||
        scanIdentity.packetId != packetId ||
        scanIdentity.pageIndex != pageIndex ||
        scanIdentity.pageId != page.pageId ||
        scanIdentity.totalPages != packet.pages.length ||
        result.templateId != packet.templateId ||
        result.templateVersion != packet.templateVersion ||
        result.pageId != page.pageId) {
      return EngineResult.failure(
        EngineError(
          code: 'PACKET_PAGE_IDENTITY_MISMATCH',
          message: 'Scan result does not match the decoded packet page.',
          details: {
            'packetId': packetId.value,
            'pageIndex': pageIndex,
            'scanPageId': result.pageId.value,
          },
        ),
      );
    }
    if (result.pageState == ScanPageState.invalid) {
      return EngineResult.failure(
        EngineError(
          code: 'PACKET_SCAN_INVALID',
          message: 'An invalid scan cannot claim a packet response.',
          details: {'packetId': packetId.value, 'pageIndex': pageIndex},
        ),
      );
    }

    PaperResponse response;
    if (packet.responseId == null) {
      final responseId = ResponseId.fromSequence(_nextResponseSequence);
      final pageResult = _storedPage(pageIndex, result, scannedAt);
      response = PaperResponse(
        responseId: responseId,
        packetId: packetId,
        templateId: packet.templateId,
        templateVersion: packet.templateVersion,
        createdAt: scannedAt,
        updatedAt: scannedAt,
        status: packet.pages.length == 1
            ? PaperResponseStatus.complete
            : PaperResponseStatus.partial,
        pageResults: {result.pageId: pageResult},
      );
      final updatedPacket = packet.copyWith(
        responseId: responseId,
        status: packet.pages.length == 1
            ? AnswerSheetPacketStatus.complete
            : AnswerSheetPacketStatus.partial,
      );
      _nextResponseSequence++;
      _responses[responseId] = response;
      _packets[packetId] = updatedPacket;
      return EngineResult.success(
        PacketPageClaimResult(
          status: PacketPageClaimStatus.accepted,
          packet: updatedPacket,
          response: response,
        ),
      );
    }

    response = _responses[packet.responseId]!;
    if (response.pageResults.containsKey(result.pageId)) {
      return EngineResult.success(
        PacketPageClaimResult(
          status: PacketPageClaimStatus.duplicate,
          packet: packet,
          response: response,
        ),
      );
    }
    final results = {
      ...response.pageResults,
      result.pageId: _storedPage(pageIndex, result, scannedAt),
    };
    final complete = results.length == packet.pages.length;
    response = PaperResponse(
      responseId: response.responseId,
      packetId: response.packetId,
      templateId: response.templateId,
      templateVersion: response.templateVersion,
      createdAt: response.createdAt,
      updatedAt: scannedAt,
      status: complete
          ? PaperResponseStatus.complete
          : PaperResponseStatus.partial,
      pageResults: results,
    );
    final updatedPacket = packet.copyWith(
      status: complete
          ? AnswerSheetPacketStatus.complete
          : AnswerSheetPacketStatus.partial,
    );
    _responses[response.responseId] = response;
    _packets[packetId] = updatedPacket;
    return EngineResult.success(
      PacketPageClaimResult(
        status: PacketPageClaimStatus.accepted,
        packet: updatedPacket,
        response: response,
      ),
    );
  }

  StoredPacketPageResult _storedPage(
    int pageIndex,
    ScanResult result,
    DateTime scannedAt,
  ) => StoredPacketPageResult(
    pageId: result.pageId,
    pageIndex: pageIndex,
    scannedAt: scannedAt,
    questions: [
      for (final question in result.questions)
        StoredQuestionResponse(
          questionId: question.questionId,
          questionNumber: question.questionNumber,
          state: question.state,
          selectedOptionIds: question.selectedOptionIds,
          numericAnswer: question.numericSelection?.completeDigitString,
        ),
    ],
  );

  EngineError _invalidCount(int count) => EngineError(
    code: 'PACKET_COUNT_INVALID',
    message: 'Packet count must be positive.',
    details: {'count': count},
  );

  EngineError _capacity(int last) => EngineError(
    code: 'PACKET_MARKER_CAPACITY_EXCEEDED',
    message: 'Packet generation exceeds marker codec capacity.',
    details: {'requestedLastSequence': last, 'maximumSequence': 999},
  );
}
