import 'dart:collection';

import '../../../core/ids/identifiers.dart';

final class PacketPageIdentity {
  PacketPageIdentity({
    required this.packetId,
    required this.templateId,
    required this.templateVersion,
    required this.pageId,
    required this.pageIndex,
    required this.totalPages,
    required Iterable<int> identityMarkerIds,
  }) : identityMarkerIds = UnmodifiableListView(List.of(identityMarkerIds));

  final PacketId packetId;
  final TemplateId templateId;
  final TemplateVersion templateVersion;
  final PageId pageId;
  final int pageIndex;
  final int totalPages;
  final List<int> identityMarkerIds;
}

final class PacketScanContext {
  PacketScanContext({required Iterable<PacketPageIdentity> knownPages})
    : knownPages = UnmodifiableListView(List.of(knownPages));

  final List<PacketPageIdentity> knownPages;

  PacketPageIdentity? find(PacketId packetId, int pageIndex) => knownPages
      .where((page) => page.packetId == packetId && page.pageIndex == pageIndex)
      .firstOrNull;
}
