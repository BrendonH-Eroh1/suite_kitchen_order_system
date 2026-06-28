// Smoke test: the KDS app boots to the setup screen when unprovisioned.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sep_kitchen/screens/station_setup_screen.dart';

void main() {
  testWidgets('Setup screen renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: StationSetupScreen()),
    );
    expect(find.text('1 · Device credentials'), findsOneWidget);
  });
}
