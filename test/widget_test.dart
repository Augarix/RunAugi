// This is a basic Flutter widget test.
//
// Instead of pumping a specific widget class (like MyApp from the template),
// we call the real application entrypoint and assert the app builds.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Import your app entrypoint under an alias to access main().
import 'package:runaugi/main.dart' as app;

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    // Run the real app
    app.main();

    // Let all frames settle (routes, async inits, etc.)
    await tester.pumpAndSettle();

    // Basic sanity check: the root MaterialApp exists.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
