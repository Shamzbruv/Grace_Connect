import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/models/bible_passage_reference.dart';
import 'package:grace_connect/services/daily_grace_service.dart';
import 'package:grace_connect/widgets/daily_grace_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
      'bundled daily Scriptures have valid references and remain available offline',
      () async {
    final verses = await DailyGraceService.catalogue();
    expect(verses.length, 31);
    expect(verses.map((v) => v.reference).toSet().length, 31);
    for (final verse in verses) {
      expect(BiblePassageReference.tryParse(verse.reference), isNotNull,
          reason: verse.reference);
      expect(verse.text.trim(), isNotEmpty);
      expect(
          (await DailyGraceService.scripture(reference: verse.reference)).text,
          verse.text);
    }
  });

  test(
      'calendar day selection advances at midnight, including leap years and DST dates',
      () {
    for (final date in [
      DateTime(2024, 2, 28),
      DateTime(2024, 2, 29),
      DateTime(2026, 3, 8),
      DateTime(2026, 11, 1)
    ]) {
      final next = DateTime(date.year, date.month, date.day + 1);
      expect(DailyGraceService.indexForDay(next, 31),
          (DailyGraceService.indexForDay(date, 31) + 1) % 31);
      expect(
          DailyGraceService.indexForDay(
              DateTime(date.year, date.month, date.day, 23, 59), 31),
          DailyGraceService.indexForDay(date, 31));
    }
    expect(DailyGraceService.indexForDay(DateTime(1970), 31), 0);
    expect(DailyGraceService.indexForDay(DateTime(1969, 12, 31), 31), 30);
  });

  testWidgets(
      'large Scripture and both shortcuts fit a narrow screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final verse = DailyScripture('Long passage',
        List.filled(30, 'A long passage with room to read.').join(' '));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: ListView(children: [
        DailyGraceCard(scripture: verse, onRead: () {}, onConnect: () {})
      ]),
    ))));
    expect(tester.takeException(), isNull);
    expect(find.text('Read Scripture'), findsOneWidget);
  });

  testWidgets('widget warm and cold launch route only to allowed destinations',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const codec = StandardMethodCodec();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        DailyGraceService.channel,
        (call) async => call.method == 'initialDestination'
            ? {'destination': 'scripture', 'reference': 'John 8:12'}
            : true);
    addTearDown(() =>
        messenger.setMockMethodCallHandler(DailyGraceService.channel, null));
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
        MaterialApp(navigatorKey: key, home: const Text('Home'), routes: {
      '/daily_grace': (context) =>
          Text('Opened ${ModalRoute.of(context)!.settings.arguments}'),
      '/community': (_) => const Text('Community'),
    }));
    await DailyGraceService.initialize(key);
    await tester.pumpAndSettle();
    expect(find.text('Opened John 8:12'), findsOneWidget);
    Future<void> send(String destination) async {
      await messenger.handlePlatformMessage(
          'love.graceconnect/home_widget',
          codec.encodeMethodCall(
              MethodCall('open', {'destination': destination})),
          (_) {});
      await tester.pumpAndSettle();
    }

    await send('/developer');
    expect(find.text('Opened John 8:12'), findsOneWidget);
    await send('community');
    expect(find.text('Community'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
    DailyGraceService.channel.setMethodCallHandler(null);
  });
}
