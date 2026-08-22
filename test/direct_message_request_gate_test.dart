import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/models/direct_message_request.dart';

void main() {
  group('direct-message request model', () {
    test('parses a denied request and exposes the exact 30-day retry date', () {
      final respondedAt = DateTime.parse('2026-08-21T18:30:00Z');
      final request = DirectMessageRequest.fromMap({
        'id': 'request-1',
        'sender_id': 'sender-1',
        'recipient_id': 'recipient-1',
        'reason': 'I would like prayer support.',
        'intended_message': 'Could you pray with me this week?',
        'status': 'denied',
        'response_message': 'I am not available right now.',
        'created_at': '2026-08-21T18:00:00Z',
        'responded_at': respondedAt.toIso8601String(),
      });

      expect(request.isDenied, isTrue);
      expect(request.isIncomingFor('recipient-1'), isTrue);
      expect(request.isOutgoingFor('sender-1'), isTrue);
      expect(
        request.retryAvailableAt!.toUtc(),
        respondedAt.add(const Duration(days: 30)),
      );
    });

    test('parses an idempotent acceptance response', () {
      final decision = DirectMessageRequestDecision.fromMap({
        'request': {
          'id': 'request-1',
          'sender_id': 'sender-1',
          'recipient_id': 'recipient-1',
          'reason': 'I would like prayer support.',
          'intended_message': 'Could you pray with me this week?',
          'status': 'accepted',
          'created_at': '2026-08-21T18:00:00Z',
          'responded_at': '2026-08-21T18:30:00Z',
        },
        'conversation_id': 'conversation-1',
        'message_id': 'message-1',
        'deduplicated': true,
      });

      expect(decision.request.isAccepted, isTrue);
      expect(decision.conversationId, 'conversation-1');
      expect(decision.messageId, 'message-1');
      expect(decision.deduplicated, isTrue);
    });
  });

  group('database consent gate', () {
    final migration = File(
      'supabase/migrations/20260822025626_cross_church_message_request_gate.sql',
    ).readAsStringSync();

    test('uses RPC-only writes, RLS, pair serialization, and cooldown', () {
      expect(
          migration,
          contains(
              'create table if not exists public.direct_message_requests'));
      expect(
          migration,
          contains(
              'alter table public.direct_message_requests enable row level security'));
      expect(
          migration,
          contains(
              'revoke all on table public.direct_message_requests from public, anon, authenticated'));
      expect(migration, contains('direct_message_requests_one_pending_idx'));
      expect(migration, contains('pg_advisory_xact_lock'));
      expect(migration, contains("interval '30 days'"));
      expect(migration, contains('detail = \'MESSAGE_REQUEST_COOLDOWN\''));
      expect(
          migration,
          contains(
              'revoke insert, delete on table public.direct_conversations from authenticated'));
      expect(
          migration,
          contains(
              'public.can_send_direct_message_to_conversation(conversation_id)'));
      expect(
          migration,
          contains(
              'create table if not exists public.direct_message_request_push_deliveries'));
      expect(
          migration,
          contains(
              'create table if not exists public.bible_nudge_push_deliveries'));
      expect(migration, contains('attempt_count between 0 and 8'));
      expect(migration, contains("interval '7 days'"));
      expect(migration, contains("'message-request-push-delivery-retry'"));
    });

    test('acceptance is atomic, idempotent, and delivers the intended message',
        () {
      expect(migration, contains('for update;'));
      expect(migration,
          contains("target_request.status = 'accepted' and accept_request"));
      expect(migration, contains("'deduplicated', true"));
      expect(migration, contains("'message_request'"));
      expect(migration, contains('target_request.intended_message'));
      expect(migration, contains('delivered_message_id = initial_message.id'));
      expect(migration, contains('public.notify_on_direct_message()'));
    });

    test('legacy identity aliases do not duplicate or break conversations', () {
      expect(migration, contains('public.direct_message_identity_keys'));
      expect(migration,
          contains('c.member_ids && public.direct_message_identity_keys'));
      expect(migration,
          contains('public.resolve_direct_message_user_id(member_id)'));
      expect(
          migration, contains('public.direct_message_viewer_identity_keys()'));
    });

    test('security-definer functions use an empty search path', () {
      expect(migration, isNot(contains('set search_path = public')));
      final securityDefiners = RegExp(
        r"security definer\s+set search_path = ''",
        caseSensitive: false,
      ).allMatches(migration);
      final allSecurityDefiners = RegExp(
        r'\nsecurity definer',
        caseSensitive: false,
      ).allMatches(migration);
      expect(securityDefiners.length, allSecurityDefiners.length);
      expect(
        migration,
        contains('(select auth.uid()) in (first_user_id, second_user_id)'),
      );
    });

    test('Bible Nudges remain cross-church encouragement, not consent', () {
      final grantFunction = migration.substring(
        migration.indexOf(
            'create or replace function public.has_direct_message_grant'),
        migration.indexOf(
            'create or replace function public.direct_message_pair_is_blocked'),
      );
      expect(grantFunction,
          contains("g.source_type in ('message_request', 'manual')"));
      expect(grantFunction, isNot(contains("'bible_nudge'")));
      expect(migration, contains("where source_type = 'bible_nudge'"));
      expect(
          migration,
          contains(
              'public.can_send_bible_nudge(sender_id, recipient_id, church_id)'));
      expect(migration, contains('notify_bible_nudge_lifecycle'));
      expect(migration, contains('claim_due_bible_nudge_push_deliveries'));
      expect(migration,
          contains('insert into public.bible_nudge_push_deliveries'));
      expect(
        migration,
        contains(
          ') from public, anon, authenticated;\ngrant execute on function public.create_notification(',
        ),
      );
      final bibleNudgeService =
          File('lib/services/bible_nudge_service.dart').readAsStringSync();
      expect(bibleNudgeService, isNot(contains(".rpc('create_notification'")));
    });

    test('denial always discloses the 30-day cooldown', () {
      expect(
        migration,
        contains("end || ' You can request again in 30 days.'"),
      );
    });
  });

  group('client and push integration', () {
    final service =
        File('lib/services/direct_message_service.dart').readAsStringSync();
    final inbox =
        File('lib/screens/messages/inbox_screen.dart').readAsStringSync();
    final composer =
        File('lib/widgets/message_request_composer.dart').readAsStringSync();
    final bibleReader =
        File('lib/screens/bible/bible_reader_screen.dart').readAsStringSync();
    final profile = File('lib/screens/profile/public_profile_screen.dart')
        .readAsStringSync();
    final push = [
      File('supabase/functions/send-message-request-push/index.ts')
          .readAsStringSync(),
      File('supabase/functions/_shared/message_request_push.ts')
          .readAsStringSync(),
      File('supabase/functions/retry-message-request-pushes/index.ts')
          .readAsStringSync(),
    ].join('\n');

    test('conversation creation has no direct-table fallback', () {
      expect(service,
          contains(".rpc(\n        'get_or_create_direct_conversation'"));
      expect(service, isNot(contains(".from('direct_conversations').insert")));
      expect(service, contains('MessageRequestRequiredException'));
      expect(service, isNot(contains('kIsWeb || requestId')));
    });

    test('request UI requires a reason and intended first message', () {
      expect(composer, contains('Why do you want to message?'));
      expect(composer, contains('First message'));
      expect(composer, contains('This is delivered only if they accept.'));
      expect(inbox, contains("text: 'Requests'"));
      expect(inbox, contains('initialIndex: widget.initialTab'));
      expect(inbox, contains('request.isIncomingFor(authUserId)'));
      expect(inbox, contains('messageService.currentUserId'));
    });

    test('Bible verse and public-profile entry points use the same gate', () {
      expect(bibleReader, contains('showMessageRequestComposer('));
      expect(bibleReader, contains('initialMessage: text'));
      expect(profile, contains('showMessageRequestComposer('));
      expect(profile, contains('_messageService.getOrCreateConversation('));
    });

    test('push target and event are derived from the stored request', () {
      expect(push, contains('user.id !== senderId'));
      expect(push, contains('user.id !== recipientId'));
      expect(push, contains('status !== event'));
      expect(push, contains('row.conversation_id'));
      expect(push, contains('row.delivered_message_id'));
      expect(push, contains(r'topic: `user_${targetId}`'));
      expect(push, contains(r'idempotencyKey: `${row.id}:${event}`'));
      expect(push, contains('You can request again in 30 days.'));
      expect(push, contains('claim_message_request_push_delivery'));
      expect(push, contains('claim_due_message_request_push_deliveries'));
      expect(push, contains('claim_due_bible_nudge_push_deliveries'));
      expect(push, contains('complete_bible_nudge_push_delivery'));
      expect(push, contains('requireCronSecret'));
      expect(push, contains('/inbox?tab=requests'));
    });
  });
}
