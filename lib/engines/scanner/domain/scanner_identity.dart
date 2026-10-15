import 'dart:math' as math;

import '../../../core/errors/engine_error.dart';
import '../../../core/ids/identifiers.dart';
import '../../../core/result/engine_result.dart';
import '../../aruco/domain/image_geometry.dart';
import '../../layout/domain/page_layout.dart';
import '../../pdf/domain/template_page_identity_codec.dart';

enum ScannerIdentitySource {
  canonicalCrop,
  canonicalUpscaled,
  fullImageFallback,
}

final class CanonicalPixelRect {
  const CanonicalPixelRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final int left;
  final int top;
  final int width;
  final int height;
}

final class ScannerIdentityConfig {
  ScannerIdentityConfig({
    this.paddingMillimeters = 2,
    this.upscaleFactors = const [1, 2, 3],
    this.tryFullCanonicalPage = true,
  }) {
    if (!paddingMillimeters.isFinite || paddingMillimeters < 0) {
      throw RangeError.value(paddingMillimeters, 'paddingMillimeters');
    }
    if (upscaleFactors.isEmpty ||
        upscaleFactors.first != 1 ||
        upscaleFactors.any((factor) => factor <= 0)) {
      throw ArgumentError.value(
        upscaleFactors,
        'upscaleFactors',
        'Must be non-empty, positive, and start with the original scale.',
      );
    }
  }

  /// Physical padding retained around the authoritative identity region so
  /// the QR quiet zone survives rounding and canonical-page interpolation.
  final double paddingMillimeters;
  final List<int> upscaleFactors;
  final bool tryFullCanonicalPage;
}

final class ScannerIdentityDiagnostics {
  const ScannerIdentityDiagnostics({
    required this.source,
    required this.cropSize,
    required this.upscaleFactor,
    required this.payloadDecoded,
    required this.processingDuration,
    required this.attemptCount,
  });

  final ScannerIdentitySource? source;
  final ImageSize cropSize;
  final int upscaleFactor;
  final bool payloadDecoded;
  final Duration processingDuration;
  final int attemptCount;

  Map<String, Object?> toErrorDetails() => {
    'identitySource': source?.name,
    'identityCropWidth': cropSize.width,
    'identityCropHeight': cropSize.height,
    'identityUpscaleFactor': upscaleFactor,
    'identityPayloadDecoded': payloadDecoded,
    'identityDurationMs': processingDuration.inMicroseconds / 1000,
    'identityAttemptCount': attemptCount,
  };
}

final class ScannerIdentityResult {
  const ScannerIdentityResult({
    required this.identity,
    required this.diagnostics,
  });

  final TemplatePageIdentity identity;
  final ScannerIdentityDiagnostics diagnostics;
}

CanonicalPixelRect canonicalIdentityCrop(
  PageLayout page, {
  ScannerIdentityConfig? config,
}) {
  final resolvedConfig = config ?? ScannerIdentityConfig();
  final bounds = page.templateIdentityRegion.physicalBounds;
  final pageWidthMm = page.pageSpec.size.width.millimeters;
  final pageHeightMm = page.pageSpec.size.height.millimeters;
  final width = page.canonicalPageSpec.widthPixels;
  final height = page.canonicalPageSpec.heightPixels;
  final paddingX = resolvedConfig.paddingMillimeters * width / pageWidthMm;
  final paddingY = resolvedConfig.paddingMillimeters * height / pageHeightMm;
  final left = math.max(
    0,
    (bounds.left.millimeters * width / pageWidthMm - paddingX).floor(),
  );
  final top = math.max(
    0,
    (bounds.top.millimeters * height / pageHeightMm - paddingY).floor(),
  );
  final right = math.min(
    width,
    (bounds.right.millimeters * width / pageWidthMm + paddingX).ceil(),
  );
  final bottom = math.min(
    height,
    (bounds.bottom.millimeters * height / pageHeightMm + paddingY).ceil(),
  );
  return CanonicalPixelRect(
    left: left,
    top: top,
    width: right - left,
    height: bottom - top,
  );
}

EngineResult<bool> validateTemplatePageIdentity({
  required TemplatePageIdentity actual,
  required TemplateId expectedTemplateId,
  required TemplateVersion expectedTemplateVersion,
  required PageId expectedPageId,
}) {
  if (actual.templateId != expectedTemplateId) {
    return _identityFailure(
      code: 'SCAN_TEMPLATE_ID_MISMATCH',
      message: 'The captured sheet belongs to a different template.',
      actual: actual,
      expectedTemplateId: expectedTemplateId,
      expectedTemplateVersion: expectedTemplateVersion,
      expectedPageId: expectedPageId,
    );
  }
  if (actual.templateVersion != expectedTemplateVersion) {
    return _identityFailure(
      code: 'SCAN_TEMPLATE_VERSION_MISMATCH',
      message: 'The captured sheet belongs to a different template version.',
      actual: actual,
      expectedTemplateId: expectedTemplateId,
      expectedTemplateVersion: expectedTemplateVersion,
      expectedPageId: expectedPageId,
    );
  }
  if (actual.pageId != expectedPageId) {
    return _identityFailure(
      code: 'SCAN_PAGE_ID_MISMATCH',
      message: 'The captured sheet is not the expected page.',
      actual: actual,
      expectedTemplateId: expectedTemplateId,
      expectedTemplateVersion: expectedTemplateVersion,
      expectedPageId: expectedPageId,
    );
  }
  return EngineResult.success(true);
}

EngineResult<bool> _identityFailure({
  required String code,
  required String message,
  required TemplatePageIdentity actual,
  required TemplateId expectedTemplateId,
  required TemplateVersion expectedTemplateVersion,
  required PageId expectedPageId,
}) => EngineResult.failure(
  EngineError(
    code: code,
    message: message,
    details: {
      'expectedTemplateId': expectedTemplateId.value,
      'actualTemplateId': actual.templateId.value,
      'expectedTemplateVersion': expectedTemplateVersion.value,
      'actualTemplateVersion': actual.templateVersion.value,
      'expectedPageId': expectedPageId.value,
      'actualPageId': actual.pageId.value,
    },
  ),
);
