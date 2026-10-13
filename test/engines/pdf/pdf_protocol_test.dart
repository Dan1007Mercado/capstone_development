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

  test('identity codec round-trips delimiters, spaces, and Unicode', () {
    const codec = TemplatePageIdentityCodec();
    final original = TemplatePageIdentity(
      templateId: TemplateId('survey | pagsusulit 日本'),
      templateVersion: TemplateVersion(7),
      pageId: PageId('page | two 📍'),
    );

    final encoded = codec.encode(
      templateId: original.templateId,
      templateVersion: original.templateVersion,
      pageId: original.pageId,
    );
    final decoded = codec.decode(encoded);

    expect(encoded.split('|'), hasLength(4));
    expect(encoded, contains('%7C'));
    expect(encoded, isNot(contains('日本')));
    expect(decoded.isSuccess, isTrue);
    expect(decoded.value, original);
  });

  test(
    'identity codec rejects malformed payloads with structured failures',
    () {
      const codec = TemplatePageIdentityCodec();
      const malformed = [
        '',
        'TS2|survey|1|page',
        'TS1|survey|1',
        'TS1|survey|not-a-version|page',
        'TS1||1|page',
        'TS1|survey|0|page',
        'TS1|survey|1|%ZZ',
        'TS1|survey|1|page|extra',
      ];

      for (final payload in malformed) {
        final result = codec.decode(payload);
        expect(result.isFailure, isTrue, reason: payload);
        expect(result.error.code, 'TEMPLATE_PAGE_IDENTITY_INVALID');
      }
    },
  );

  test('OpenCV DICT_4X4_50 encoder emits stable marker semantics', () {
    const encoder = OpenCvDictionary4x4MarkerEncoder();
    final marker = encoder.encode(10);

    expect(marker.dictionary, ArucoDictionary.openCv4x4_50);
    expect(marker.markerId, 10);
    expect(marker.quietZoneModules, 1);
    expect(marker.markerModules, 6);
    expect(marker.totalModules, 8);
    expect(marker.modules.first, everyElement(isFalse));
    expect(marker.modules.last, everyElement(isFalse));
    expect([
      for (final row in marker.modules) row.first,
    ], everyElement(isFalse));
    expect([for (final row in marker.modules) row.last], everyElement(isFalse));
    expect(marker.modules[1].sublist(1, 7), everyElement(isTrue));
    expect(marker.modules[6].sublist(1, 7), everyElement(isTrue));
  });

  test('only the inner six-module range contains the detectable marker', () {
    final marker = const OpenCvDictionary4x4MarkerEncoder().encode(10);
    final quiet = marker.quietZoneModules;
    final markerEnd = quiet + marker.markerModules;

    for (var row = 0; row < marker.totalModules; row++) {
      for (var column = 0; column < marker.totalModules; column++) {
        final inQuietZone =
            row < quiet ||
            column < quiet ||
            row >= markerEnd ||
            column >= markerEnd;
        if (inQuietZone) expect(marker.modules[row][column], isFalse);
      }
    }
    expect(
      marker.modules[quiet].sublist(quiet, markerEnd),
      everyElement(isTrue),
    );
    expect(
      marker.modules[markerEnd - 1].sublist(quiet, markerEnd),
      everyElement(isTrue),
    );
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
