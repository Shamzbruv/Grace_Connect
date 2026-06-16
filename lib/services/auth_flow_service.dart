import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum AuthRedirectPurpose {
  emailConfirmation,
  passwordReset,
}

class AuthFlowService {
  static const String _appScheme = 'app.graceconnect.church';
  static const String _configuredWebBaseUrl = String.fromEnvironment(
    'APP_BASE_URL',
    defaultValue: '',
  );
  static const String _firebaseWebBaseUrl =
      'https://graceconnect-9a97c.web.app';

  static String redirectUrl(AuthRedirectPurpose purpose) {
    if (kIsWeb) {
      final callbackType = switch (purpose) {
        AuthRedirectPurpose.emailConfirmation => 'signup',
        AuthRedirectPurpose.passwordReset => 'recovery',
      };

      return Uri.parse(_webBaseUrl()).replace(
        path: '/auth/callback',
        queryParameters: {'auth_callback': callbackType},
      ).toString();
    }

    final host = switch (purpose) {
      AuthRedirectPurpose.emailConfirmation => 'login-callback',
      AuthRedirectPurpose.passwordReset => 'reset-callback',
    };

    return '$_appScheme://$host/';
  }

  static String _webBaseUrl() {
    if (_configuredWebBaseUrl.trim().isNotEmpty) {
      return _configuredWebBaseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    }

    final origin = Uri.base.origin;
    final host = Uri.base.host.toLowerCase();
    final isLocalHost = host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host.startsWith('192.168.') ||
        host.startsWith('10.');

    if (origin.isNotEmpty && !isLocalHost) {
      return origin.replaceFirst(RegExp(r'/$'), '');
    }

    return _firebaseWebBaseUrl;
  }

  static bool isConfirmedUser(User? user) {
    if (user == null) return false;
    return user.emailConfirmedAt != null ||
        user.toJson()['confirmed_at'] != null;
  }

  static bool isEmailNotConfirmed(AuthException error) {
    final message = error.message.toLowerCase();
    return message.contains('email not confirmed') ||
        message.contains('not confirmed') ||
        message.contains('confirm your email') ||
        message.contains('verify your email');
  }

  static bool isExistingAccount(AuthException error) {
    final message = error.message.toLowerCase();
    return message.contains('already registered') ||
        message.contains('already exists') ||
        message.contains('user already');
  }

  static bool isAuthCallbackUri(Uri uri) {
    return _isKnownAuthCallbackUri(uri) ||
        uri.queryParameters.containsKey('auth_callback') ||
        uri.queryParameters.containsKey('code') ||
        uri.queryParameters.containsKey('error') ||
        uri.queryParameters.containsKey('error_description') ||
        uri.fragment.contains('access_token') ||
        uri.fragment.contains('refresh_token') ||
        uri.fragment.contains('error_description');
  }

  static bool isAuthCallbackRouteName(String routeName) {
    final candidate = routeName.trim();
    if (candidate.isEmpty || candidate == '/') return false;

    final parsed = Uri.tryParse(candidate);
    if (parsed != null && isAuthCallbackUri(parsed)) return true;

    if (candidate.startsWith('/')) {
      final resolved = Uri.base.resolve(candidate);
      if (isAuthCallbackUri(resolved)) return true;
    }

    return candidate.contains('access_token') ||
        candidate.contains('refresh_token') ||
        candidate.contains('error_description') ||
        candidate.contains('auth_callback') ||
        candidate.contains('code=') ||
        candidate.contains('login-callback') ||
        candidate.contains('reset-callback') ||
        candidate.contains(_appScheme);
  }

  static bool isPasswordResetCallback(Uri uri) {
    final callbackType = uri.queryParameters['auth_callback'];
    final queryType = uri.queryParameters['type'];
    final fragment = uri.fragment.toLowerCase();

    return _isKnownPasswordResetCallbackUri(uri) ||
        callbackType == 'recovery' ||
        queryType == 'recovery' ||
        fragment.contains('type=recovery');
  }

  static bool _isKnownAuthCallbackUri(Uri uri) {
    final hasKnownCallbackName = _isKnownNativeCallbackName(uri.host) ||
        uri.pathSegments.any(_isKnownNativeCallbackName);
    if (!hasKnownCallbackName) return false;

    return uri.scheme == _appScheme ||
        uri.host.isEmpty ||
        uri.host == Uri.base.host;
  }

  static bool _isKnownPasswordResetCallbackUri(Uri uri) {
    return uri.host == 'reset-callback' ||
        uri.pathSegments.contains('reset-callback');
  }

  static bool _isKnownNativeCallbackName(String value) {
    return value == 'login-callback' || value == 'reset-callback';
  }

  static Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    Map<String, dynamic>? data,
  }) {
    return _withRedirectFallback(
      purpose: AuthRedirectPurpose.emailConfirmation,
      withRedirect: (redirectTo) => Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: data,
        emailRedirectTo: redirectTo,
      ),
      withoutRedirect: () => Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: data,
      ),
    );
  }

  static Future<void> resendConfirmationEmail(String email) {
    return _withRedirectFallback<void>(
      purpose: AuthRedirectPurpose.emailConfirmation,
      withRedirect: (redirectTo) async {
        await Supabase.instance.client.auth.resend(
          type: OtpType.signup,
          email: email,
          emailRedirectTo: redirectTo,
        );
      },
      withoutRedirect: () async {
        await Supabase.instance.client.auth.resend(
          type: OtpType.signup,
          email: email,
        );
      },
    );
  }

  static Future<void> sendPasswordResetEmail(String email) {
    return _withRedirectFallback<void>(
      purpose: AuthRedirectPurpose.passwordReset,
      withRedirect: (redirectTo) =>
          Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: redirectTo,
      ),
      withoutRedirect: () =>
          Supabase.instance.client.auth.resetPasswordForEmail(email),
    );
  }

  static Future<T> _withRedirectFallback<T>({
    required AuthRedirectPurpose purpose,
    required Future<T> Function(String redirectTo) withRedirect,
    required Future<T> Function() withoutRedirect,
  }) async {
    try {
      return await withRedirect(redirectUrl(purpose));
    } on AuthException catch (error) {
      if (_isRedirectError(error)) {
        debugPrint(
            'Supabase rejected auth redirect URL; retrying with project default redirect. ${error.message}');
        return withoutRedirect();
      }
      rethrow;
    }
  }

  static bool _isRedirectError(AuthException error) {
    final message = error.message.toLowerCase();
    return message.contains('redirect') &&
        (message.contains('not allowed') ||
            message.contains('invalid') ||
            message.contains('is not supported'));
  }
}
