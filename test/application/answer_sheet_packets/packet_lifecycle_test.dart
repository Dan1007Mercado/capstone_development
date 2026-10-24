import 'dart:io';
import 'dart:typed_data';

import 'package:capstone_development/application/answer_sheet_packets/file_packet_response_repository.dart';
import 'package:capstone_development/application/answer_sheet_packets/in_memory_packet_response_repository.dart';
import 'package:capstone_development/application/answer_sheet_packets/packet_generation_service.dart';
import 'package:capstone_development/application/answer_sheet_packets/packet_models.dart';
import 'package:capstone_development/application/answer_sheet_packets/packet_response_service.dart';
import 'package:capstone_development/application/published_templates/published_template_artifact.dart';
import 'package:capstone_development/core/errors/engine_error.dart';
import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/core/protocol/packet_marker_codec.dart';
import 'package:capstone_development/core/result/engine_result.dart';
import 'package:capstone_development/debug/p11_1_scanner_validation_sheet.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/layout/domain/layout_config.dart';
import 'package:capstone_development/engines/preprocessing/domain/preprocessed_page.dart';
import 'package:capstone_development/engines/scanner/domain/packet_scan_identity.dart';
import 'package:capstone_development/engines/scanner/domain/scan_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('packet marker codec', () {
    test('round-trips packet and physical page identity', () {
      const codec = PacketMarkerCodec();
      final packetId = PacketId.fromSequence(237);

      final encoded = codec.encode(packetId: packetId, pageIndex: 6);
      final decoded = codec.decode(encoded.value.markerIds);

      expect(encoded.value.markerIds, [2, 3, 7, 6]);
      expect(decoded.value.packetId, packetId);
      expect(decoded.value.pageIndex, 6);
    });

    test('rejects incomplete identity and codec capacity overflow', () {
      const codec = PacketMarkerCodec();
      expect(
        codec.decode([1, 2, 3]).error.code,
        'PACKET_IDENTITY_MARKER_COUNT_INVALID',
      );
      expect(
        codec.decode([0, 0, 0, 0], version: 2).error.code,
        'PACKET_CODEC_VERSION_UNSUPPORTED',
      );
      expect(
        codec
            .encode(packetId: PacketId.fromSequence(1), pageIndex: 10)
            .error
            .code,
        'PACKET_MARKER_CAPACITY_EXCEEDED',
      );
    });
  });

  test(
    'generates 100 unique packets without preallocating responses',
    () async {
      final repository = InMemoryPacketResponseRepository();
      final artifact = _publishedArtifact();
      final generated = await PacketGenerationService(
        repository: repository,
        pdfRenderer: (_, _) async =>
            EngineResult.success(Uint8List.fromList([37, 80, 68, 70, 45])),
      ).generatePackets(artifact, count: 100);

      expect(
        generated.isSuccess,
        isTrue,
        reason: generated.errorOrNull?.toString(),
      );
      expect(generated.value, hasLength(100));
      expect(
        generated.value.map((item) => item.packet.packetId).toSet(),
        hasLength(100),
      );
      expect(
        generated.value
            .expand((item) => item.packet.pages)
            .map((page) => page.identityMarkerIds.join(','))
            .toSet(),
        hasLength(100 * artifact.layout.pages.length),
      );
      expect((await repository.listResponses()).value, isEmpty);
    },
  );

  test(
    'batch generation commits 50 unused packets and scan creates one response',
    () async {
      final repository = InMemoryPacketResponseRepository();
      final artifact = _publishedArtifact();
      var renderCalls = 0;
      final generated = await PacketGenerationService(
        repository: repository,
        batchPdfRenderer: (_, packets) async {
          renderCalls++;
          expect(packets, hasLength(50));
          return EngineResult.success(
            Uint8List.fromList([37, 80, 68, 70, 45, 66]),
          );
        },
      ).generateBatch(artifact, count: 50);

      expect(
        generated.isSuccess,
        isTrue,
        reason: generated.errorOrNull?.toString(),
      );
      expect(renderCalls, 1);
      expect(generated.value.packets, hasLength(50));
      expect(
        generated.value.packets.map((packet) => packet.packetId).toSet(),
        hasLength(50),
      );
      expect(
        generated.value.packets.every(
          (packet) => packet.status == AnswerSheetPacketStatus.unused,
        ),
        isTrue,
      );
      expect((await repository.listResponses()).value, isEmpty);

      final claimed = await PacketResponseService(
        repository: repository,
      ).claim(_scan(generated.value.packets.first, 0));

      expect(claimed.isSuccess, isTrue);
      expect((await repository.listResponses()).value, hasLength(1));
      final stored = (await repository.listPackets()).value;
      expect(
        stored.where(
          (packet) => packet.status == AnswerSheetPacketStatus.unused,
        ),
        hasLength(49),
      );
    },
  );

  test(
    'failed batch commits no packets and never reuses reserved IDs',
    () async {
      final repository = InMemoryPacketResponseRepository();
      final artifact = _publishedArtifact();
      final service = PacketGenerationService(
        repository: repository,
        batchPdfRenderer: (_, _) async => EngineResult.failure(
          EngineError(
            code: 'PACKET_BATCH_RENDER_FAILED',
            message: 'Synthetic batch failure.',
          ),
        ),
      );

      final failed = await service.generateBatch(artifact, count: 2);

      expect(failed.error.code, 'PACKET_BATCH_RENDER_FAILED');
      expect((await repository.listPackets()).value, isEmpty);
      expect((await repository.listResponses()).value, isEmpty);
      expect((await repository.reservePacketSequences(1)).value, [2]);
    },
  );

  group('response claiming', () {
    test('single-page first scan completes and repeat is duplicate', () async {
      final repository = InMemoryPacketResponseRepository();
      final packet = _packet(pageCount: 1, sequence: 10);
      await repository.saveGeneratedPackets([packet]);
      final service = PacketResponseService(repository: repository);
      final result = _scan(packet, 0);

      final first = await service.claim(result);
      final second = await service.claim(result);

      expect(first.value.status, PacketPageClaimStatus.accepted);
      expect(first.value.packet.status, AnswerSheetPacketStatus.complete);
      expect(first.value.response.status, PaperResponseStatus.complete);
      expect(second.value.status, PacketPageClaimStatus.duplicate);
      expect(second.value.response.responseId, first.value.response.responseId);
      expect((await repository.listResponses()).value, hasLength(1));
    });

    test(
      'multi-page scans are order-independent and duplicates are idempotent',
      () async {
        final repository = InMemoryPacketResponseRepository();
        final packet = _packet(pageCount: 3, sequence: 11);
        await repository.saveGeneratedPackets([packet]);
        final service = PacketResponseService(repository: repository);

        final page2 = await service.claim(_scan(packet, 1));
        final page1 = await service.claim(_scan(packet, 0));
        final duplicate2 = await service.claim(_scan(packet, 1));
        final page3 = await service.claim(_scan(packet, 2));

        expect(page2.value.response.status, PaperResponseStatus.partial);
        expect(page1.value.response.status, PaperResponseStatus.partial);
        expect(duplicate2.value.status, PacketPageClaimStatus.duplicate);
        expect(page3.value.response.status, PaperResponseStatus.complete);
        expect(page3.value.response.pageResults, hasLength(3));
        expect((await repository.listResponses()).value, hasLength(1));
      },
    );

    test('different packets create different responses', () async {
      final repository = InMemoryPacketResponseRepository();
      final first = _packet(pageCount: 1, sequence: 12);
      final second = _packet(pageCount: 1, sequence: 13);
      await repository.saveGeneratedPackets([first, second]);
      final service = PacketResponseService(repository: repository);

      final firstClaim = await service.claim(_scan(first, 0));
      final secondClaim = await service.claim(_scan(second, 0));

      expect(
        firstClaim.value.response.responseId,
        isNot(secondClaim.value.response.responseId),
      );
      expect((await repository.listResponses()).value, hasLength(2));
    });

    test(
      'near-simultaneous claims produce one response and one duplicate',
      () async {
        final repository = InMemoryPacketResponseRepository();
        final packet = _packet(pageCount: 1, sequence: 14);
        await repository.saveGeneratedPackets([packet]);
        final service = PacketResponseService(repository: repository);

        final claims = await Future.wait([
          service.claim(_scan(packet, 0)),
          service.claim(_scan(packet, 0)),
        ]);

        expect(claims.map((claim) => claim.value.status).toSet(), {
          PacketPageClaimStatus.accepted,
          PacketPageClaimStatus.duplicate,
        });
        expect((await repository.listResponses()).value, hasLength(1));
      },
    );

    test(
      'mismatched identity and invalid scans never create a response',
      () async {
        final repository = InMemoryPacketResponseRepository();
        final packet = _packet(pageCount: 2, sequence: 15);
        await repository.saveGeneratedPackets([packet]);
        final service = PacketResponseService(repository: repository);

        final mismatch = _scan(packet, 0, identityPageIndex: 1);
        final invalid = _scan(packet, 0, pageState: ScanPageState.invalid);

        expect(
          (await service.claim(mismatch)).error.code,
          'PACKET_PAGE_IDENTITY_MISMATCH',
        );
        expect(
          (await service.claim(invalid)).error.code,
          'PACKET_SCAN_INVALID',
        );
        expect((await repository.listResponses()).value, isEmpty);
      },
    );
  });

  test(
    'durable repository preserves binding and duplicate state after restart',
    () async {
      final root = await Directory.systemTemp.createTemp('p14_4_packet_test_');
      addTearDown(() => root.delete(recursive: true));
      final packet = _packet(pageCount: 2, sequence: 16);
      final firstRepository = FilePacketResponseRepository(rootDirectory: root);
      await firstRepository.saveGeneratedPackets([packet]);
      final first = await PacketResponseService(
        repository: firstRepository,
      ).claim(_scan(packet, 1));

      final restarted = FilePacketResponseRepository(rootDirectory: root);
      final duplicate = await PacketResponseService(
        repository: restarted,
      ).claim(_scan(packet, 1));
      final restoredPacket = (await restarted.getPacket(
        packet.packetId,
      )).value!;

      expect(duplicate.value.status, PacketPageClaimStatus.duplicate);
      expect(
        duplicate.value.response.responseId,
        first.value.response.responseId,
      );
      expect(restoredPacket.responseId, first.value.response.responseId);
      expect(restoredPacket.status, AnswerSheetPacketStatus.partial);
      expect((await restarted.listResponses()).value, hasLength(1));
    },
  );
}

