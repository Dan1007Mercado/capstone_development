import 'dart:math' as math;

import '../../../core/errors/engine_error.dart';
import '../../../core/protocol/packet_marker_codec.dart';
import '../../../core/result/engine_result.dart';
import '../../aruco/application/marker_role_splitter.dart';
import '../../aruco/domain/image_geometry.dart';
import '../../aruco/domain/page_alignment_result.dart';
import '../../layout/application/packet_header_layout_engine.dart';
import '../../layout/domain/page_layout.dart';
import '../domain/packet_scan_identity.dart';

final class PacketIdentityResolver {
  const PacketIdentityResolver({
    this.codec = const PacketMarkerCodec(),
    this.roleSplitter = const MarkerRoleSplitter(),
    this.headerLayoutEngine = const PacketHeaderLayoutEngine(),
  });

  final PacketMarkerCodec codec;
  final MarkerRoleSplitter roleSplitter;
  final PacketHeaderLayoutEngine headerLayoutEngine;

  EngineResult<PacketPageIdentity> resolve({
    required PageAlignmentResult alignment,
    required PageLayout page,
    required PacketScanContext context,
  }) {
    final registrationIds = page.markerRegions
        .map((marker) => marker.markerId)
        .toSet();
    final split = roleSplitter.split(
      alignment.detectedMarkers,
      registrationIds,
    );
    if (split.identityMarkers.length < PacketMarkerCodec.markerCount) {
      return _failure(
        'PACKET_IDENTITY_MISSING',
        'One or more packet identity markers were not detected.',
        {'detectedCount': split.identityMarkers.length},
      );
    }
    if (split.identityMarkers.length > PacketMarkerCodec.markerCount) {
      return _failure(
        'PACKET_IDENTITY_MARKER_COUNT_INVALID',
        'Too many packet identity markers were detected.',
        {'detectedCount': split.identityMarkers.length},
      );
    }
    final projected = [
      for (final marker in split.identityMarkers)
        (marker: marker, center: alignment.homography.project(marker.center)),
    ]..sort((left, right) => left.center.x.compareTo(right.center.x));
    final provisional = headerLayoutEngine.build(
      page,
      List.filled(PacketMarkerCodec.markerCount, 0),
    );
    if (provisional.isFailure) return EngineResult.failure(provisional.error);
    final expected = provisional.value.identityMarkers;
    for (var index = 0; index < projected.length; index++) {
      final bounds = expected[index].physicalBounds;
      final expectedCenter = ImagePoint(
        bounds.center.x.millimeters /
            page.pageSpec.size.width.millimeters *
            page.canonicalPageSpec.widthPixels,
        bounds.center.y.millimeters /
            page.pageSpec.size.height.millimeters *
            page.canonicalPageSpec.heightPixels,
      );
      final markerWidthPixels =
          bounds.width.millimeters /
          page.pageSpec.size.width.millimeters *
          page.canonicalPageSpec.widthPixels;
      if (projected[index].center.distanceTo(expectedCenter) >
          math.max(12, markerWidthPixels * 1.5)) {
        return _failure(
          'PACKET_IDENTITY_GEOMETRY_INVALID',
          'Identity marker does not match its reserved header slot.',
          {'slotIndex': index, 'markerId': projected[index].marker.id},
        );
      }
    }
    final decoded = codec.decode(projected.map((item) => item.marker.id));
    if (decoded.isFailure) return EngineResult.failure(decoded.error);
    final identity = context.find(
      decoded.value.packetId,
      decoded.value.pageIndex,
    );
    if (identity == null) {
      return _failure(
        'PACKET_NOT_FOUND',
        'Decoded packet/page identity is not in the offline catalog.',
        {
          'packetId': decoded.value.packetId.value,
          'pageIndex': decoded.value.pageIndex,
        },
      );
    }
    if (identity.templateId != page.templateId ||
        identity.templateVersion != page.templateVersion ||
        identity.pageId != page.pageId ||
        identity.pageIndex != page.pageIndex ||
        identity.totalPages != page.totalPageCount ||
        !_sameIds(identity.identityMarkerIds, decoded.value.markerIds)) {
      return _failure(
        'PACKET_PAGE_IDENTITY_MISMATCH',
        'Packet identity and registration PageLayout do not agree.',
        {
          'packetId': identity.packetId.value,
          'identityPageId': identity.pageId.value,
          'registrationPageId': page.pageId.value,
        },
      );
    }
    return EngineResult.success(identity);
  }

  bool _sameIds(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  EngineResult<PacketPageIdentity> _failure(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );
}
