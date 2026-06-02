import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/login screen/login_screen.dart';
import '../services/auth_flow_service.dart';

class AuthRequired extends StatelessWidget {
  const AuthRequired({
    super.key,
    required this.child,
  });

  final Widget child;

  Stream<AuthState> _safeAuthStateStream() {
    try {
      return Supabase.instance.client.auth.onAuthStateChange;
    } catch (error) {
      debugPrint('Supabase not initialized, falling back to login: $error');
      return const Stream.empty();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: _safeAuthStateStream(),
      builder: (context, snapshot) {
        try {
          final user = Supabase.instance.client.auth.currentUser ??
              snapshot.data?.session?.user;

          if (!AuthFlowService.isConfirmedUser(user)) {
            return const LoginScreen();
          }

          return child;
        } catch (error) {
          debugPrint(
              'Failed to read Supabase auth state, falling back to login: $error');
          return const LoginScreen();
        }
      },
    );
  }
}
