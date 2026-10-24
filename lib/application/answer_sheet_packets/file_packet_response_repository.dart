import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/errors/engine_error.dart';
import '../../core/ids/identifiers.dart';
import '../../core/result/engine_result.dart';
import '../../engines/recognition/domain/mark_classification.dart';
import '../../engines/scanner/domain/scan_result.dart';
import 'in_memory_packet_response_repository.dart';
import 'packet_models.dart';
import 'packet_response_repository.dart';

/// Durable append-only packet/response snapshots.
///
/// A mutation becomes visible only after its complete snapshot is renamed into
/// place. Older generations remain valid if a process stops mid-write.
final class FilePacketResponseRepository implements PacketResponseRepository {
  FilePacketResponseRepository({required Directory rootDirectory})
    : _rootDirectory = rootDirectory;

  final Directory _rootDirectory;
  Future<void> _tail = Future.value();

  @override
  Future<EngineResult<List<int>>> reservePacketSequences(int count) =>
      _mutate((repository) => repository.reservePacketSequences(count));

  @override
  Future<EngineResult<List<AnswerSheetPacket>>> saveGeneratedPackets(
    Iterable<AnswerSheetPacket> packets,
  ) => _mutate((repository) => repository.saveGeneratedPackets(packets));

  @override
  Future<EngineResult<PacketPageClaimResult>> claimPage({
    required PacketId packetId,
    required int pageIndex,
    required ScanResult result,
    required DateTime scannedAt,
  }) => _mutate(
    (repository) => repository.claimPage(
      packetId: packetId,
      pageIndex: pageIndex,
      result: result,
      scannedAt: scannedAt,
    ),
  );

  @override
  Future<EngineResult<AnswerSheetPacket?>> getPacket(PacketId packetId) =>
      _read((repository) => repository.getPacket(packetId));

  @override
  Future<EngineResult<List<AnswerSheetPacket>>> listPackets() =>
      _read((repository) => repository.listPackets());

  @override
  Future<EngineResult<List<PaperResponse>>> listResponses() =>
      _read((repository) => repository.listResponses());

  Future<EngineResult<T>> _mutate<T>(
    Future<EngineResult<T>> Function(InMemoryPacketResponseRepository value)
    operation,
  ) => _locked(() async {
    final loaded = await _load();
    if (loaded.isFailure) return EngineResult.failure(loaded.error);
    final result = await operation(loaded.value.repository);
    if (result.isFailure) return result;
    final saved = await _save(
      loaded.value.repository.snapshot(),
      loaded.value.generation + 1,
    );
    if (saved.isFailure) return EngineResult.failure(saved.error);
    return result;
  });

  Future<EngineResult<T>> _read<T>(
    Future<EngineResult<T>> Function(InMemoryPacketResponseRepository value)
    operation,
  ) => _locked(() async {
    final loaded = await _load();
    if (loaded.isFailure) return EngineResult.failure(loaded.error);
    return operation(loaded.value.repository);
  });

  Future<T> _locked<T>(Future<T> Function() operation) {
    final previous = _tail;
    final released = Completer<void>();
    _tail = released.future;
    return () async {
      await previous;
      try {
        return await operation();
      } finally {
        released.complete();
      }
    }();
  }

  Future<
    EngineResult<
      ({int generation, InMemoryPacketResponseRepository repository})
    >
  >
  _load() async {
    try {
      if (!await _rootDirectory.exists()) {
        return EngineResult.success((
          generation: 0,
          repository: InMemoryPacketResponseRepository(),
        ));
      }
      final files = await _rootDirectory
          .list(followLinks: false)
          .where((entity) => entity is File)
          .map((entity) => entity as File)
          .where((file) => _generation(file.path) != null)
          .toList();
      if (files.isEmpty) {
        return EngineResult.success((
          generation: 0,
          repository: InMemoryPacketResponseRepository(),
        ));
      }
      files.sort(
        (left, right) =>
            _generation(left.path)!.compareTo(_generation(right.path)!),
      );
      final file = files.last;
      final generation = _generation(file.path)!;
      final json = Map<String, Object?>.from(
        jsonDecode(await file.readAsString()) as Map,
      );
      return EngineResult.success((
        generation: generation,
        repository: _decode(json),
      ));
    } on Object catch (error) {
      return EngineResult.failure(_storageFailure('read', error));
    }
  }

  Future<EngineResult<bool>> _save(
    PacketRepositorySnapshot snapshot,
    int generation,
  ) async {
    try {
      await _rootDirectory.create(recursive: true);
      final suffix = generation.toString().padLeft(10, '0');
      final target = File(
        '${_rootDirectory.path}${Platform.pathSeparator}state-$suffix.json',
      );
      final staging = File('${target.path}.staging');
      await staging.writeAsString(jsonEncode(_encode(snapshot)), flush: true);
      await staging.rename(target.path);
      return EngineResult.success(true);
    } on Object catch (error) {
      return EngineResult.failure(_storageFailure('write', error));
    }
  }

  int? _generation(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final match = RegExp(r'^state-([0-9]{10})\.json$').firstMatch(name);
    return match == null ? null : int.parse(match.group(1)!);
  }

  Map<String, Object?> _encode(PacketRepositorySnapshot state) => {
    'schemaVersion': 1,
    'nextPacketSequence': state.nextPacketSequence,
    'nextResponseSequence': state.nextResponseSequence,
    'packets': state.packets.map(_encodePacket).toList(),
    'responses': state.responses.map(_encodeResponse).toList(),
  };

