import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tutorial_controller.dart';

class TutorialSession extends StatefulWidget {
  const TutorialSession({super.key, required this.child});
  final Widget child;
  @override
  State<TutorialSession> createState() => _TutorialSessionState();
}

class _TutorialSessionState extends State<TutorialSession> {
  StreamSubscription<AuthState>? _subscription;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subscription != null || context.read<TutorialController?>() == null) {
      return;
    }
    final auth = Supabase.instance.client.auth;
    _subscription =
        auth.onAuthStateChange.listen((event) => _bind(event.session?.user.id));
    _bind(auth.currentUser?.id);
  }

  void _bind(String? userId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(context.read<TutorialController>().initializeForUser(userId));
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