PublishedTemplateArtifact _publishedArtifact() {
  final inputs = buildP11ScannerValidationSheetInputs();
  return PublishedTemplateArtifact(
    template: inputs.template.toPublishedAfterValidation(),
    layoutProfile: LayoutProfile.answerSheet,
    layout: inputs.layout,
    pdfBytes: Uint8List.fromList([37, 80, 68, 70, 45]),
  );
}

AnswerSheetPacket _packet({required int pageCount, required int sequence}) {
  final packetId = PacketId.fromSequence(sequence);
  const codec = PacketMarkerCodec();
  return AnswerSheetPacket(
    packetId: packetId,
    templateId: TemplateId('packet-template'),
    templateVersion: TemplateVersion(3),
    createdAt: DateTime.utc(2026, 1, 1),
    pages: [
      for (var index = 0; index < pageCount; index++)
        AnswerSheetPacketPage(
          packetId: packetId,
          pageId: PageId('packet-template-v3-p${index + 1}'),
          pageIndex: index,
          totalPages: pageCount,
          identityMarkerIds: codec
              .encode(packetId: packetId, pageIndex: index)
              .value
              .markerIds,
        ),
    ],
    status: AnswerSheetPacketStatus.unused,
  );
}

ScanResult _scan(
  AnswerSheetPacket packet,
  int pageIndex, {
  int? identityPageIndex,
  ScanPageState pageState = ScanPageState.accepted,
}) {
  final page = packet.pages[pageIndex];
  final identityPage = packet.pages[identityPageIndex ?? pageIndex];
  const statistics = ImageStatistics(
    meanIntensity: 200,
    intensityStandardDeviation: 20,
    minimumIntensity: 0,
    maximumIntensity: 255,
    darkPixelRatio: 0.1,
    brightPixelRatio: 0.8,
  );
  return ScanResult(
    templateId: packet.templateId,
    templateVersion: packet.templateVersion,
    pageId: page.pageId,
    questions: const [],
    pageState: pageState,
    reviewReasons: const [],
    reviewQuestionIds: const [],
    packetIdentity: PacketPageIdentity(
      packetId: packet.packetId,
      templateId: packet.templateId,
      templateVersion: packet.templateVersion,
      pageId: identityPage.pageId,
      pageIndex: identityPage.pageIndex,
      totalPages: identityPage.totalPages,
      identityMarkerIds: identityPage.identityMarkerIds,
    ),
    diagnostics: ScanDiagnostics(
      totalProcessingDuration: Duration.zero,
      stageDurations: const ScanStageDurations(
        alignment: Duration.zero,
        preprocessing: Duration.zero,
        measurement: Duration.zero,
        classification: Duration.zero,
      ),
      alignment: PageAlignmentDiagnostics(
        expectedMarkerIds: const [10, 11, 12, 13],
        detectedMarkerIds: const [10, 11, 12, 13],
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
      summary: const ScanSummary(
        totalQuestions: 0,
        marked: 0,
        blank: 0,
        multiple: 0,
        ambiguous: 0,
        invalid: 0,
        requiredBlank: 0,
        measuredBubbles: 0,
      ),
    ),
  );
}
