import 'dart:math' as math;
import 'dart:typed_data';

import 'package:capstone_development/core/geometry/normalized_geometry.dart';
import 'package:capstone_development/core/geometry/page_spec.dart';
import 'package:capstone_development/core/geometry/physical_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/image_geometry.dart';
import 'package:capstone_development/engines/aruco/domain/page_alignment_result.dart';
import 'package:capstone_development/engines/layout/domain/layout_regions.dart';
import 'package:capstone_development/engines/layout/domain/page_layout.dart';
import 'package:capstone_development/engines/pdf/application/pdf_engine.dart';
import 'package:capstone_development/engines/scanner/domain/scanner_identity.dart';
import 'package:capstone_development/engines/scanner/infrastructure/opencv_qr_identity_stage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import '../layout/layout_test_fixtures.dart';

void main() {
  test(
    'identity ROI maps physical geometry with padding to canonical pixels',
    () {
      final page = buildLayout(fullTemplate()).pages.single;
      final crop = canonicalIdentityCrop(page);
      final bounds = page.templateIdentityRegion.physicalBounds;
      final width = page.canonicalPageSpec.widthPixels;
      final height = page.canonicalPageSpec.heightPixels;

      expect(
        crop.left,
        (bounds.left.millimeters * width / 210 - 2 * width / 210).floor(),
      );
      expect(
        crop.top,
        (bounds.top.millimeters * height / 297 - 2 * height / 297).floor(),
      );
      expect(
        crop.width,
        (bounds.right.millimeters * width / 210 + 2 * width / 210).ceil() -
            crop.left,
      );
      expect(crop.width, greaterThan(bounds.width.millimeters * width / 210));
      expect(
        crop.height,
        greaterThan(bounds.height.millimeters * height / 297),
      );
    },
  );

  test('identity ROI padding clamps safely to canonical page bounds', () {
    final original = buildLayout(fullTemplate()).pages.single;
    final page = _withIdentityRegion(
      original,
      TemplateIdentityRegion(
        physicalBounds: PhysicalRect.millimeters(
          left: 0,
          top: 0,
          width: 12,
          height: 12,
        ),
        normalizedBounds: NormalizedRect.values(
          left: 0,
          top: 0,
          width: 12 / 210,
          height: 12 / 297,
        ),
      ),
    );

    final crop = canonicalIdentityCrop(
      page,
      config: ScannerIdentityConfig(paddingMillimeters: 20),
    );

    expect(crop.left, 0);
    expect(crop.top, 0);
    expect(crop.width, lessThanOrEqualTo(page.canonicalPageSpec.widthPixels));
    expect(crop.height, lessThanOrEqualTo(page.canonicalPageSpec.heightPixels));
  });

  test('production PDF TS1 payload decodes from canonical identity crop', () {
    final template = fullTemplate();
    final layout = buildLayout(template);
    final plan = PdfEngine().buildPlan(template, layout).value;
    final page = layout.pages.single;
    final canonical = _canonicalPageWithQr(
      page,
      plan.pages.single.identity.payload,
    );
    final stage = _nativeStageOrSkip();
    if (stage == null) return;
    addTearDown(stage.dispose);

    final result = stage.identify(canonical, page);
    if (_nativeBackendUnavailable(result.errorOrNull?.details['cause'])) {
      markTestSkipped('OpenCV native QR backend is unavailable on this host.');
      return;
    }

    expect(result.isSuccess, isTrue, reason: '${result.errorOrNull?.details}');
    expect(result.value.identity.templateId, template.id);
    expect(result.value.identity.templateVersion, template.version);
    expect(result.value.identity.pageId, page.pageId);
    expect(
      result.value.diagnostics.source,
      anyOf(
        ScannerIdentitySource.canonicalCrop,
        ScannerIdentitySource.canonicalUpscaled,
      ),
    );
  });

  test(
    'bounded upscale attempts recover a small canonical QR when possible',
    () {
      final template = fullTemplate();
      final layout = buildLayout(
        template,
        config: testConfig(
          canonicalPageSpec: CanonicalPageSpec.a4FromWidth(800),
        ),
      );
      final page = layout.pages.single;
      final payload = PdfEngine()
          .buildPlan(template, layout)
          .value
          .pages
          .single
          .identity
          .payload;
      final stage = _nativeStageOrSkip();
      if (stage == null) return;
      addTearDown(stage.dispose);

      final result = stage.identify(_canonicalPageWithQr(page, payload), page);
      if (_nativeBackendUnavailable(result.errorOrNull?.details['cause'])) {
        markTestSkipped(
          'OpenCV native QR backend is unavailable on this host.',
        );
        return;
      }

      expect(
        result.isSuccess,
        isTrue,
        reason: '${result.errorOrNull?.details}',
      );
      expect(result.value.diagnostics.attemptCount, inInclusiveRange(1, 3));
      expect(result.value.diagnostics.upscaleFactor, anyOf(1, 2, 3));
    },
  );

  test('malformed QR and missing QR preserve typed failures', () {
    final page = buildLayout(fullTemplate()).pages.single;
    final malformedStage = _nativeStageOrSkip();
    if (malformedStage == null) return;
    addTearDown(malformedStage.dispose);
    final malformed = malformedStage.identify(
      _canonicalPageWithQr(page, 'not-a-TS1-payload'),
      page,
    );
    if (_nativeBackendUnavailable(malformed.errorOrNull?.details['cause'])) {
      markTestSkipped('OpenCV native QR backend is unavailable on this host.');
      return;
    }
    expect(malformed.error.code, 'SCAN_PAGE_IDENTITY_INVALID');
    expect(malformed.error.details['identityPayloadDecoded'], isTrue);

    final missingStage = _nativeStageOrSkip();
    if (missingStage == null) return;
    addTearDown(missingStage.dispose);
    final missing = missingStage.identify(_blankCanonicalPage(page), page);
    expect(missing.error.code, 'SCAN_PAGE_IDENTITY_NOT_FOUND');
    expect(missing.error.details['identityPayloadDecoded'], isFalse);
  });
}

