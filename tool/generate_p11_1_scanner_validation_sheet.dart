import 'dart:io';

import 'package:capstone_development/debug/p11_1_scanner_validation_sheet.dart';

Future<void> main() async {
  final inputs = buildP11ScannerValidationSheetInputs();
  final result = await renderP11ScannerValidationSheetPdf();
  if (result.isFailure) {
    stderr.writeln(
      '${result.error.code}: ${result.error.message} ${result.error.details}',
    );
    exitCode = 1;
    return;
  }
  final output = File(p11ScannerValidationSheetOutputPath);
  await output.parent.create(recursive: true);
  await output.writeAsBytes(result.value, flush: true);
  stdout.writeln('Generated ${output.path} (${result.value.length} bytes).');
  for (final page in inputs.layout.pages) {
    stdout.writeln(
      '${page.pageId.value}: '
      '${page.questionRegions.map((question) => question.questionId.value).join(', ')}',
    );
  }
}
