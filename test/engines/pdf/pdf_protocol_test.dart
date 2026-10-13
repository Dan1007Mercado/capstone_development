import 'package:capstone_development/core/ids/identifiers.dart';
import 'package:capstone_development/engines/pdf/domain/aruco_marker_encoder.dart';
import 'package:capstone_development/engines/pdf/domain/template_page_identity_codec.dart';
import 'package:capstone_development/engines/pdf/infrastructure/opencv_4x4_50_marker_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('identity payload is exact, compact, versioned, and deterministic', () {
    const codec = TemplatePageIdentityCodec();

    final first = codec.encode(
      templateId: TemplateId('survey'),
      templateVersion: TemplateVersion(3),
      pageId: PageId('survey-v3-p2'),
    );
    final second = codec.encode(
      templateId: TemplateId('survey'),
      templateVersion: TemplateVersion(3),
      pageId: PageId('survey-v3-p2'),
    );

    expect(first, 'TS1|survey|3|survey-v3-p2');
    expect(second, first);
  });

  test('OpenCV DICT_4X4_50 encoder emits stable marker semantics', () {
    const encoder = OpenCvDictionary4x4MarkerEncoder();
    final marker = encoder.encode(10);

    expect(marker.dictionary, ArucoDictionary.openCv4x4_50);
    expect(marker.markerId, 10);
    expect(marker.moduleCount, 8);
    expect(marker.modules.first, everyElement(isFalse));
    expect(marker.modules.last, everyElement(isFalse));
    expect([
      for (final row in marker.modules) row.first,
    ], everyElement(isFalse));
    expect([for (final row in marker.modules) row.last], everyElement(isFalse));
    expect(marker.modules[1].sublist(1, 7), everyElement(isTrue));
    expect(marker.modules[6].sublist(1, 7), everyElement(isTrue));
  });

  test('marker payload matches OpenCV canonical codeword for ID 10', () {
    final modules = const OpenCvDictionary4x4MarkerEncoder().encode(10).modules;
    final blackPayload = [
      for (var row = 2; row < 6; row++) modules[row].sublist(2, 6),
    ];

    // OpenCV codeword F9 91: one bits print white, zero bits print black.
    expect(blackPayload, [
      [false, false, false, false],
      [false, true, true, false],
      [false, true, true, false],
      [true, true, true, false],
    ]);
  });

  test('dictionary rejects IDs outside its explicit range', () {
    const encoder = OpenCvDictionary4x4MarkerEncoder();

    expect(() => encoder.encode(-1), throwsRangeError);
    expect(() => encoder.encode(50), throwsRangeError);
  });
}
