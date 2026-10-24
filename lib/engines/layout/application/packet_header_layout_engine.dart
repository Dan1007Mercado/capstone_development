import 'dart:math' as math;

import '../../../core/errors/engine_error.dart';
import '../../../core/geometry/geometry_converter.dart';
import '../../../core/geometry/physical_geometry.dart';
import '../../../core/protocol/packet_marker_codec.dart';
import '../../../core/result/engine_result.dart';
import '../domain/packet_header_layout.dart';
import '../domain/page_layout.dart';

/// Derives packet-only header geometry from an immutable [PageLayout].
///
/// This does not move or replace any published layout region.
final class PacketHeaderLayoutEngine {
  const PacketHeaderLayoutEngine({
    this.markerSizeMm = 10,
    this.markerGapMm = 2,
    this.registrationClearanceMm = 2,
  });

  final double markerSizeMm;
  final double markerGapMm;
  final double registrationClearanceMm;

  EngineResult<PacketHeaderLayout> build(
    PageLayout page,
    List<int> identityMarkerIds,
  ) {
    if (identityMarkerIds.length != PacketMarkerCodec.markerCount ||
        identityMarkerIds.any(
          (id) =>
              id < PacketMarkerCodec.minimumIdentityMarkerId ||
              id > PacketMarkerCodec.maximumIdentityMarkerId,
        )) {
      return _failure(
        'PACKET_HEADER_IDENTITY_INVALID',
        'Header marker IDs do not match the packet marker contract.',
      );
    }
    final values = [markerSizeMm, markerGapMm, registrationClearanceMm];
    if (values.any((value) => !value.isFinite || value <= 0)) {
      return _failure(
        'PACKET_HEADER_CONFIG_INVALID',
        'Packet header dimensions must be finite and positive.',
      );
    }

    final pageWidth = page.pageSpec.size.width.millimeters;
    final groupWidth =
        PacketMarkerCodec.markerCount * markerSizeMm +
        (PacketMarkerCodec.markerCount - 1) * markerGapMm;
    final left = (pageWidth - groupWidth) / 2;
    final top = page.printableBounds.top.millimeters;
    final markerRegions = [
      for (var index = 0; index < identityMarkerIds.length; index++)
        _marker(
          page,
          index,
          identityMarkerIds[index],
          PhysicalRect.millimeters(
            left: left + index * (markerSizeMm + markerGapMm),
            top: top,
            width: markerSizeMm,
            height: markerSizeMm,
          ),
        ),
    ];
    final groupRight = left + groupWidth;
    final topRegistration = page.markerRegions.where(
      (marker) =>
          marker.physicalBounds.top.millimeters <
          page.safeBounds.top.millimeters,
    );
    final allBounds = markerRegions.map((marker) => marker.physicalBounds);
    final invalid = allBounds.any(
      (bounds) =>
          !page.printableBounds.containsRect(bounds) ||
          page.bubbleRegions.any(
            (bubble) => bounds.intersects(bubble.physicalBounds),
          ) ||
          page.questionRegions.any(
            (question) => bounds.intersects(question.physicalBounds),
          ) ||
          topRegistration.any(
            (registration) =>
                bounds.intersects(registration.physicalBounds) ||
                _clearance(bounds, registration.physicalBounds) <
                    registrationClearanceMm,
          ),
    );
    if (invalid) {
      return _failure(
        'PACKET_HEADER_GEOMETRY_INVALID',
        'Packet identity markers collide with published page geometry.',
        {'pageId': page.pageId.value},
      );
    }

    final labelTop = top;
    final labelHeight = markerSizeMm;
    final leftLabelRight = left - markerGapMm;
    final rightLabelLeft = groupRight + markerGapMm;
    final packetLabelBounds = PhysicalRect.millimeters(
      left: page.printableBounds.left.millimeters,
      top: labelTop,
      width: leftLabelRight - page.printableBounds.left.millimeters,
      height: labelHeight,
    );
    final pageLabelBounds = PhysicalRect.millimeters(
      left: rightLabelLeft,
      top: labelTop,
      width: page.printableBounds.right.millimeters - rightLabelLeft,
      height: labelHeight,
    );
    return EngineResult.success(
      PacketHeaderLayout(
        identityMarkers: markerRegions,
        packetLabelBounds: packetLabelBounds,
        pageLabelBounds: pageLabelBounds,
      ),
    );
  }

  PacketIdentityMarkerRegion _marker(
    PageLayout page,
    int slotIndex,
    int markerId,
    PhysicalRect bounds,
  ) => PacketIdentityMarkerRegion(
    slotIndex: slotIndex,
    markerId: markerId,
    physicalBounds: bounds,
    normalizedBounds: GeometryConverter.physicalRectToNormalized(
      bounds,
      page.pageSpec.size,
    ),
  );

  static double _clearance(PhysicalRect first, PhysicalRect second) {
    final horizontal = math.max(
      0,
      math.max(
        second.left.millimeters - first.right.millimeters,
        first.left.millimeters - second.right.millimeters,
      ),
    );
    final vertical = math.max(
      0,
      math.max(
        second.top.millimeters - first.bottom.millimeters,
        first.top.millimeters - second.bottom.millimeters,
      ),
    );
    return math.sqrt(horizontal * horizontal + vertical * vertical);
  }

  EngineResult<PacketHeaderLayout> _failure(
    String code,
    String message, [
    Map<String, Object?> details = const {},
  ]) => EngineResult.failure(
    EngineError(code: code, message: message, details: details),
  );
}
