import 'dart:collection';

import '../../../core/geometry/normalized_geometry.dart';
import '../../../core/geometry/physical_geometry.dart';

final class PacketIdentityMarkerRegion {
  const PacketIdentityMarkerRegion({
    required this.slotIndex,
    required this.markerId,
    required this.physicalBounds,
    required this.normalizedBounds,
  });

  final int slotIndex;
  final int markerId;
  final PhysicalRect physicalBounds;
  final NormalizedRect normalizedBounds;
}

final class PacketHeaderLayout {
  PacketHeaderLayout({
    required Iterable<PacketIdentityMarkerRegion> identityMarkers,
    required this.packetLabelBounds,
    required this.pageLabelBounds,
  }) : identityMarkers = UnmodifiableListView(List.of(identityMarkers));

  final List<PacketIdentityMarkerRegion> identityMarkers;
  final PhysicalRect packetLabelBounds;
  final PhysicalRect pageLabelBounds;
}