OpenCvQrIdentityStage? _nativeStageOrSkip() {
  try {
    return OpenCvQrIdentityStage();
  } on Object {
    markTestSkipped('OpenCV native QR backend is unavailable on this host.');
    return null;
  }
}

bool _nativeBackendUnavailable(Object? cause) {
  final text = cause?.toString().toLowerCase() ?? '';
  return text.contains('dynamic library') ||
      text.contains('failed to load') ||
      text.contains('native');
}

CanonicalPageImage _blankCanonicalPage(PageLayout page) {
  final size = ImageSize(
    width: page.canonicalPageSpec.widthPixels,
    height: page.canonicalPageSpec.heightPixels,
  );
  return CanonicalPageImage.ownedGrayscale(
    size: size,
    grayscaleBytes: Uint8List(size.area)..fillRange(0, size.area, 255),
  );
}

CanonicalPageImage _canonicalPageWithQr(PageLayout page, String payload) {
  final canonical = _blankCanonicalPage(page);
  final bounds = page.templateIdentityRegion.physicalBounds;
  final pageWidth = page.pageSpec.size.width.millimeters;
  final pageHeight = page.pageSpec.size.height.millimeters;
  final qrLeft = (bounds.left.millimeters * canonical.size.width / pageWidth)
      .round();
  final qrTop = (bounds.top.millimeters * canonical.size.height / pageHeight)
      .round();
  final qrSize = math
      .min(
        bounds.width.millimeters * canonical.size.width / pageWidth,
        bounds.height.millimeters * canonical.size.height / pageHeight,
      )
      .round();
  final elements = pw.Barcode.qrCode().make(
    payload,
    width: qrSize.toDouble(),
    height: qrSize.toDouble(),
    drawText: false,
  );
  for (final element in elements) {
    if (element is! pw.BarcodeBar || !element.black) continue;
    final left = qrLeft + element.left.floor();
    final top = qrTop + element.top.floor();
    final right = qrLeft + element.right.ceil();
    final bottom = qrTop + element.bottom.ceil();
    for (var y = top; y < bottom; y++) {
      for (var x = left; x < right; x++) {
        if (x >= 0 &&
            x < canonical.size.width &&
            y >= 0 &&
            y < canonical.size.height) {
          canonical.grayscaleBytes[y * canonical.size.width + x] = 0;
        }
      }
    }
  }
  return canonical;
}

PageLayout _withIdentityRegion(
  PageLayout page,
  TemplateIdentityRegion identityRegion,
) => PageLayout(
  templateId: page.templateId,
  templateVersion: page.templateVersion,
  pageId: page.pageId,
  pageIndex: page.pageIndex,
  totalPageCount: page.totalPageCount,
  pageSpec: page.pageSpec,
  canonicalPageSpec: page.canonicalPageSpec,
  physicalPageBounds: page.physicalPageBounds,
  normalizedPageBounds: page.normalizedPageBounds,
  printableBounds: page.printableBounds,
  normalizedPrintableBounds: page.normalizedPrintableBounds,
  safeBounds: page.safeBounds,
  normalizedSafeBounds: page.normalizedSafeBounds,
  markerRegions: page.markerRegions,
  templateIdentityRegion: identityRegion,
  headerRegion: page.headerRegion,
  sectionRegions: page.sectionRegions,
  questionRegions: page.questionRegions,
  bubbleRegions: page.bubbleRegions,
);
