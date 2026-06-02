import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/auth_flow_service.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';

class AuthCallbackScreen extends StatefulWidget {
  const AuthCallbackScreen({super.key});

  @override
  State<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends State<AuthCallbackScreen> {
  String? _error;
  bool _confirmedWithoutSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _completeAuthCallback();
    });
  }

  Future<void> _completeAuthCallback() async {
    final supabase = Supabase.instance.client;
    final uri = _effectiveCallbackUri();

    final callbackError = _callbackErrorMessage(uri);
    if (callbackError != null) {
      if (mounted) setState(() => _error = callbackError);
      return;
    }

    try {
      if (AuthFlowService.isAuthCallbackUri(uri) &&
          supabase.auth.currentSession == null) {
        try {
          await supabase.auth.getSessionFromUrl(uri);
        } on AuthException catch (error) {
          debugPrint(
              'Auth callback was not manually exchanged: ${error.message}');
        }
      }

      final callbackResult = await _waitForAuthSession(supabase);
      final session = callbackResult.session ?? supabase.auth.currentSession;
      final user = session?.user ?? supabase.auth.currentUser;

      if (!mounted) return;

      if (user == null) {
        setState(() {
          _confirmedWithoutSession = true;
        });
        return;
      }

      if (callbackResult.event == AuthChangeEvent.passwordRecovery ||
          AuthFlowService.isPasswordResetCallback(uri)) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/reset_password', (route) => false);
        return;
      }

      final profileData = await supabase
          .from('users')
          .select()
          .eq('uid', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (profileData == null) {
        Navigator.of(context)
            .pushNamedAndRemoveUntil('/complete_profile', (route) => false);
        return;
      }

      final roleProvider =
          Provider.of<UserRoleProvider>(context, listen: false);
      roleProvider.setUserProfile(UserProfile.fromMap(profileData));

      Navigator.of(context)
          .pushNamedAndRemoveUntil('/dashboard', (route) => false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'We could not complete this auth link: $error';
      });
    }
  }

  Uri _effectiveCallbackUri() {
    final candidates = <String>[
      ModalRoute.of(context)?.settings.name ?? '',
      WidgetsBinding.instance.platformDispatcher.defaultRouteName,
      Uri.base.toString(),
    ];

    for (final rawCandidate in candidates) {
      final candidate = rawCandidate.trim();
      if (candidate.isEmpty || candidate == '/') continue;

      final parsed = Uri.tryParse(candidate);
      if (parsed != null && AuthFlowService.isAuthCallbackUri(parsed)) {
        return parsed;
      }

      if (candidate.startsWith('/')) {
        final resolved = Uri.base.resolve(candidate);
        if (AuthFlowService.isAuthCallbackUri(resolved)) return resolved;
      }
    }

    return Uri.base;
  }

  Future<_AuthCallbackResult> _waitForAuthSession(
      SupabaseClient supabase) async {
    final currentSession = supabase.auth.currentSession;
    if (currentSession != null) {
      return _AuthCallbackResult(currentSession, null);
    }

    final completer = Completer<_AuthCallbackResult>();
    late final StreamSubscription<AuthState> subscription;
    subscription = supabase.auth.onAuthStateChange.listen((state) {
      if (state.session != null && !completer.isCompleted) {
        completer.complete(_AuthCallbackResult(state.session, state.event));
      }
    });

    try {
      return await Future.any([
        completer.future,
        Future.delayed(
          const Duration(seconds: 5),
          () => _AuthCallbackResult(supabase.auth.currentSession, null),
        ),
      ]);
    } finally {
      await subscription.cancel();
    }
  }

  String? _callbackErrorMessage(Uri uri) {
    final description = uri.queryParameters['error_description'];
    final error = uri.queryParameters['error'];

    if (description != null && description.isNotEmpty) {
      return description;
    }

    if (error != null && error.isNotEmpty) {
      return error;
    }

    if (uri.fragment.contains('error_description=')) {
      final fragmentQuery = uri.fragment.contains('?')
          ? uri.fragment.split('?').last
          : uri.fragment;
      final fragmentParams = Uri.splitQueryString(fragmentQuery);
      return fragmentParams['error_description'] ?? fragmentParams['error'];
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      withBackground: true,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: AppCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _error != null
                      ? Icons.error_outline
                      : _confirmedWithoutSession
                          ? Icons.verified_outlined
                          : Icons.mark_email_read_outlined,
                  size: 56,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  _error != null
                      ? 'Link Issue'
                      : _confirmedWithoutSession
                          ? 'Account Confirmed'
                          : 'Confirming your account...',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  _error ??
                      (_confirmedWithoutSession
                          ? 'Your email has been confirmed. Please sign in to continue.'
                          : 'Please wait while Grace Connect finishes setting up your sign in.'),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (_error == null && !_confirmedWithoutSession)
                  const CircularProgressIndicator()
                else
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      text: 'Back to Sign In',
                      onPressed: () {
                        Navigator.of(context).pushNamedAndRemoveUntil(
                            '/login', (route) => false);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthCallbackResult {
  const _AuthCallbackResult(this.session, this.event);

  final Session? session;
  final AuthChangeEvent? event;
}
