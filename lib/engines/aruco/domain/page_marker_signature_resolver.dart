import 'dart:collection';

import '../../../core/errors/engine_error.dart';
import '../../../core/ids/identifiers.dart';
import '../../../core/protocol/packet_marker_codec.dart';
import '../../../core/result/engine_result.dart';
import '../../layout/domain/layout_config.dart';
import '../../layout/domain/layout_regions.dart';
import '../../layout/domain/page_layout.dart';

final class PageMarkerSignature {
  PageMarkerSignature({required this.pageId, required this.markerIds})
    : ids = UnmodifiableSetView(markerIds.values.toSet()) {
    if (!markerIds.areUnique) {
      throw ArgumentError('A page marker signature must contain unique IDs.');
    }
  }

  factory PageMarkerSignature.fromPage(PageLayout page) {
    final byRole = {
      for (final marker in page.markerRegions) marker.role: marker,
    };
    return PageMarkerSignature(
      pageId: page.pageId,
      markerIds: MarkerIds(
        topLeft: byRole[MarkerRole.topLeft]!.markerId,
        topRight: byRole[MarkerRole.topRight]!.markerId,
        bottomLeft: byRole[MarkerRole.bottomLeft]!.markerId,
        bottomRight: byRole[MarkerRole.bottomRight]!.markerId,
      ),
    );
  }

  final PageId pageId;
  final MarkerIds markerIds;
  final Set<int> ids;
}

final class ResolvedPageMarkerSignature {
  const ResolvedPageMarkerSignature({
    required this.pageId,
    required this.markerIds,
  });

  final PageId pageId;
  final MarkerIds markerIds;
}

final class PageMarkerSignatureResolver {
  PageMarkerSignatureResolver(
    Iterable<PageMarkerSignature> signatures, {
    this.packetMarkerCodec = const PacketMarkerCodec(),
  }) : signatures = UnmodifiableListView(List.of(signatures)) {
    if (this.signatures.isEmpty) {
      throw ArgumentError('At least one page marker signature is required.');
    }
    final used = <int>{};
    for (final signature in this.signatures) {
      if (signature.ids.any((id) => !used.add(id))) {
        throw ArgumentError('Page marker signatures must not collide.');
      }
    }
  }

  factory PageMarkerSignatureResolver.fromPages(Iterable<PageLayout> pages) =>
      PageMarkerSignatureResolver(pages.map(PageMarkerSignature.fromPage));

  final List<PageMarkerSignature> signatures;
  final PacketMarkerCodec packetMarkerCodec;

  EngineResult<ResolvedPageMarkerSignature> resolve(Iterable<int> detectedIds) {
    final allDetected = List<int>.of(detectedIds);
    final registrationIds = signatures
        .expand((signature) => signature.ids)
        .toSet();
    final detected = allDetected
        .where(
          (id) =>
              registrationIds.contains(id) ||
              !packetMarkerCodec.isIdentityMarkerId(id),
        )
        .toList(growable: false);
    if (detected.toSet().length != detected.length) {
      return _failure(
        'SCAN_DUPLICATE_PAGE_MARKERS',
        'A page marker ID was detected more than once.',
        detected,
      );
    }
    final ids = detected.toSet();
    final exact = signatures.where(
      (signature) => _setEquals(ids, signature.ids),
    );
    if (exact.length == 1) {
      final signature = exact.single;
      return EngineResult.success(
        ResolvedPageMarkerSignature(
          pageId: signature.pageId,
          markerIds: signature.markerIds,
        ),
      );
    }
    if (ids.isEmpty ||
        signatures.any((signature) => signature.ids.containsAll(ids))) {
      return _failure(
        'SCAN_PAGE_MARKERS_INCOMPLETE',
        'All four markers for one selected-template page are required.',
        detected,
      );
    }
    return _failure(
      'SCAN_UNKNOWN_PAGE_MARKERS',
      'The detected marker set does not belong to the selected template version.',
      detected,
    );
  }

  bool _setEquals(Set<int> left, Set<int> right) =>
      left.length == right.length && left.containsAll(right);

  EngineResult<ResolvedPageMarkerSignature> _failure(
    String code,
    String message,
    List<int> detected,
  ) => EngineResult.failure(
    EngineError(
      code: code,
      message: message,
      details: {'detectedMarkerIds': detected..sort()},
    ),
  );
}
