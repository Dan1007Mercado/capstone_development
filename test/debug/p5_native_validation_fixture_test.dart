import 'package:capstone_development/debug/p5_native_validation_fixture.dart';
import 'package:capstone_development/debug/p5_native_validation_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;

void main() {
  test(
    'fixture uses the expected marker protocol and canonical dimensions',
    () {
      final page = buildP5NativeValidationPage();
      final generated = renderP5NativeValidationPng(page);
      final decoded = image.decodePng(generated);

      expect(
        page.markerRegions.map((marker) => marker.markerId),
        p5NativeValidationExpectedMarkerIds,
      );
      expect(decoded, isNotNull);
      expect(decoded!.width, page.canonicalPageSpec.widthPixels);
      expect(decoded.height, page.canonicalPageSpec.heightPixels);
    },
  );

  test('in-memory PNG generation is deterministic', () {
    final page = buildP5NativeValidationPage();

    expect(
      renderP5NativeValidationPng(page),
      renderP5NativeValidationPng(page),
    );
  });

  test('report formatting prefixes every line', () {
    final report = P5NativeValidationReport(
      lines: const ['backend=success', 'verdict=PASS'],
      passed: true,
    );

    expect(
      report.text,
      '[P5_NATIVE] backend=success\n[P5_NATIVE] verdict=PASS',
    );
  });
}
