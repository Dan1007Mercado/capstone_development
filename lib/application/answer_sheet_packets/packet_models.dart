import 'dart:collection';
import 'dart:typed_data';

import '../../core/ids/identifiers.dart';
import '../../engines/recognition/domain/mark_classification.dart';

enum AnswerSheetPacketStatus { unused, partial, complete }

enum PaperResponseStatus { partial, complete }

enum ResponseSource { paper }

enum PacketPageClaimStatus { accepted, duplicate }

final class AnswerSheetPacketPage {
  AnswerSheetPacketPage({
    required this.packetId,
    required this.pageId,
    required this.pageIndex,
    required this.totalPages,
    required Iterable<int> identityMarkerIds,
  }) : identityMarkerIds = UnmodifiableListView(List.of(identityMarkerIds));

  final PacketId packetId;
  final PageId pageId;
  final int pageIndex;
  final int totalPages;
  final List<int> identityMarkerIds;
}

final class AnswerSheetPacket {
  AnswerSheetPacket({
    required this.packetId,
    required this.templateId,
    required this.templateVersion,
    required this.createdAt,
    required Iterable<AnswerSheetPacketPage> pages,
    required this.status,
    this.responseId,
  }) : pages = UnmodifiableListView(List.of(pages));

  final PacketId packetId;
  final TemplateId templateId;
  final TemplateVersion templateVersion;
  final DateTime createdAt;
  final List<AnswerSheetPacketPage> pages;
  final AnswerSheetPacketStatus status;
  final ResponseId? responseId;

  AnswerSheetPacket copyWith({
    AnswerSheetPacketStatus? status,
    ResponseId? responseId,
  }) => AnswerSheetPacket(
    packetId: packetId,
    templateId: templateId,
    templateVersion: templateVersion,
    createdAt: createdAt,
    pages: pages,
    status: status ?? this.status,
    responseId: responseId ?? this.responseId,
  );
}

final class StoredQuestionResponse {
  StoredQuestionResponse({
    required this.questionId,
    required this.questionNumber,
    required this.state,
    required Iterable<OptionId> selectedOptionIds,
    this.numericAnswer,
  }) : selectedOptionIds = UnmodifiableListView(List.of(selectedOptionIds));

  final QuestionId questionId;
  final int questionNumber;
  final MarkState state;
  final List<OptionId> selectedOptionIds;
  final String? numericAnswer;
}

final class StoredPacketPageResult {
  StoredPacketPageResult({
    required this.pageId,
    required this.pageIndex,
    required this.scannedAt,
    required Iterable<StoredQuestionResponse> questions,
  }) : questions = UnmodifiableListView(List.of(questions));

  final PageId pageId;
  final int pageIndex;
  final DateTime scannedAt;
  final List<StoredQuestionResponse> questions;
}

final class PaperResponse {
  PaperResponse({
    required this.responseId,
    required this.packetId,
    required this.templateId,
    required this.templateVersion,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    required this.status,
    required Map<PageId, StoredPacketPageResult> pageResults,
  }) : pageResults = UnmodifiableMapView(Map.of(pageResults));

  final ResponseId responseId;
  final PacketId packetId;
  final TemplateId templateId;
  final TemplateVersion templateVersion;
  final ResponseSource source;
  final DateTime createdAt;
  final DateTime updatedAt;
  final PaperResponseStatus status;
  final Map<PageId, StoredPacketPageResult> pageResults;
}

final class PacketArtifact {
  PacketArtifact({required this.packet, required Uint8List pdfBytes})
    : pdfBytes = Uint8List.fromList(pdfBytes);

  final AnswerSheetPacket packet;
  final Uint8List pdfBytes;
}

final class PacketPageClaimResult {
  const PacketPageClaimResult({
    required this.status,
    required this.packet,
    required this.response,
  });

  final PacketPageClaimStatus status;
  final AnswerSheetPacket packet;
  final PaperResponse response;
}

final class PacketRepositorySnapshot {
  PacketRepositorySnapshot({
    required this.nextPacketSequence,
    required this.nextResponseSequence,
    required Iterable<AnswerSheetPacket> packets,
    required Iterable<PaperResponse> responses,
  }) : packets = UnmodifiableListView(List.of(packets)),
       responses = UnmodifiableListView(List.of(responses));

  final int nextPacketSequence;
  final int nextResponseSequence;
  final List<AnswerSheetPacket> packets;
  final List<PaperResponse> responses;
}
