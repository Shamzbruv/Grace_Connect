// test/widget_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:grace_connect/main.dart';
import 'package:grace_connect/providers/theme_provider.dart';
import 'package:grace_connect/providers/user_role_provider.dart';

void main() {
  testWidgets('App starts and shows the app title',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => UserRoleProvider()),
        ],
        child: const MyApp(),
      ),
    );

    expect(find.text('GraceConnect'), findsOneWidget);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
