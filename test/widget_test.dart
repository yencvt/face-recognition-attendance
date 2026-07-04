import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_cam/database/app_database.dart';
import 'package:flutter_cam/log/log_service.dart';
import 'package:flutter_cam/main.dart';

void main() {
  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await LogService().init();
    await AppDatabase.instance();
    await AppDatabase.clearCameras();
  });

  testWidgets('can discover and add a camera from the dialog', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Camera Conference'), findsOneWidget);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Scan again'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.textContaining('Laptop camera'), findsWidgets);

    final connectButton = find.widgetWithText(FilledButton, 'Connect').first;
    if (tester.any(connectButton)) {
      await tester.tap(connectButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    final addButton = find.widgetWithText(FilledButton, 'Add camera').first;
    if (tester.any(addButton)) {
      await tester.tap(addButton);
      await tester.pumpAndSettle();
    }

    final savedCameras = await AppDatabase.getCameras();
    expect(savedCameras.isNotEmpty, isTrue);
  });
}
