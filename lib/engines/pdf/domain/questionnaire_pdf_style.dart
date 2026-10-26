import 'pdf_units.dart';

/// A4 questionnaire visual and pagination policy.
///
/// Values are converted once into PDF points. They never participate in OMR
/// page geometry.
final class QuestionnairePdfStyle {
  const QuestionnairePdfStyle({
    this.outerMarginMm = 13,
    this.columnGutterMm = 7,
    this.headerGapMm = 4,
    this.footerHeightMm = 8,
    this.titleFontSizePoints = 15,
    this.repeatedTitleFontSizePoints = 10,
    this.identityFontSizePoints = 7,
    this.instructionFontSizePoints = 8.5,
    this.sectionFontSizePoints = 10,
    this.questionFontSizePoints = 9,
    this.optionFontSizePoints = 8.2,
    this.lineHeightFactor = 1.28,
    this.sectionGapPoints = 7,
    this.questionGapPoints = 6,
    this.optionIndentMm = 4,
    this.maxPages = 200,
  });

  final double outerMarginMm;
  final double columnGutterMm;
  final double headerGapMm;
  final double footerHeightMm;
  final double titleFontSizePoints;
  final double repeatedTitleFontSizePoints;
  final double identityFontSizePoints;
  final double instructionFontSizePoints;
  final double sectionFontSizePoints;
  final double questionFontSizePoints;
  final double optionFontSizePoints;
  final double lineHeightFactor;
  final double sectionGapPoints;
  final double questionGapPoints;
  final double optionIndentMm;
  final int maxPages;

  double get outerMarginPoints => PdfUnits.millimetersToPoints(outerMarginMm);
  double get columnGutterPoints => PdfUnits.millimetersToPoints(columnGutterMm);
  double get headerGapPoints => PdfUnits.millimetersToPoints(headerGapMm);
  double get footerHeightPoints => PdfUnits.millimetersToPoints(footerHeightMm);
  double get optionIndentPoints => PdfUnits.millimetersToPoints(optionIndentMm);

  void validate() {
    final positive = [
      outerMarginMm,
      columnGutterMm,
      headerGapMm,
      footerHeightMm,
      titleFontSizePoints,
      repeatedTitleFontSizePoints,
      identityFontSizePoints,
      instructionFontSizePoints,
      sectionFontSizePoints,
      questionFontSizePoints,
      optionFontSizePoints,
      lineHeightFactor,
      sectionGapPoints,
      questionGapPoints,
      optionIndentMm,
    ];
    if (positive.any((value) => !value.isFinite || value <= 0) ||
        maxPages <= 0) {
      throw ArgumentError('Questionnaire PDF style values must be positive.');
    }
  }
}
