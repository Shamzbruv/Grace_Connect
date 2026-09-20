import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/theme/app_theme.dart';

/// Guards the bug that made the Grace Rooms send button invisible.
///
/// ThemeData.iconTheme carries a colour, and IconButton adopts that colour as
/// its foreground unless the call site overrides it. In the light theme that
/// colour is onSurface (#1A1A1A) while a filled button's background is
/// primary (#10141C) -- a black icon on a black circle.
///
/// The fix is per-button rather than in the theme, because removing the
/// theme's icon colour turns every bare icon black in dark mode instead.
/// These tests pin both halves of that: the hazard is real, and the override
/// defeats it.
void main() {
  Future<Color?> foregroundOf(
    WidgetTester tester,
    ThemeData theme,
    IconData icon,
    Widget button,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: theme, home: Scaffold(body: button)),
    );
    return IconTheme.of(tester.element(find.byIcon(icon))).color;
  }

  testWidgets('an unstyled filled button is unreadable in the light theme',
      (tester) async {
    final theme = AppTheme.lightTheme;
    final foreground = await foregroundOf(
      tester,
      theme,
      Icons.send_outlined,
      IconButton.filled(
        onPressed: () {},
        icon: const Icon(Icons.send_outlined),
      ),
    );

    // Documents why every filled button in this app must pass a style: left
    // to the theme, the icon lands within a hair of its own background.
    final background = theme.colorScheme.primary;
    expect(foreground, isNotNull);
    expect(
      (foreground!.r - background.r).abs() < 0.05 &&
          (foreground.g - background.g).abs() < 0.05 &&
          (foreground.b - background.b).abs() < 0.05,
      isTrue,
      reason: 'the hazard this test guards against no longer exists; if '
          'Flutter or the theme changed, the per-button styles can be revisited',
    );
  });

  testWidgets('an explicit style restores contrast in both themes',
      (tester) async {
    for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
      final scheme = theme.colorScheme;
      final foreground = await foregroundOf(
        tester,
        theme,
        Icons.send_outlined,
        Builder(
          builder: (context) => IconButton.filled(
            onPressed: () {},
            style: IconButton.styleFrom(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
            ),
            icon: const Icon(Icons.send_outlined),
          ),
        ),
      );
      expect(foreground, scheme.onPrimary);
      expect(foreground, isNot(scheme.primary));
    }
  });
}
