import 'dart:io';

import 'package:capstone_development/debug/p10_camera_test_sheet.dart';

Future<void> main() async {
  final result = await renderP10CameraTestSheetPdf();
  if (result.isFailure) {
    stderr.writeln(
      '${result.error.code}: ${result.error.message} ${result.error.details}',
    );
    exitCode = 1;
    return;
  }

  final output = File(p10CameraTestSheetOutputPath);
  await output.parent.create(recursive: true);
  await output.writeAsBytes(result.value, flush: true);
  stdout.writeln('Generated ${output.path} (${result.value.length} bytes).');
}
