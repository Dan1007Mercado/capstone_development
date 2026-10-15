import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/errors/engine_error.dart';
import '../../../core/result/engine_result.dart';
import '../domain/pdf_render_fonts.dart';

/// Loads the bundled Apache-2.0 Roboto fonts without network access.
final class BundledPdfRenderFontLoader implements PdfRenderFontLoader {
  BundledPdfRenderFontLoader({AssetBundle? bundle}) : _bundle = bundle;

  static const regularAsset = 'assets/fonts/Roboto-Regular.ttf';
  static const boldAsset = 'assets/fonts/Roboto-Bold.ttf';
  static const symbolsAsset = 'assets/fonts/NotoSansSymbols2-Regular.ttf';

  final AssetBundle? _bundle;

  @override
  Future<EngineResult<PdfRenderFonts>> load() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final bundle = _bundle ?? rootBundle;
      final results = await Future.wait([
        bundle.load(regularAsset),
        bundle.load(boldAsset),
        bundle.load(symbolsAsset),
      ]);
      return EngineResult.success(
        PdfRenderFonts(
          regular: pw.Font.ttf(results[0]),
          bold: pw.Font.ttf(results[1]),
          fallback: [pw.Font.ttf(results[2])],
        ),
      );
    } on Object catch (error) {
      return EngineResult.failure(
        EngineError(
          code: 'PDF_FONT_LOAD_FAILED',
          message: 'Unable to load the bundled Unicode PDF fonts.',
          details: {'cause': error.toString()},
        ),
      );
    }
  }
}
