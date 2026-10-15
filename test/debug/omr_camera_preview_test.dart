import 'package:capstone_development/debug/omr_camera_preview.dart';
import 'package:capstone_development/debug/p11_1_scanner_validation_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('display preview uses orientation-aware uniform aspect ratios', () {
    expect(
      omrDisplayedPreviewAspectRatio(
        cameraAspectRatio: 16 / 9,
        orientation: Orientation.portrait,
      ),
      closeTo(9 / 16, 1e-12),
    );
    expect(
      omrDisplayedPreviewAspectRatio(
        cameraAspectRatio: 16 / 9,
        orientation: Orientation.landscape,
      ),
      closeTo(16 / 9, 1e-12),
    );
    expect(omrPortraitViewportAspectRatio, 3 / 4);
  });

  test('page guide derives aspect from authoritative PageLayout', () {
    final page = buildP11ScannerValidationSheetInputs().layout.pages.first;

    expect(
      omrPageGuideAspectRatio(page),
      page.pageSpec.size.width.millimeters /
          page.pageSpec.size.height.millimeters,
    );
  });
}
