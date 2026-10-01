import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/widgets/reels/reel_mode_header.dart';

void main() {
  for (final width in [320.0, 390.0, 480.0]) {
    testWidgets('Reel modes are centered at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      String? selected;
      var creates = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ReelModeHeader(
        mode: 'discover',
        onModeChanged: (mode) => selected = mode,
        onCreate: () => creates++,
      ))));
      expect(tester.getCenter(find.byKey(const Key('reel-mode-tabs'))).dx,
          closeTo(width / 2, 0.01));
      await tester.tap(find.text('Following'));
      expect(selected, 'following');
      await tester.tap(find.byTooltip('New reel'));
      expect(creates, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
