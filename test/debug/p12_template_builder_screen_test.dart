import 'package:capstone_development/application/template_builder/template_builder_controller.dart';
import 'package:capstone_development/debug/p12_template_builder_fixture.dart';
import 'package:capstone_development/debug/p12_template_builder_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('screen keeps controller draft and exposes P12 actions', (
    tester,
  ) async {
    final controller = TemplateBuilderController();
    await tester.pumpWidget(
      MaterialApp(home: P12TemplateBuilderScreen(controller: controller)),
    );

    await tester.tap(find.byKey(const Key('add-section')));
    await tester.pump();
    final sectionId = controller.snapshot.definition.sections.single.id;
    await tester.tap(find.byKey(Key('add-question-${sectionId.value}')));
    await tester.pump();

    expect(
      controller.snapshot.definition.sections.single.questions,
      hasLength(1),
    );
    expect(find.text('Question 1'), findsOneWidget);
    expect(find.text('Single Choice'), findsOneWidget);
  });

  testWidgets('mixed demo validates and previews through LayoutEngine', (
    tester,
  ) async {
    final controller = buildP12MixedTemplateDemo();
    await tester.pumpWidget(
      MaterialApp(home: P12TemplateBuilderScreen(controller: controller)),
    );

    await tester.dragUntilVisible(
      find.byKey(const Key('preview-layout')),
      find.byType(ListView),
      const Offset(0, -500),
    );
    await tester.tap(find.byKey(const Key('preview-layout')));
    await tester.pump();
    await tester.dragUntilVisible(
      find.byKey(const Key('layout-preview-panel')),
      find.byType(ListView),
      const Offset(0, -400),
    );

    expect(find.text('Template is valid.'), findsOneWidget);
    expect(find.textContaining('Layout preview:'), findsOneWidget);
  });
}
