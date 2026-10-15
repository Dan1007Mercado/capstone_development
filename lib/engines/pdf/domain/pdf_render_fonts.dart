import 'package:pdf/widgets.dart' as pw;

import '../../../core/result/engine_result.dart';

/// Fonts embedded into a rendered PDF document.
final class PdfRenderFonts {
  const PdfRenderFonts({
    required this.regular,
    required this.bold,
    this.fallback = const [],
  });

  final pw.Font regular;
  final pw.Font bold;
  final List<pw.Font> fallback;
}

/// Loads reusable font objects for one PDF render operation.
abstract interface class PdfRenderFontLoader {
  Future<EngineResult<PdfRenderFonts>> load();
}
