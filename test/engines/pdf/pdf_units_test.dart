import 'package:capstone_development/core/geometry/physical_geometry.dart';
import 'package:capstone_development/engines/pdf/domain/pdf_units.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('millimeters convert to PDF points centrally', () {
    expect(PdfUnits.millimetersToPoints(25.4), closeTo(72, 1e-10));
    expect(PdfUnits.millimetersToPoints(210), closeTo(595.2755906, 1e-7));
  });

  test('physical rectangles preserve all dimensions during conversion', () {
    final rect = PhysicalRect.millimeters(
      left: 10,
      top: 20,
      width: 30,
      height: 40,
    );
    final converted = PdfUnits.rectToPoints(rect);

    expect(converted.left, closeTo(28.3464567, 1e-7));
    expect(converted.top, closeTo(56.6929134, 1e-7));
    expect(converted.width, closeTo(85.0393701, 1e-7));
    expect(converted.height, closeTo(113.3858268, 1e-7));
  });
}
