// A local-only component preview. No real profiles, usage or progress are read
// or written; this route is registered only in debug builds.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import 'tutorial_anchor.dart';
import 'tutorial_controller.dart';
import 'tutorial_definition.dart';
import 'tutorial_analytics.dart';
import 'tutorial_host.dart';
import 'tutorial_registry.dart';
import 'tutorial_runtime.dart';
import 'tutorial_state.dart';
import 'tutorial_storage.dart';

class _PreviewStorage extends TutorialStorage {
  @override
  Future<TutorialState> load(String id) async => TutorialState(enabled: true);
  @override
  Future<void> save(String id, TutorialState state) async {}
}

class _PreviewAnalytics extends TutorialAnalytics {
  @override
  void event(String name,
      {TutorialDefinition? definition, int? step, int? count}) {}
}

class TutorialPreview extends StatefulWidget {
  const TutorialPreview({super.key});
  @override
  State<TutorialPreview> createState() => _TutorialPreviewState();
}

class _TutorialPreviewState extends State<TutorialPreview> {
  late final TutorialController controller;
  final runtime = TutorialRuntime();
  late final TutorialNavigationObserver observer;
  String screen = 'community_feed';
  bool dark = false;
  double scale = 1;
  @override
  void initState() {
    super.initState();
    controller = TutorialController(
        storage: _PreviewStorage(), analytics: _PreviewAnalytics());
    controller.initializeForUser('local-preview');
    observer = TutorialNavigationObserver(runtime);
  }

  @override
  void dispose() {
    controller.dispose();
    runtime.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Tutorial preview · sample controls')),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<String>(
                      value: screen,
                      items: TutorialRegistry.definitions.keys
                          .map((id) =>
                              DropdownMenuItem(value: id, child: Text(id)))
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => screen = value);
                      }),
                  IconButton(
                      tooltip: 'Toggle light and dark',
                      onPressed: () => setState(() => dark = !dark),
                      icon: Icon(dark ? Icons.light_mode : Icons.dark_mode)),
                  DropdownButton<double>(
                      value: scale,
                      items: [1.0, 1.3, 1.6, 2.0]
                          .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text('${(s * 100).round()}% text')))
                          .toList(),
                      onChanged: (s) => setState(() => scale = s!)),
                  FilledButton.tonal(
                      onPressed: () {
                        controller.screenChanged('preview.controls');
                        controller.restartAll();
                        runtime.changed();
                      },
                      child: const Text('Replay guides')),
                ])),
        Expanded(
            child: MultiProvider(
                providers: [
              ChangeNotifierProvider.value(value: controller),
              ChangeNotifierProvider.value(value: runtime)
            ],
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.lightTheme,
                  darkTheme: AppTheme.darkTheme,
                  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
                  navigatorObservers: [observer],
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: TutorialHost(child: child!)),
                  home: Builder(builder: (context) {
                    final definition = TutorialRegistry.definitions[screen]!;
                    return Scaffold(
                        appBar:
                            AppBar(title: Text(screen.replaceAll('_', ' '))),
                        body: ListView(
                            padding: const EdgeInsets.all(20),
                            children: [
                              const Text(
                                  'Local preview — these controls demonstrate guidance without changing your account.'),
                              const SizedBox(height: 20),
                              for (final step in definition.steps)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 20),
                                    child: Card(
                                            child: ListTile(
                                                contentPadding:
                                                    const EdgeInsets.all(18),
                                                leading: const Icon(Icons
                                                    .auto_awesome_outlined),
                                                title: Text(step.title),
                                                subtitle: Text(step.message),
                                                onTap: () {}))
                                        .tutorial(step.targetId)),
                            ])).tutorialScreen(screen);
                  }),
                ))),
      ]));
}
