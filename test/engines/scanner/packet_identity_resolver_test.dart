import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/core/protocol/packet_marker_codec.dart';
import 'package:capstone_development/debug/p11_1_scanner_validation_sheet.dart';
import 'package:capstone_development/engines/aruco/domain/detected_marker.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/aruco/domain/marker_correspondence.dart';
import 'package:capstone_development/engines/layout/application/packet_header_layout_engine.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/scanner/application/packet_identity_resolver.dart';
import 'package:capstone_development/engines/scanner/domain/packet_scan_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves packet page from header detections and stored PageLayout', () {
    final pages = buildP11ScannerValidationSheetInputs().layout.pages;
    final page = pages.first;
    final identity = _identity(page, packetSequence: 71);

    final result = const PacketIdentityResolver().resolve(
      alignment: _alignment(page, identity.identityMarkerIds),
      page: page,
      context: PacketScanContext(knownPages: [identity]),
    );

    expect(result.isSuccess, isTrue, reason: result.errorOrNull?.toString());
    expect(result.value.packetId, identity.packetId);
    expect(result.value.pageId, page.pageId);
  });

  test('missing identity marker returns typed failure', () {
    final page = buildP11ScannerValidationSheetInputs().layout.pages.first;
    final identity = _identity(page, packetSequence: 72);
    final detected = identity.identityMarkerIds.take(3).toList();

    final result = const PacketIdentityResolver().resolve(
      alignment: _alignment(page, detected),
      page: page,
      context: PacketScanContext(knownPages: [identity]),
    );

    expect(result.error.code, 'PACKET_IDENTITY_MISSING');
  });

  test('extra identity marker returns typed failure', () {
    final page = buildP11ScannerValidationSheetInputs().layout.pages.first;
    final identity = _identity(page, packetSequence: 73);

    final result = const PacketIdentityResolver().resolve(
      alignment: _alignment(page, [...identity.identityMarkerIds, 9]),
      page: page,
      context: PacketScanContext(knownPages: [identity]),
    );

    expect(result.error.code, 'PACKET_IDENTITY_MARKER_COUNT_INVALID');
  });

  test('identity page and registration PageLayout mismatch is rejected', () {
    final pages = buildP11ScannerValidationSheetInputs().layout.pages;
    final registrationPage = pages.first;
    final packetId = PacketId.fromSequence(74);
    final markerIds = const PacketMarkerCodec()
        .encode(packetId: packetId, pageIndex: 0)
        .value
        .markerIds;
    final mismatched = PacketPageIdentity(
      packetId: packetId,
      templateId: registrationPage.templateId,
      templateVersion: registrationPage.templateVersion,
      pageId: pages[1].pageId,
      pageIndex: 0,
      totalPages: registrationPage.totalPageCount,
      identityMarkerIds: markerIds,
    );

    final result = const PacketIdentityResolver().resolve(
      alignment: _alignment(registrationPage, markerIds),
      page: registrationPage,
      context: PacketScanContext(knownPages: [mismatched]),
    );

    expect(result.error.code, 'PACKET_PAGE_IDENTITY_MISMATCH');
  });
}

PacketPageIdentity _identity(PageLayout page, {required int packetSequence}) {
  final packetId = PacketId.fromSequence(packetSequence);
  final markers = const PacketMarkerCodec()
      .encode(packetId: packetId, pageIndex: page.pageIndex)
      .value
      .markerIds;
  return PacketPageIdentity(
    packetId: packetId,
    templateId: page.templateId,
    templateVersion: page.templateVersion,
    pageId: page.pageId,
    pageIndex: page.pageIndex,
    totalPages: page.totalPageCount,
    identityMarkerIds: markers,
  );
}

PageAlignmentResult _alignment(PageLayout page, List<int> markerIds) {
  final header = const PacketHeaderLayoutEngine()
      .build(page, List.filled(PacketMarkerCodec.markerCount, 0))
      .value;
  final markers = <DetectedMarker>[];
  for (var index = 0; index < markerIds.length; index++) {
    final slot = header.identityMarkers[index % header.identityMarkers.length];
    final center = slot.physicalBounds.center;
    final x =
        center.x.millimeters /
        page.pageSpec.size.width.millimeters *
        page.canonicalPageSpec.widthPixels;
    final y =
        center.y.millimeters /
        page.pageSpec.size.height.millimeters *
        page.canonicalPageSpec.heightPixels;
    markers.add(_marker(markerIds[index], x, y));
  }
  final size = ImageSize(
    width: page.canonicalPageSpec.widthPixels,
    height: page.canonicalPageSpec.heightPixels,
  );
  return PageAlignmentResult(
    canonicalPage: CanonicalPageImage(size: size),
    homography: HomographyMatrix([1, 0, 0, 0, 1, 0, 0, 0, 1]),
    observations: const [],
    correspondences: const [],
    detectedMarkers: markers,
    diagnostics: PageAlignmentDiagnostics(
      expectedMarkerIds: page.markerRegions.map((marker) => marker.markerId),
      detectedMarkerIds: markers.map((marker) => marker.id),
      sourceMarkerSideLengths: const [],
      sourceRegistrationPoints: const [],
      destinationRegistrationPoints: const [],
      registrationQuality: const RegistrationQuality(
        quadrilateralAreaRatio: 0.5,
        minimumMarkerSidePixels: 20,
        maximumPerspectiveRatio: 1,
      ),
      reprojectionErrors: const [],
      meanReprojectionError: 0,
      maxReprojectionError: 0,
      processingDuration: Duration.zero,
    ),
  );
}

DetectedMarker _marker(int id, double centerX, double centerY) =>
    DetectedMarker(
      id: id,
      topLeft: ImagePoint(centerX - 5, centerY - 5),
      topRight: ImagePoint(centerX + 5, centerY - 5),
      bottomRight: ImagePoint(centerX + 5, centerY + 5),
      bottomLeft: ImagePoint(centerX - 5, centerY + 5),
    );
