import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/services/grace_rooms_service.dart';

void main() {
  group('Grace Rooms live presence', () {
    test('maps the live aggregate separately from lifetime participants', () {
      final room = GraceRoom.fromMap({
        'id': 'room-1',
        'title': 'Peace in the Storm',
        'participant_count': 19,
        'live_participant_count': 3,
      });

      expect(room.participantCount, 19);
      expect(room.liveParticipantCount, 3);
    });

    test('presence migration expires heartbeats and schedules invitations', () {
      final migration = File(
        'supabase/migrations/20260805120000_grace_rooms_live_presence_and_circle_retirement.sql',
      ).readAsStringSync();
      final invitationFunction = File(
        'supabase/functions/send-grace-room-invitations/index.ts',
      ).readAsStringSync();

      expect(migration, contains("interval '2 minutes'"));
      expect(migration, contains('touch_grace_room_presence'));
      expect(migration, contains('leave_grace_room'));
      expect(migration, contains('refresh-grace-room-presence'));
      expect(migration, contains('grace-room-support-invitations'));
      expect(migration, contains('unique (invitation_date, invitation_slot)'));
      expect(migration, contains('claim_grace_room_invitation_run'));
      expect(migration, contains("interval '10 minutes'"));
      expect(migration, contains('in_app_created_at'));
      expect(migration, contains("'30,45 0 * * 1,3,5'"));
      expect(
        migration,
        contains('create_grace_room_invitation_notifications'),
      );
      expect(invitationFunction, contains('DAILY_QUIZ_CRON_SECRET'));
      expect(invitationFunction, contains('grace_room_invitation'));
      expect(invitationFunction, contains('graceconnect_all'));
      expect(
        invitationFunction,
        contains('"claim_grace_room_invitation_run"'),
      );
      expect(
        invitationFunction,
        contains('"create_grace_room_invitation_notifications"'),
      );
    });
  });

  test('Grace Circles are removed from the current application surface', () {
    final currentSources = <String>[
      'lib/main.dart',
      'lib/access/app_feature.dart',
      'lib/access/app_access_context.dart',
      'lib/widgets/app_bottom_menu.dart',
      'lib/screens/main/main_tabs_screen.dart',
      'lib/services/community_service.dart',
      'lib/services/notification_service.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    expect(currentSources, isNot(contains('Grace Circles')));
    expect(currentSources, isNot(contains('/grace_circles')));
    expect(currentSources, isNot(contains('grace_circle_members')));
    expect(
        File('lib/services/grace_circles_service.dart').existsSync(), isFalse);
    final screensDirectory = Directory('lib/screens/grace_circles');
    expect(
      !screensDirectory.existsSync() || screensDirectory.listSync().isEmpty,
      isTrue,
    );
  });

  test('Grace Room invitation taps use the room route, not the delivery run',
      () {
    final notifications =
        File('lib/services/notification_service.dart').readAsStringSync();
    final routeGuard = notifications.indexOf(
      "if (normalizedType == 'grace_room_invitation')",
    );
    final genericRoomRouting = notifications.indexOf(
      "cleanEntityTable == 'grace_rooms'",
    );

    expect(routeGuard, greaterThanOrEqualTo(0));
    expect(genericRoomRouting, greaterThan(routeGuard));
    expect(
      notifications.substring(routeGuard, genericRoomRouting),
      contains('normalizeRoute(route)'),
    );
  });

  test('Circle retirement preserves non-Circle feed database contracts', () {
    final migration = File(
      'supabase/migrations/20260805120000_grace_rooms_live_presence_and_circle_retirement.sql',
    ).readAsStringSync();
    final executableMigration = migration
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('--'))
        .join('\n');

    expect(
      executableMigration,
      matches(RegExp(
        r"delete from public\.community_posts\s+"
        r"where circle_id is not null\s+or scope = 'circle';",
      )),
    );
    expect(
      executableMigration,
      contains('constraint community_posts_scope_not_circle'),
    );
    expect(
      executableMigration,
      isNot(
          contains('drop table if exists public.grace_circle_members cascade')),
    );
    expect(
      executableMigration,
      isNot(contains('drop table if exists public.grace_circles cascade')),
    );

    final dropColumnStart = executableMigration.indexOf(
      'alter table public.community_posts\n  drop column if exists circle_id;',
    );
    final dropColumnEnd = executableMigration.indexOf(';', dropColumnStart) + 1;
    final dropTablesEnd = executableMigration.indexOf(
          'drop table if exists public.grace_circles;',
          dropColumnEnd,
        ) +
        'drop table if exists public.grace_circles;'.length;
    final auditGuardStart = executableMigration.indexOf(
      'do \$\$\ndeclare\n  dangling_objects text;',
      dropTablesEnd,
    );
    expect(dropColumnStart, greaterThanOrEqualTo(0));
    expect(dropTablesEnd, greaterThan(dropColumnEnd));
    expect(auditGuardStart, greaterThan(dropTablesEnd));

    final survivingContracts = executableMigration.substring(
      dropTablesEnd,
      auditGuardStart,
    );
    for (final policyName in const <String>[
      'Authenticated users view visible community posts',
      'Users create visible community posts',
      'Authenticated users create visible community comments',
    ]) {
      expect(survivingContracts, contains('create policy "$policyName"'));
    }
    expect(
      survivingContracts,
      contains('create or replace function public.toggle_community_post_like'),
    );
    expect(survivingContracts, contains("and p.scope <> 'circle'"));
    expect(survivingContracts, isNot(contains('grace_circle_members')));
    expect(survivingContracts, isNot(contains('grace_circles')));
    expect(survivingContracts, isNot(contains('circle_id')));
    expect(survivingContracts, isNot(contains('target_circle_id')));

    final auditGuard = executableMigration.substring(auditGuardStart);
    expect(auditGuard, contains('pg_get_functiondef'));
    expect(auditGuard, contains('from pg_policy'));
    expect(auditGuard, contains('from pg_views'));
    expect(auditGuard, contains('from pg_matviews'));
    expect(auditGuard,
        contains('Grace Circle retirement left dangling database references'));
  });

  test('community video surfaces use the lifecycle-safe shared player', () {
    final player =
        File('lib/widgets/community_video_player.dart').readAsStringSync();
    final feed = File('lib/screens/community/community_feed_screen.dart')
        .readAsStringSync();
    final detail = File('lib/screens/community/post_detail_screen.dart')
        .readAsStringSync();

    expect(player, contains('with WidgetsBindingObserver'));
    expect(player, contains('VisibilityDetector'));
    expect(player, contains('VideoViewType.textureView'));
    expect(player, contains('WidgetsBinding.instance.endOfFrame'));
    expect(player, contains('_VideoPlaybackPositionStore'));
    expect(player, contains('controller.value.hasError'));
    expect(player, contains('_resumeWhenVisible = false'));
    expect(player, contains('await controller.pause().catchError'));
    expect(feed, contains('CommunityVideoPlayer('));
    expect(detail, contains('CommunityVideoPlayer('));
    expect(feed, isNot(contains('VideoPlayerController.networkUrl')));
    expect(detail, isNot(contains('VideoPlayerController.networkUrl')));
  });

  test('all repository email transports enforce Grace Connect branding', () {
    final flutterMailer =
        File('lib/services/email_service.dart').readAsStringSync();
    final edgeMailer =
        File('supabase/functions/grace-mailer/index.ts').readAsStringSync();
    final firebaseFunctions = File('functions/index.js').readAsStringSync();
    final config = File('supabase/config.toml').readAsStringSync();

    expect(flutterMailer, contains('data-grace-email="true"'));
    expect(flutterMailer, contains('_brandHtmlBody'));
    expect(flutterMailer, contains("'action': 'send-app-email'"));
    expect(flutterMailer, isNot(contains('RESEND_API_KEY')));
    expect(flutterMailer, isNot(contains('api.resend.com')));
    expect(edgeMailer, contains('queuedEmailBody'));
    expect(edgeMailer, contains('brandedEmail'));
    expect(edgeMailer, contains('requireManagedEmailSender'));
    expect(firebaseFunctions, contains('graceConnectEmailTemplate'));
    expect(firebaseFunctions, contains('data-grace-email="true"'));
    expect(config, contains('[auth.email.template.confirmation]'));
    expect(config, contains('[auth.email.template.recovery]'));

    for (final template
        in Directory('supabase/templates').listSync().whereType<File>()) {
      expect(
        template.readAsStringSync(),
        contains('data-grace-email="true"'),
        reason: '${template.path} must use the decorated app template.',
      );
    }
  });
}
