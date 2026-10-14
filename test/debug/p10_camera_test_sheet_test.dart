import 'dart:convert';

import 'package:capstone_development/debug/p10_camera_test_sheet.dart';
import 'package:capstone_development/debug/p5_native_validation_fixture.dart';
import 'package:capstone_development/engines/pdf/application/pdf_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'test sheet plan preserves authoritative PageLayout marker geometry',
    () {
      final inputs = buildP10CameraTestSheetInputs();
      final page = inputs.layout.pages.single;
      final authoritative = buildP5NativeValidationPage();
      final plan = PdfEngine()
          .buildPlan(inputs.template, inputs.layout)
          .value
          .pages
          .single;

      expect(inputs.template.name, 'P10 Camera Validation Sheet');
      expect(page.pageSpec.size.width.millimeters, 210);
      expect(page.pageSpec.size.height.millimeters, 297);
      expect(
        plan.markers.map((marker) => marker.region.markerId),
        p5NativeValidationExpectedMarkerIds,
      );
      for (var index = 0; index < plan.markers.length; index++) {
        expect(
          plan.markers[index].region.physicalBounds,
          authoritative.markerRegions[index].physicalBounds,
        );
        expect(
          plan.markers[index].region.physicalMarkerBounds,
          authoritative.markerRegions[index].physicalMarkerBounds,
        );
        expect(
          plan.markers[index].region.physicalRegistrationPoint,
          authoritative.markerRegions[index].physicalRegistrationPoint,
        );
      }
    },
  );

  test('test sheet renders one printable PDF page', () async {
    final result = await renderP10CameraTestSheetPdf();

    expect(result.isSuccess, isTrue);
    expect(ascii.decode(result.value.take(5).toList()), '%PDF-');
    expect(latin1.decode(result.value), contains('/Count 1'));
  });
}
