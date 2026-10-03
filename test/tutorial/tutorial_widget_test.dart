import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:grace_connect/tutorial/tutorial_anchor.dart';
import 'package:grace_connect/tutorial/tutorial_controller.dart';
import 'package:grace_connect/tutorial/tutorial_host.dart';
import 'package:grace_connect/tutorial/tutorial_runtime.dart';
import 'package:grace_connect/tutorial/tutorial_screen_scope.dart';
import 'package:grace_connect/tutorial/tutorial_state.dart';
import 'package:grace_connect/tutorial/tutorial_storage.dart';
import 'package:grace_connect/tutorial/tutorial_tooltip.dart';
import 'package:grace_connect/tutorial/tutorial_definition.dart';
import 'package:grace_connect/tutorial/tutorial_registry.dart';

const constPlaceholder = TutorialDefinition('missing', []);

class TestStorage extends TutorialStorage {
  @override
  Future<TutorialState> load(String id) async => TutorialState(enabled: true);
  @override
  Future<void> save(String id, TutorialState state) async {}
}

Future<void> settleGuide(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 300));
  await t.pump();
}

Future<
        ({
          TutorialController c,
          TutorialRuntime runtime,
          GlobalKey<NavigatorState> nav
        })>
    mount(WidgetTester t, Widget child,
        {double scale = 1, Brightness brightness = Brightness.light}) async {
  final c = TutorialController(storage: TestStorage());
  await c.initializeForUser('a');
  final runtime = TutorialRuntime();
  final nav = GlobalKey<NavigatorState>();
  addTearDown(() {
    c.dispose();
    runtime.dispose();
  });
  await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: c),
        ChangeNotifierProvider.value(value: runtime)
      ],
      child: MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [TutorialNavigationObserver(runtime)],
          theme: ThemeData(brightness: brightness),
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: TutorialHost(child: child!)),
          home: child)));
  await settleGuide(t);
  return (c: c, runtime: runtime, nav: nav);
}

Widget page({bool ready = true, bool tools = true, VoidCallback? onTap}) =>
    TutorialScreenScope(
        screenId: 'inbox',
        ready: ready,
        child: Scaffold(
            appBar:
                AppBar(title: const Text('Inbox').tutorial('inbox.overview')),
            body: Center(
                child: tools
                    ? FilledButton(
                            onPressed: onTap ?? () {},
                            child: const Text('Compose'))
                        .tutorial('inbox.tools')
                    : const Text('Empty'))));

// Uses the same PageView -> feed IndexedStack -> visibility boundaries as the
// application shell, with small controls that do not require network accounts.
Widget navigationPage(String screen) => TutorialScreenScope(
    screenId: screen,
    child: Scaffold(
        body: Center(
            child: Text(screen).tutorial(
                TutorialRegistry.definitions[screen]!.steps.first.targetId))));

