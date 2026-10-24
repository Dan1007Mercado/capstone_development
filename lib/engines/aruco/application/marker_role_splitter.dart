import 'dart:collection';

import '../../../core/protocol/packet_marker_codec.dart';
import '../domain/detected_marker.dart';

final class MarkerRoleSplit {
  MarkerRoleSplit({
    required Iterable<DetectedMarker> registrationMarkers,
    required Iterable<DetectedMarker> identityMarkers,
    required Iterable<DetectedMarker> unrelatedMarkers,
  }) : registrationMarkers = UnmodifiableListView(List.of(registrationMarkers)),
       identityMarkers = UnmodifiableListView(List.of(identityMarkers)),
       unrelatedMarkers = UnmodifiableListView(List.of(unrelatedMarkers));

  final List<DetectedMarker> registrationMarkers;
  final List<DetectedMarker> identityMarkers;
  final List<DetectedMarker> unrelatedMarkers;
}

final class MarkerRoleSplitter {
  const MarkerRoleSplitter({this.packetCodec = const PacketMarkerCodec()});

  final PacketMarkerCodec packetCodec;

  MarkerRoleSplit split(
    Iterable<DetectedMarker> markers,
    Set<int> registrationMarkerIds,
  ) {
    final registration = <DetectedMarker>[];
    final identity = <DetectedMarker>[];
    final unrelated = <DetectedMarker>[];
    for (final marker in markers) {
      if (registrationMarkerIds.contains(marker.id)) {
        registration.add(marker);
      } else if (packetCodec.isIdentityMarkerId(marker.id)) {
        identity.add(marker);
      } else {
        unrelated.add(marker);
      }
    }
    return MarkerRoleSplit(
      registrationMarkers: registration,
      identityMarkers: identity,
      unrelatedMarkers: unrelated,
    );
  }
}
