import '../../core/errors/engine_error.dart';
import '../../core/result/engine_result.dart';
import '../../engines/scanner/domain/scan_result.dart';
import '../real_scanner/scan_acceptance_policy.dart';
import 'packet_models.dart';
import 'packet_response_repository.dart';

final class PacketResponseService {
  PacketResponseService({
    required this.repository,
    DateTime Function()? clock,
    this.acceptancePolicy = const ScanAcceptancePolicy(),
  }) : clock = clock ?? DateTime.now;

  final PacketResponseRepository repository;
  final DateTime Function() clock;
  final ScanAcceptancePolicy acceptancePolicy;

  Future<EngineResult<PacketPageClaimResult>> claim(ScanResult result) {
    final acceptance = acceptancePolicy.evaluate(result);
    if (!acceptance.accepted) {
      return Future.value(
        EngineResult.failure(
          EngineError(
            code: acceptance.decision == ScanAcceptanceDecision.rescanInvalid
                ? 'PACKET_SCAN_INVALID'
                : 'PACKET_SCAN_RESCAN_REQUIRED',
            message: acceptance.title,
            details: {
              'decision': acceptance.decision.name,
              'questionIds': acceptance.questionIds
                  .map((id) => id.value)
                  .toList(growable: false),
            },
          ),
        ),
      );
    }
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