void main() {
  testWidgets('PageView and Feed/Reels modes learn independently', (t) async {
    final pager = PageController();
    final selected = ValueNotifier(0), mode = ValueNotifier(0);
    addTearDown(pager.dispose);
    addTearDown(selected.dispose);
    addTearDown(mode.dispose);
    final h = await mount(
        t,
        ValueListenableBuilder<int>(
            valueListenable: selected,
            builder: (_, tab, __) => PageView(
                    controller: pager,
                    onPageChanged: (value) => selected.value = value,
                    children: [
                      ValueListenableBuilder<int>(
                          valueListenable: mode,
                          builder: (_, feedMode, __) =>
                              IndexedStack(index: feedMode, children: [
                                for (final entry
                                    in ['community_feed', 'reel_grace'].indexed)
                                  TutorialVisibility(
                                      visible: tab == 0 && feedMode == entry.$1,
                                      child: navigationPage(entry.$2)),
                              ])),
                      TutorialVisibility(
                          visible: tab == 1, child: navigationPage('events')),
                    ])));
    expect(h.c.activeScreenId, 'community_feed');
    await t.tap(find.text('Got it'));
    await settleGuide(t);
    expect(h.c.isSeen('community_feed', 1), true);
    pager.jumpToPage(1);
    await settleGuide(t);
    expect(h.c.activeScreenId, 'events');
    pager.jumpToPage(0);
    await settleGuide(t);
    expect(find.byType(TutorialTooltip), findsNothing);
    mode.value = 1;
    await settleGuide(t);
    expect(h.c.activeScreenId, 'reel_grace');
    expect(h.c.isSeen('reel_grace', 1), false);
    await t.tap(find.text('Got it'));
    await settleGuide(t);
    mode.value = 0;
    await settleGuide(t);
    expect(find.byType(TutorialTooltip), findsNothing);
  });
  testWidgets(
      'role changes and restart defer only the currently visible screen',
      (t) async {
    final role = ValueNotifier('dashboard.member');
    addTearDown(role.dispose);
    final h = await mount(
        t,
        ValueListenableBuilder<String>(
            valueListenable: role,
            builder: (_, value, __) => navigationPage(value)));
    expect(h.c.activeScreenId, 'dashboard.member');
    await t.tap(find.text('Got it'));
    await settleGuide(t);
    role.value = 'dashboard.pastor';
    await settleGuide(t);
    expect(h.c.activeScreenId, 'dashboard.pastor');
    await h.c.restartAll();
    await settleGuide(t);
    expect(find.byType(TutorialTooltip), findsNothing);
    role.value = 'dashboard.admin';
    await settleGuide(t);
    expect(h.c.activeScreenId, 'dashboard.admin');
    role.value = 'dashboard.pastor';
    await settleGuide(t);
    expect(h.c.activeScreenId, 'dashboard.pastor');
    expect(h.c.steps.length, 1); // Only this role's mounted control exists.
  });
  testWidgets('Next, Back, explicit dismissal and no pointer passthrough',
      (t) async {
    var taps = 0;
    final h = await mount(t, page(onTap: () => taps++));
    expect(find.byType(TutorialTooltip), findsOneWidget);
    await t.tap(find.text('Compose'), warnIfMissed: false);
    expect(taps, 0);
    await t.tap(find.text('Next'));
    await settleGuide(t);
    expect(h.c.activeStepIndex, 1);
    await t.tap(find.text('Back'));
    await settleGuide(t);
    expect(h.c.activeStepIndex, 0);
    await t.tap(find.byKey(const ValueKey('tutorial-close')));
    await t.pump();
    expect(find.text('Skip this screen'), findsOneWidget);
    await t.tap(find.text('Continue guide'));
    await t.pump();
    expect(h.c.leaveMenuVisible, false);
    h.c.showLeaveMenu();
    await t.pump();
    await t.tap(find.text('Skip this screen'));
    await settleGuide(t);
    expect(h.c.isSeen('inbox', 1), true);
    expect(find.byType(TutorialTooltip), findsNothing);
  });
  testWidgets(
      'missing permission-controlled targets skip and all missing completes silently',
      (t) async {
    final h = await mount(t, page(tools: false));
    expect(h.c.steps.length, 1);
    await t.tap(find.text('Got it'));
    await settleGuide(t);
    expect(h.c.isSeen('inbox', 1), true);
    await h.c.restartAll();
    h.c.start(constPlaceholder, []);
    expect(h.c.isSeen('missing', 1), true);
  });
  testWidgets('modal suspends guide and resumes same step after dismissal',
      (t) async {
    final h = await mount(t, page());
    await t.tap(find.text('Next'));
    await settleGuide(t);
    showDialog<void>(
        context: h.nav.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Real dialog')));
    await t.pumpAndSettle();
    expect(find.byType(TutorialTooltip), findsNothing);
    expect(find.text('Real dialog'), findsOneWidget);
    h.nav.currentState!.pop();
    await t.pumpAndSettle();
    await settleGuide(t);
    expect(find.byType(TutorialTooltip), findsOneWidget);
    expect(h.c.activeStepIndex, 1);
  });
  testWidgets('kept-alive hidden page cannot start; loading guards defer guide',
      (t) async {
    final visible = ValueNotifier(false), ready = ValueNotifier(false);
    addTearDown(visible.dispose);
    addTearDown(ready.dispose);
    final h = await mount(
        t,
        ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (context, value, _) => TutorialVisibility(
                visible: value,
                child: ValueListenableBuilder<bool>(
                    valueListenable: ready,
                    builder: (_, value, __) => page(ready: value)))));
    expect(h.c.current, isNull);
    visible.value = true;
    await settleGuide(t);
    expect(h.c.current, isNull);
    ready.value = true;
    await settleGuide(t);
    expect(h.c.current?.screenId, 'inbox');
    visible.value = false;
    await settleGuide(t);
    expect(find.byType(TutorialTooltip), findsNothing);
  });
  for (final width in [320.0, 360.0, 390.0, 412.0]) {
    for (final scale in [1.0, 1.3, 1.6, 2.0]) {
      testWidgets('accessible tooltip at width $width, text $scale', (t) async {
        t.view.physicalSize = Size(width, 800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final semantics = t.ensureSemantics();
        final h = await mount(t, page(),
            scale: scale,
            brightness: scale == 2 ? Brightness.dark : Brightness.light);
        expect(find.byType(TutorialTooltip), findsOneWidget);
        expect(t.takeException(), isNull);
        expect(find.bySemanticsLabel(RegExp('Step 1 of 2')), findsWidgets);
        h.c.showLeaveMenu();
        await t.pump();
        expect(t.takeException(), isNull);
        semantics.dispose();
      });
    }
  }
}
