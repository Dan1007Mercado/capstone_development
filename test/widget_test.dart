import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:capstone_development/main.dart';

void main() {
  testWidgets('home exposes only primary workflows and developer tools', (
    tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byKey(const Key('open-template-builder')), findsOneWidget);
    expect(find.byKey(const Key('open-scanner')), findsOneWidget);
    expect(find.byKey(const Key('open-developer-tools')), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.textContaining('P5'), findsNothing);
    expect(find.textContaining('P10'), findsNothing);
    expect(find.textContaining('P11'), findsNothing);

    await tester.tap(find.byKey(const Key('open-developer-tools')));
    await tester.pumpAndSettle();

    expect(find.text('Developer Tools'), findsOneWidget);
    expect(find.byKey(const Key('developer-native-opencv')), findsOneWidget);
    expect(
      find.byKey(const Key('developer-camera-diagnostics')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('developer-template-validation')),
      findsOneWidget,
    );
  });
}
