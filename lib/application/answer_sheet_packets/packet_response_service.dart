import '../../core/errors/engine_error.dart';
import '../../core/result/engine_result.dart';
import '../../engines/scanner/domain/scan_result.dart';
import 'packet_models.dart';
import 'packet_response_repository.dart';

final class PacketResponseService {
  PacketResponseService({required this.repository, DateTime Function()? clock})
    : clock = clock ?? DateTime.now;

  final PacketResponseRepository repository;
  final DateTime Function() clock;

  Future<EngineResult<PacketPageClaimResult>> claim(ScanResult result) {
    final identity = result.packetIdentity;
    if (identity == null) {
      return Future.value(
        EngineResult.failure(
          EngineError(
            code: 'PACKET_IDENTITY_MISSING',
            message: 'A packet response cannot be claimed without identity.',
          ),
        ),
      );
    }
    return repository.claimPage(
      packetId: identity.packetId,
      pageIndex: identity.pageIndex,
      result: result,
      scannedAt: clock().toUtc(),
    );
  }
}
