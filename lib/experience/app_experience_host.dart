import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/notification_service.dart';
import '../tutorial/tutorial_controller.dart';
import '../tutorial/tutorial_runtime.dart';
import 'app_experience_controller.dart';

class AppExperienceHost extends StatefulWidget {
  const AppExperienceHost({super.key, required this.child});
  final Widget child;
  @override
  State<AppExperienceHost> createState() => _AppExperienceHostState();
}

class _AppExperienceHostState extends State<AppExperienceHost>
    with WidgetsBindingObserver {
  AppExperienceController? _controller;
  TutorialController? _tutorials;
  TutorialRuntime? _runtime;
  StreamSubscription<AuthState>? _auth;
  bool _opening = false, _foreground = true;
  String? _dialogUser;
  BuildContext? _dialogContext;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (kIsWeb || _controller != null) return;
    _controller = context.read<AppExperienceController?>();
    if (_controller == null) return;
    _tutorials = context.read<TutorialController>();
    _runtime = context.read<TutorialRuntime>();
    _controller!.addListener(_changed);
    _tutorials!.addListener(_changed);
    _runtime!.addListener(_changed);
    void userChanged() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_controller!.initializeForUser(
              Supabase.instance.client.auth.currentUser?.id));
        }
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }

    _auth = Supabase.instance.client.auth.onAuthStateChange
        .listen((_) => userChanged());
    userChanged();
  }

  bool get _safe {
    final scene = _runtime?.active;
    final screen = scene?.screenId ?? '';
    final supported = screen == 'community_feed' ||
        screen == 'more' ||
        screen == 'settings' ||
        screen == 'devices_app' ||
        screen.startsWith('dashboard.');
    return _foreground &&
        supported &&
        scene?.eligible == true &&
        _tutorials?.overlayVisible != true &&
        _tutorials?.current == null &&
        _tutorials?.temporarilySuppressed != true &&
        MediaQuery.viewInsetsOf(context).bottom == 0;
  }

  void _changed() {
    if (!mounted) return;
    if (_opening && _dialogUser != _controller?.userId) {
      final dialog = _dialogContext;
      if (dialog != null &&
          dialog.mounted &&
          ModalRoute.of(dialog)?.isCurrent == true) {
        Navigator.of(dialog).pop();
      }
      return;
    }
    if (_opening ||
        _controller?.eligible != true ||
        _controller?.storeUrl == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_opening && _safe) unawaited(_present());
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _present() async {
    final controller = _controller!;
    if (!_safe || !controller.eligible) return;
    _opening = true;
    _dialogUser = controller.userId;
    var suppressed = false;
    try {
      if (!await controller.claimPrompt() ||
          !mounted ||
          !_safe ||
          controller.userId != _dialogUser) {
        return;
      }
      final navContext = NotificationService.navigatorKey.currentContext;
      if (navContext == null || !navContext.mounted) return;
      _tutorials!.suppress();
      suppressed = true;
      final answer = await showDialog<bool>(
          context: navContext,
          builder: (dialog) {
            _dialogContext = dialog;
            return AlertDialog(
              icon: const Icon(Icons.favorite_outline),
              title: const Text('Growing together in faith'),
              content: const Text(
                  'Is Grace Connect helping you grow closer to God and connect with others in faith?\n\nYour honest feedback helps us serve this community.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog),
                    child: const Text('Not now')),
                TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('No')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const Text('Yes'))
              ],
            );
          });
      if (!mounted || controller.userId != _dialogUser) return;
      unawaited(controller.record(answer == null ? 'dismissed' : 'answered',
          response: answer));
      if (answer == null || !navContext.mounted) return;
      // Identical invitation for either answer. No star filter, incentives or
      // inference that returning from the store means a review was submitted.
      final visit = await showDialog<bool>(
          context: navContext,
          builder: (dialog) {
            _dialogContext = dialog;
            return AlertDialog(
              title: const Text('Thank you for sharing'),
              content: Text(
                  'You can share what works and what could improve in an honest review on ${controller.storeName}.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const Text('Later')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: Text('Open ${controller.storeName}'))
              ],
            );
          });
      if (visit == true && mounted && controller.userId == _dialogUser) {
        await openExperienceStore(controller);
      }
    } finally {
      _dialogContext = null;
      _opening = false;
      _dialogUser = null;
      if (suppressed) _tutorials?.resume();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _controller?.setForeground(_foreground);
    if (_foreground) _changed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth?.cancel();
    _controller?.removeListener(_changed);
    _tutorials?.removeListener(_changed);
    _runtime?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<bool> openExperienceStore(AppExperienceController controller) async {
  final userId = controller.userId;
  final url = controller.storeUrl;
  if (url == null) return false;
  final uri = Uri.tryParse(url);
  if (uri == null ||
      uri.scheme != 'https' ||
      !{'play.google.com', 'apps.apple.com'}.contains(uri.host)) {
    return false;
  }
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (opened && controller.userId == userId) {
      await controller.record('store_opened');
    }
    return opened;
  } catch (_) {
    return false;
  }
}
