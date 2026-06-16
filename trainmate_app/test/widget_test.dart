import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trainmate_app/main.dart';

void main() {
  testWidgets('app builds and splash progresses', (WidgetTester tester) async {
    await tester.pumpWidget(const TrainMateApp());
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('TrainMate'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
