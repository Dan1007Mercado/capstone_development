import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart' as cv;

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../../aruco/domain/image_geometry.dart';
import '../../aruco/domain/page_alignment_result.dart';
import '../../layout/domain/page_layout.dart';
import '../../pdf/domain/template_page_identity_codec.dart';
import '../domain/scanner_identity.dart';
import '../domain/scanner_stages.dart';

/// Worker-isolate-owned QR reader for the already aligned canonical page.
final class OpenCvQrIdentityStage implements ScannerIdentityStage {
  OpenCvQrIdentityStage({ScannerIdentityConfig? config})
    : config = config ?? ScannerIdentityConfig(),
      _detector = cv.QRCodeDetector.empty();

  final ScannerIdentityConfig config;
  final cv.QRCodeDetector _detector;
  bool _disposed = false;

  @override
  EngineResult<ScannerIdentityResult> identify(
    CanonicalPageImage page,
    PageLayout layout,
  ) {
    final stopwatch = Stopwatch()..start();
    final crop = canonicalIdentityCrop(layout, config: config);
    cv.Mat? canonical;
    cv.Mat? cropMat;
    var attempts = 0;
    var lastFactor = 1;
    ScannerIdentitySource? lastSource;
    try {
      if (_disposed) {
        return _failure(
          'SCAN_PAGE_IDENTITY_NOT_FOUND',
          'The page identity detector has already been disposed.',
          stopwatch,
          crop,
          attempts,
          lastFactor,
          lastSource,
        );
      }
      canonical = _canonicalMat(page);
      if (canonical.isEmpty ||
          canonical.width != page.size.width ||
          canonical.height != page.size.height) {
        return _failure(
          'SCAN_PAGE_IDENTITY_NOT_FOUND',
          'The canonical page could not be read for page identity.',
          stopwatch,
          crop,
          attempts,
          lastFactor,
          lastSource,
        );
      }
      cropMat = canonical.region(
        cv.Rect(crop.left, crop.top, crop.width, crop.height),
      );

      for (final factor in config.upscaleFactors) {
        attempts++;
        lastFactor = factor;
        lastSource = factor == 1
            ? ScannerIdentitySource.canonicalCrop
            : ScannerIdentitySource.canonicalUpscaled;
        cv.Mat? attemptImage;
        try {
          attemptImage = factor == 1
              ? cropMat
              : cv.resize(cropMat, (
                  crop.width * factor,
                  crop.height * factor,
                ), interpolation: cv.INTER_CUBIC);
          final decoded = _decode(attemptImage);
          if (decoded.isNotEmpty) {
            return _parse(
              decoded,
              stopwatch,
              crop,
              attempts,
              factor,
              lastSource,
            );
          }
        } finally {
          if (!identical(attemptImage, cropMat)) attemptImage?.dispose();
        }
      }

      if (config.tryFullCanonicalPage) {
        attempts++;
        lastFactor = 1;
        lastSource = ScannerIdentitySource.fullImageFallback;
        final decoded = _decode(canonical);
        if (decoded.isNotEmpty) {
          return _parse(decoded, stopwatch, crop, attempts, 1, lastSource);
        }
      }
      return _failure(
        'SCAN_PAGE_IDENTITY_NOT_FOUND',
        'No readable TalaanScan page identity was found.',
        stopwatch,
        crop,
        attempts,
        lastFactor,
        lastSource,
      );
    } on Object catch (error) {
      return _failure(
        'SCAN_PAGE_IDENTITY_NOT_FOUND',
        'The captured page identity could not be read.',
        stopwatch,
        crop,
        attempts,
        lastFactor,
        lastSource,
        cause: error,
      );
    } finally {
      cropMat?.dispose();
      canonical?.dispose();
    }
  }

  cv.Mat _canonicalMat(CanonicalPageImage page) {
    if (page.grayscaleBytes.isNotEmpty) {
      return cv.Mat.fromList(
        page.size.height,
        page.size.width,
        cv.MatType.CV_8UC1,
        page.grayscaleBytes,
      );
    }
    return cv.imdecode(Uint8List.fromList(page.pngBytes), cv.IMREAD_GRAYSCALE);
  }

  String _decode(cv.Mat image) {
    cv.VecPoint? points;
    cv.Mat? straightCode;
    try {
      final decoded = _detector.detectAndDecode(image);
      points = decoded.$2;
      straightCode = decoded.$3;
      return decoded.$1;
    } finally {
      straightCode?.dispose();
      points?.dispose();
    }
  }

  EngineResult<ScannerIdentityResult> _parse(
    String payload,
    Stopwatch stopwatch,
    CanonicalPixelRect crop,
    int attempts,
    int factor,
    ScannerIdentitySource source,
  ) {
    final decoded = const TemplatePageIdentityCodec().decode(payload);
    stopwatch.stop();
    final diagnostics = _diagnostics(
      stopwatch,
      crop,
      attempts,
      factor,
      source,
      payloadDecoded: true,
    );
    if (decoded.isFailure) {
      return EngineResult.failure(
        EngineError(
          code: 'SCAN_PAGE_IDENTITY_INVALID',
          message: 'The captured page identity is malformed.',
          details: {
            ...diagnostics.toErrorDetails(),
            'causeCode': decoded.error.code,
            'causeMessage': decoded.error.message,
          },
        ),
      );
    }
    return EngineResult.success(
      ScannerIdentityResult(identity: decoded.value, diagnostics: diagnostics),
    );
  }

  EngineResult<ScannerIdentityResult> _failure(
    String code,
    String message,
    Stopwatch stopwatch,
    CanonicalPixelRect crop,
    int attempts,
    int factor,
    ScannerIdentitySource? source, {
    Object? cause,
  }) {
    stopwatch.stop();
    final diagnostics = _diagnostics(
      stopwatch,
      crop,
      attempts,
      factor,
      source,
      payloadDecoded: false,
    );
    return EngineResult.failure(
      EngineError(
        code: code,
        message: message,
        details: {
          ...diagnostics.toErrorDetails(),
          if (cause != null) 'cause': cause.toString(),
        },
      ),
    );
  }

  ScannerIdentityDiagnostics _diagnostics(
    Stopwatch stopwatch,
    CanonicalPixelRect crop,
    int attempts,
    int factor,
    ScannerIdentitySource? source, {
    required bool payloadDecoded,
  }) => ScannerIdentityDiagnostics(
    source: source,
    cropSize: ImageSize(width: crop.width, height: crop.height),
    upscaleFactor: factor,
    payloadDecoded: payloadDecoded,
    processingDuration: stopwatch.elapsed,
    attemptCount: attempts,
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _detector.dispose();
  }
}