  Map<String, Object?> _encodePacket(AnswerSheetPacket packet) => {
    'packetId': packet.packetId.value,
    'templateId': packet.templateId.value,
    'templateVersion': packet.templateVersion.value,
    'createdAt': packet.createdAt.toIso8601String(),
    'status': packet.status.name,
    'responseId': packet.responseId?.value,
    'pages': [
      for (final page in packet.pages)
        {
          'pageId': page.pageId.value,
          'pageIndex': page.pageIndex,
          'totalPages': page.totalPages,
          'identityMarkerIds': page.identityMarkerIds,
        },
    ],
  };

  Map<String, Object?> _encodeResponse(PaperResponse response) => {
    'responseId': response.responseId.value,
    'packetId': response.packetId.value,
    'templateId': response.templateId.value,
    'templateVersion': response.templateVersion.value,
    'source': response.source.name,
    'createdAt': response.createdAt.toIso8601String(),
    'updatedAt': response.updatedAt.toIso8601String(),
    'status': response.status.name,
    'pages': [
      for (final page in response.pageResults.values)
        {
          'pageId': page.pageId.value,
          'pageIndex': page.pageIndex,
          'scannedAt': page.scannedAt.toIso8601String(),
          'questions': [
            for (final question in page.questions)
              {
                'questionId': question.questionId.value,
                'questionNumber': question.questionNumber,
                'state': question.state.name,
                'selectedOptionIds': question.selectedOptionIds
                    .map((id) => id.value)
                    .toList(),
                'numericAnswer': question.numericAnswer,
              },
          ],
        },
    ],
  };

  InMemoryPacketResponseRepository _decode(Map<String, Object?> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported packet repository schema.');
    }
    final packets = [
      for (final raw in (json['packets']! as List))
        _decodePacket(Map<String, Object?>.from(raw as Map)),
    ];
    final responses = [
      for (final raw in (json['responses']! as List))
        _decodeResponse(Map<String, Object?>.from(raw as Map)),
    ];
    return InMemoryPacketResponseRepository.restore(
      nextPacketSequence: json['nextPacketSequence']! as int,
      nextResponseSequence: json['nextResponseSequence']! as int,
      packets: packets,
      responses: responses,
    );
  }

  AnswerSheetPacket _decodePacket(Map<String, Object?> json) {
    final packetId = PacketId(json['packetId']! as String);
    return AnswerSheetPacket(
      packetId: packetId,
      templateId: TemplateId(json['templateId']! as String),
      templateVersion: TemplateVersion(json['templateVersion']! as int),
      createdAt: DateTime.parse(json['createdAt']! as String),
      status: AnswerSheetPacketStatus.values.byName(json['status']! as String),
      responseId: json['responseId'] == null
          ? null
          : ResponseId(json['responseId']! as String),
      pages: [
        for (final raw in (json['pages']! as List))
          _decodePacketPage(packetId, Map<String, Object?>.from(raw as Map)),
      ],
    );
  }

  AnswerSheetPacketPage _decodePacketPage(
    PacketId packetId,
    Map<String, Object?> json,
  ) => AnswerSheetPacketPage(
    packetId: packetId,
    pageId: PageId(json['pageId']! as String),
    pageIndex: json['pageIndex']! as int,
    totalPages: json['totalPages']! as int,
    identityMarkerIds: (json['identityMarkerIds']! as List).cast<int>(),
  );

  PaperResponse _decodeResponse(Map<String, Object?> json) {
    final source = ResponseSource.values.byName(json['source']! as String);
    if (source != ResponseSource.paper) {
      throw const FormatException(
        'Packet repository only decodes paper response records.',
      );
    }
    final pages = <PageId, StoredPacketPageResult>{};
    for (final raw in (json['pages']! as List)) {
      final value = Map<String, Object?>.from(raw as Map);
      final pageId = PageId(value['pageId']! as String);
      pages[pageId] = StoredPacketPageResult(
        pageId: pageId,
        pageIndex: value['pageIndex']! as int,
        scannedAt: DateTime.parse(value['scannedAt']! as String),
        questions: [
          for (final rawQuestion in (value['questions']! as List))
            _decodeQuestion(Map<String, Object?>.from(rawQuestion as Map)),
        ],
      );
    }
    return PaperResponse(
      responseId: ResponseId(json['responseId']! as String),
      packetId: PacketId(json['packetId']! as String),
      templateId: TemplateId(json['templateId']! as String),
      templateVersion: TemplateVersion(json['templateVersion']! as int),
      createdAt: DateTime.parse(json['createdAt']! as String),
      updatedAt: DateTime.parse(json['updatedAt']! as String),
      status: PaperResponseStatus.values.byName(json['status']! as String),
      pageResults: pages,
    );
  }

  StoredQuestionResponse _decodeQuestion(Map<String, Object?> json) =>
      StoredQuestionResponse(
        questionId: QuestionId(json['questionId']! as String),
        questionNumber: json['questionNumber']! as int,
        state: MarkState.values.byName(json['state']! as String),
        selectedOptionIds: (json['selectedOptionIds']! as List)
            .cast<String>()
            .map(OptionId.new),
        numericAnswer: json['numericAnswer'] as String?,
      );

  EngineError _storageFailure(String operation, Object error) => EngineError(
    code: 'PACKET_REPOSITORY_${operation.toUpperCase()}_FAILED',
    message: 'Unable to $operation packet/response state.',
    details: {'cause': error.toString()},
  );
}
