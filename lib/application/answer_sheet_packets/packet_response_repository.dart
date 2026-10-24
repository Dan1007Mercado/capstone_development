import '../../core/ids/identifiers.dart';
import '../../core/result/engine_result.dart';
import '../../engines/scanner/domain/scan_result.dart';
import 'packet_models.dart';

abstract interface class PacketResponseRepository {
  Future<EngineResult<List<int>>> reservePacketSequences(int count);

  Future<EngineResult<List<AnswerSheetPacket>>> saveGeneratedPackets(
    Iterable<AnswerSheetPacket> packets,
  );

  Future<EngineResult<AnswerSheetPacket?>> getPacket(PacketId packetId);

  Future<EngineResult<List<AnswerSheetPacket>>> listPackets();

  Future<EngineResult<List<PaperResponse>>> listResponses();

  /// Atomically binds an unused packet, creates its response, and stores the
  /// first page; or appends a new page to the already-bound response.
  Future<EngineResult<PacketPageClaimResult>> claimPage({
    required PacketId packetId,
    required int pageIndex,
    required ScanResult result,
    required DateTime scannedAt,
  });
}
