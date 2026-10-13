/// Visual policy only. All positions and OMR dimensions come from PageLayout.
final class PdfRenderStyle {
  const PdfRenderStyle({
    this.headerFontSizePoints = 10,
    this.sectionTitleFontSizePoints = 9,
    this.bodyFontSizePoints = 7,
    this.labelFontSizePoints = 6,
    this.bubbleStrokeWidthPoints = 0.8,
    this.fieldStrokeWidthPoints = 0.6,
    this.diagnosticStrokeWidthPoints = 0.25,
    this.debugOverlays = false,
  });

  final double headerFontSizePoints;
  final double sectionTitleFontSizePoints;
  final double bodyFontSizePoints;
  final double labelFontSizePoints;
  final double bubbleStrokeWidthPoints;
  final double fieldStrokeWidthPoints;
  final double diagnosticStrokeWidthPoints;
  final bool debugOverlays;
}
