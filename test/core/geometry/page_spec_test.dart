import 'package:capstone_development/core/geometry/page_spec.dart';
import 'package:capstone_development/core/geometry/physical_geometry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('A4 portrait uses exact millimeter dimensions', () {
    final spec = PageSpec.a4Portrait();
    expect(spec.size.width.millimeters, 210);
    expect(spec.size.height.millimeters, 297);
    expect(spec.orientation, PageOrientation.portrait);
  });

  test('A4 landscape swaps the exact millimeter dimensions', () {
    final spec = PageSpec.a4Landscape();
    expect(spec.size.width.millimeters, 297);
    expect(spec.size.height.millimeters, 210);
    expect(spec.orientation, PageOrientation.landscape);
  });

  test('PageMargins calculates the content rectangle', () {
    final margins = PageMargins(
      top: PhysicalLength(20),
      right: PhysicalLength(15),
      bottom: PhysicalLength(25),
      left: PhysicalLength(10),
    );
    expect(
      margins.contentRect(PageSpec.a4Portrait().size),
      PhysicalRect.millimeters(left: 10, top: 20, width: 185, height: 252),
    );
  });

  test('PageMargins rejects a consumed content area', () {
    final margins = PageMargins(
      top: PhysicalLength(50),
      right: PhysicalLength(100),
      bottom: PhysicalLength(50),
      left: PhysicalLength(100),
    );
    expect(
      () => margins.contentRect(PhysicalSize.millimeters(200, 100)),
      throwsRangeError,
    );
  });

  test('CanonicalPageSpec requires positive pixel dimensions', () {
    expect(
      () => CanonicalPageSpec(widthPixels: 0, heightPixels: 100),
      throwsRangeError,
    );
    expect(
      () => CanonicalPageSpec(widthPixels: 100, heightPixels: -1),
      throwsRangeError,
    );
  });

  test('canonical helpers preserve the A4 aspect ratio', () {
    final fromWidth = CanonicalPageSpec.a4FromWidth(2100);
    final fromHeight = CanonicalPageSpec.a4FromHeight(2970);
    final landscape = CanonicalPageSpec.a4FromWidth(
      2970,
      orientation: PageOrientation.landscape,
    );

    expect(fromWidth, CanonicalPageSpec(widthPixels: 2100, heightPixels: 2970));
    expect(
      fromHeight,
      CanonicalPageSpec(widthPixels: 2100, heightPixels: 2970),
    );
    expect(landscape, CanonicalPageSpec(widthPixels: 2970, heightPixels: 2100));
  });
}
