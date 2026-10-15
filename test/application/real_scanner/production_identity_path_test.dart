import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production scanner and PDF contain no QR or barcode path', () {
    expect(
      File(
        'lib/engines/scanner/infrastructure/opencv_qr_identity_stage.dart',
      ).existsSync(),
      isFalse,
    );
    final sources = [
      File(
        'lib/application/camera_scanner/infrastructure/'
        'isolate_offline_scanner_runner.dart',
      ).readAsStringSync(),
      File(
        'lib/engines/scanner/infrastructure/offline_scanner_composition.dart',
      ).readAsStringSync(),
      File('lib/engines/pdf/application/pdf_engine.dart').readAsStringSync(),
    ].join('\n').toLowerCase();

    expect(sources, isNot(contains('qrcode')));
    expect(sources, isNot(contains('barcode')));
    expect(sources, isNot(contains('qridentity')));
  });
}
