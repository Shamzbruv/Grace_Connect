import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Grace mail security hardening', () {
    test('all Supabase auth and security mail templates are branded', () {
      final config = File('supabase/config.toml').readAsStringSync();
      const expectedTemplates = <String, List<String>>{
        'reauthentication.html': ['{{ .Token }}'],
        'password_changed_notification.html': ['{{ .Email }}'],
        'email_changed_notification.html': ['{{ .OldEmail }}', '{{ .Email }}'],
        'phone_changed_notification.html': ['{{ .OldPhone }}', '{{ .Phone }}'],
        'mfa_factor_enrolled_notification.html': ['{{ .FactorType }}'],
        'mfa_factor_unenrolled_notification.html': ['{{ .FactorType }}'],
        'identity_linked_notification.html': ['{{ .Provider }}'],
        'identity_unlinked_notification.html': ['{{ .Provider }}'],
      };

      expect(config, contains('[auth.email.template.reauthentication]'));
      for (final entry in expectedTemplates.entries) {
        final path = 'supabase/templates/${entry.key}';
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path must exist');
        final configuredPath = entry.key == 'reauthentication.html'
            ? './supabase/templates/${entry.key}'
            : './templates/${entry.key}';
        expect(config, contains('content_path = "$configuredPath"'));

        final source = file.readAsStringSync();
        expect(source, contains('data-grace-email="true"'));
        expect(source, contains('Grace Connect'));
        for (final placeholder in entry.value) {
          expect(source, contains(placeholder),
              reason: '$path needs $placeholder');
        }
      }

      for (final notification in const <String>[
        'password_changed',
        'email_changed',
        'phone_changed',
        'mfa_factor_enrolled',
        'mfa_factor_unenrolled',
        'identity_linked',
        'identity_unlinked',
      ]) {
        expect(config, contains('[auth.email.notification.$notification]'));
      }
      expect(RegExp(r'enabled = true').allMatches(config).length,
          greaterThanOrEqualTo(7));
    });

    test('public mail quotas are private and consumed transactionally', () {
      final migration = File(
        'supabase/migrations/20260805200000_grace_mailer_public_abuse_protection.sql',
      ).readAsStringSync();

      expect(migration, contains('grace_mail_public_rate_events'));
      expect(migration, contains('email_key text not null'));
      expect(migration, contains('ip_key text'));
      expect(migration, isNot(contains('email_address')));
      expect(migration, contains('enable row level security'));
      expect(migration, contains('security definer'));
      expect(migration, contains('pg_advisory_xact_lock'));
      expect(migration, contains('consume_grace_mail_public_rate_limit'));
      expect(migration, contains('from public, anon, authenticated'));
      expect(migration, contains('to service_role'));
      expect(migration, contains("interval '1 minute'"));
      expect(migration, contains("interval '10 minutes'"));
      expect(migration, contains("interval '1 hour'"));
      expect(migration, contains("interval '1 day'"));
      expect(migration, contains("'allowed', false"));
      expect(migration, contains("'allowed', true"));
    });

    test('public signup and reset enforce rate limit and optional CAPTCHA', () {
      final mailer =
          File('supabase/functions/grace-mailer/index.ts').readAsStringSync();
      final authFlow =
          File('lib/services/auth_flow_service.dart').readAsStringSync();
      final signupStart =
          mailer.indexOf('async function sendSignupVerification');
      final resetStart = mailer.indexOf('async function sendPasswordReset');
      final developerStart = mailer.indexOf('async function requireDeveloper');
      final signupSource = mailer.substring(signupStart, resetStart);
      final resetSource = mailer.substring(resetStart, developerStart);

      expect(mailer, contains('captchaToken?: string'));
      expect(mailer, contains('MAIL_CAPTCHA_REQUIRED'));
      expect(mailer, contains('MAIL_CAPTCHA_SIGNUP_REQUIRED'));
      expect(mailer, contains('MAIL_CAPTCHA_RESET_REQUIRED'));
      expect(mailer, contains('MAIL_CAPTCHA_ALLOWED_HOSTNAMES'));
      expect(mailer, contains('MAIL_CAPTCHA_SIGNUP_ACTION'));
      expect(mailer, contains('MAIL_CAPTCHA_RESET_ACTION'));
      expect(mailer,
          contains('challenges.cloudflare.com/turnstile/v0/siteverify'));
      expect(mailer, contains('{ name: "HMAC", hash: "SHA-256" }'));
      expect(mailer, contains('consume_grace_mail_public_rate_limit'));
      expect(mailer, contains('new MailHttpError('));
      expect(mailer, contains('429'));
      expect(mailer, contains('"Retry-After"'));
      expect(mailer, isNot(contains('existing_account')),
          reason: 'public signup must not disclose account existence');
      expect(
        signupSource.indexOf('verifyPublicMailCaptcha'),
        lessThan(signupSource.indexOf('auth.admin.generateLink')),
      );
      expect(
        signupSource.indexOf('consumePublicMailRateLimit'),
        lessThan(signupSource.indexOf('auth.admin.generateLink')),
      );
      expect(
        resetSource.indexOf('verifyPublicMailCaptcha'),
        lessThan(resetSource.indexOf('auth.admin.generateLink')),
      );
      expect(
        resetSource.indexOf('consumePublicMailRateLimit'),
        lessThan(resetSource.indexOf('auth.admin.generateLink')),
      );
      expect(resetSource, contains('Public recovery must not reveal'));
      expect(resetSource, contains('return jsonResponse({ ok: true });'));
      expect(resetSource, isNot(contains('provider: "resend"')));
      expect(resetSource, isNot(contains('id: resendId')));

      expect(authFlow, contains("'captchaToken': captchaToken!.trim()"));
      expect(authFlow, isNot(contains('sendDefaultPasswordResetEmail')));
      expect(authFlow, isNot(contains('resetPasswordForEmail')));
    });

    test('deployment guide preserves migration-first and CAPTCHA rollout order',
        () {
      final docs = File('docs/resend-email-setup.md').readAsStringSync();
      final normalizedDocs = docs.replaceAll(RegExp(r'\s+'), ' ');

      expect(docs, contains('Required deployment order'));
      expect(normalizedDocs, contains('Do not deploy the function first'));
      expect(docs, contains('MAIL_RATE_LIMIT_PEPPER'));
      expect(docs, contains('CAPTCHA is off by default'));
      expect(docs, contains('MAIL_CAPTCHA_SIGNUP_REQUIRED'));
      expect(docs, contains('MAIL_CAPTCHA_RESET_REQUIRED'));
      expect(docs, contains('--no-verify-jwt'));
    });
  });
}
