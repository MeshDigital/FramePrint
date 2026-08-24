import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:frameprint/main.dart';

void main() {
  testWidgets('FramePrint home screen renders app bar and add button', (
    WidgetTester tester,
  ) async {
    // Uses a single pump rather than pumpAndSettle: the home screen loads
    // its card list from a real sqflite database, which never resolves in
    // the widget-test harness, so we only assert on what renders
    // immediately.
    await tester.pumpWidget(const FramePrintApp());
    await tester.pump();

    expect(find.text('FramePrint'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });
}
