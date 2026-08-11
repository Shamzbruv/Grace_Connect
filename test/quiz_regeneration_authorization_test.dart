import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('scheduled quiz refresh requires a mutation-capable developer role', () {
    final source = File(
      'supabase/functions/generate-daily-bible-quiz/index.ts',
    ).readAsStringSync();

    final roleSetStart = source.indexOf('const scheduledQuizMutationRoles');
    final authorizationStart = source.indexOf(
      'async function canRegenerateScheduledQuiz',
    );
    final publishStart = source.indexOf('async function publishQuiz');
    final authorization = source.substring(authorizationStart, publishStart);

    expect(roleSetStart, greaterThanOrEqualTo(0));
    expect(authorizationStart, greaterThan(roleSetStart));
    for (final role in const [
      'super_developer',
      'support_developer',
      'content_moderator',
      'security_admin',
    ]) {
      expect(source, contains('"$role"'));
    }
    expect(authorization, contains('scheduledQuizMutationRoles.has'));
    expect(
      source,
      contains('if (!(await canRegenerateScheduledQuiz(client, request)))'),
    );
    expect(source, contains('if (regenerating) {'));
    expect(source, contains('const cronAuthorized = hasCronSecret('));
    expect(source, isNot(contains('"read_only_support"')));
    expect(source, isNot(contains('"billing_support"')));
  });

  test('Flutter console gates replacement while retaining schedule preview',
      () {
    final source = File(
      'lib/screens/developer/developer_console_screen.dart',
    ).readAsStringSync();

    final roleSetStart = source.indexOf('const _scheduledQuizMutationRoles');
    final gateStart = source.indexOf('bool _canReplaceScheduledQuiz');
    final updateSubscriptionStart = source.indexOf(
      'Future<void> _updateSubscription',
    );
    final gate = source.substring(gateStart, updateSubscriptionStart);

    expect(roleSetStart, greaterThanOrEqualTo(0));
    expect(gateStart, greaterThan(roleSetStart));
    for (final role in const [
      'super_developer',
      'support_developer',
      'content_moderator',
      'security_admin',
    ]) {
      expect(source, contains("'$role'"));
    }
    expect(source, contains("session?['developer_role']"));
    expect(
        source, contains('final canReplace = _canReplaceScheduledQuiz(quiz)'));
    expect(source, contains('trailing: canReplace'));
    expect(
      source,
      contains('if (!_canReplaceScheduledQuiz(quiz))'),
    );
    expect(gate, contains('_scheduledQuizMutationRoles.contains'));
    expect(gate, contains("!= 'scheduled'"));
    expect(gate, contains('releaseAt.isAfter(DateTime.now())'));
    expect(gate, isNot(contains('read_only_support')));
    expect(gate, isNot(contains('billing_support')));

    // Schedule loading and rendering remain outside the mutation gate.
    expect(source, contains('_devService.getScheduledContent()'));
    expect(source, contains('Widget _buildScheduledContentTab()'));
  });
}
