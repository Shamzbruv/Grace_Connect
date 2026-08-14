import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/access/app_access_context.dart';
import 'package:grace_connect/access/app_feature.dart';
import 'package:grace_connect/models/church_subscription_management.dart';
import 'package:grace_connect/models/user_profile.dart';
import 'package:grace_connect/services/church_subscription_service.dart';
import 'package:grace_connect/services/membership_service.dart';

void main() {
  group('church subscription pricing', () {
    test('selects every tier at exact boundaries', () {
      const expectations = <int, String>{
        0: 'tier_0_50',
        50: 'tier_0_50',
        51: 'tier_51_100',
        100: 'tier_51_100',
        101: 'tier_101_150',
        150: 'tier_101_150',
        151: 'tier_151_200',
        200: 'tier_151_200',
        201: 'tier_201_300',
        300: 'tier_201_300',
        301: 'tier_301_400',
        400: 'tier_301_400',
        401: 'tier_401_500',
        500: 'tier_401_500',
        501: 'tier_501_700',
        700: 'tier_501_700',
        701: 'tier_701_900',
        900: 'tier_701_900',
        901: 'tier_901_1000',
        1000: 'tier_901_1000',
        1001: 'enterprise_1001_plus',
        5000: 'enterprise_1001_plus',
      };

      for (final entry in expectations.entries) {
        expect(
          ChurchSubscriptionTier.forMemberCount(entry.key).code,
          entry.value,
          reason: 'member count ${entry.key}',
        );
      }
    });

    test('fixed USD prices and bracketed JMD references are exact', () {
      expect(
        ChurchSubscriptionTier.all.map((tier) => tier.monthlyUsd).toList(),
        [17, 34, 51, 68, 85, 102, 119, 136, 153, 170, null],
      );
      expect(
        ChurchSubscriptionTier.all.map((tier) => tier.monthlyJmd).toList(),
        [
          2689,
          5377,
          8066,
          10755,
          13444,
          16132,
          18821,
          21510,
          24199,
          26887,
          null,
        ],
      );
      expect(
        ChurchSubscriptionTier.forMemberCount(1).priceLabel,
        'US\$17 (J\$2,689)',
      );
      expect(
        ChurchSubscriptionTier.forMemberCount(1001).priceLabel,
        'Enterprise / Custom (Custom Quote)',
      );
    });
  });

  group('subscription access', () {
    test('account management remains reachable when subscription is inactive',
        () {
      const membership = MembershipContext(
        authenticated: true,
        hasProfile: true,
        accountStatus: 'active',
        membershipStatus: 'active',
        churchId: 'church-1',
        churchName: 'Grace Church',
        hasPendingChurchApplication: false,
      );
      const subscription = ChurchSubscriptionContext(
        churchId: 'church-1',
        status: 'inactive',
        isActive: false,
      );
      const access = AppAccessContext(
        membership: membership,
        subscription: subscription,
      );

      expect(access.canUse(AppFeature.subscriptionManagement), isTrue);
      expect(access.canUse(AppFeature.churchFinance), isFalse);
    });

    test('all requested management roles and explicit privilege are visible',
        () {
      const roles = [
        'Pastor',
        'Senior Pastor',
        'Assistant Pastor',
        'Acting Pastor',
        'Church Admin',
        'Church Administrator',
        'Admin',
        'Administrator',
        'Treasurer',
        'Financial Secretary',
        'Finance',
        'Finance Officer',
        'Accountant',
      ];
      for (final role in roles) {
        expect(
          ChurchSubscriptionService.canManageForProfile(_profile(role: role)),
          isTrue,
          reason: role,
        );
      }

      expect(
        ChurchSubscriptionService.canManageForProfile(
          _profile(
            role: 'Member',
            privileges: const ['manageChurchSubscription'],
          ),
        ),
        isTrue,
      );
      expect(
        ChurchSubscriptionService.canManageForProfile(
          _profile(role: 'Member'),
        ),
        isFalse,
      );
    });
  });

  test('backend is RPC-only, tier-safe, bounded, and membership-authorized',
      () {
    final migration = File(
      'supabase/migrations/20260811160000_church_subscription_management.sql',
    ).readAsStringSync();
    final screen = File(
      'lib/screens/subscription/subscription_screen.dart',
    ).readAsStringSync();
    final menu = File('lib/widgets/app_bottom_menu.dart').readAsStringSync();
    final settings = File('lib/screens/settings/settings_home_screen.dart')
        .readAsStringSync();
    final developerService =
        File('lib/services/developer_service.dart').readAsStringSync();
    final subscriptionService =
        File('lib/services/church_subscription_service.dart')
            .readAsStringSync();
    final developerConsole = File(
      'lib/screens/developer/developer_console_screen.dart',
    ).readAsStringSync();

    expect(
      File('lib/providers/subscription_provider.dart').existsSync(),
      isFalse,
    );
    expect(screen, isNot(contains('Card Number')));
    expect(screen, isNot(contains('CVV')));
    expect(screen, isNot(contains('isPremium')));
    expect(screen, contains('no card details, payment links'));
    expect(screen, contains('JMD amounts in brackets are approximate'));
    expect(screen, contains('ACCOUNT MANAGEMENT ONLY'));
    expect(screen, contains('Purchasing and enrollment are unavailable'));
    expect(screen, contains('pricing table is read-only'));
    expect(screen, contains('Plan contact name'));
    expect(screen, contains('Plan contact email'));
    expect(screen, isNot(contains('Billing contact name')));
    expect(screen, isNot(contains('Billing contact email')));
    expect(screen, isNot(contains('Request this subscription')));
    expect(screen, isNot(contains('Request plan assessment')));
    expect(screen, isNot(contains('Request custom assessment')));
    expect(screen, isNot(contains("requestType: 'new_subscription'")));
    expect(screen, isNot(contains("requestType: 'change_plan'")));
    expect(screen, isNot(contains("requestType: 'enterprise_quote'")));
    expect(
      subscriptionService,
      contains("requestType != 'billing_support'"),
    );
    expect(
      subscriptionService,
      contains("'p_channel': 'android_account_management'"),
    );
    expect(
        developerService, isNot(contains('developer_set_church_subscription')));
    expect(developerService,
        isNot(contains('developer_clear_church_subscription')));
    expect(developerConsole, isNot(contains('Free 1 month')));
    expect(developerConsole, isNot(contains('Turn subscription off')));
    expect(menu, contains("route: '/subscription'"));
    expect(settings, contains("'/subscription'"));

    expect(migration, contains("cm.membership_status = 'active'"));
    expect(migration, contains('cm.church_id = any'));
    expect(migration, contains("'Church Administrator'"));
    expect(
        migration, contains("has_app_privilege('manageChurchSubscription')"));
    expect(
      migration,
      contains("selected_plan_code <> (calculated_tier ->> 'tierCode')"),
    );
    expect(
      migration,
      contains('p_monthly_usd <> fixed_usd'),
    );
    expect(
      migration,
      contains('p_monthly_jmd <> fixed_jmd'),
    );
    expect(
      migration,
      contains('char_length(contact_email) between 3 and 320'),
    );
    expect(migration, contains('auto_renews = false'));
    expect(migration, contains('auto_converts = false'));
    expect(migration, contains("'requestDoesNotCharge', true"));
    expect(migration, contains("'billingCycle', 'monthly'"));
    expect(
      migration,
      contains(
          'requested_by uuid references auth.users(id) on delete set null'),
    );
    expect(migration, isNot(contains('requested_by uuid not null')));
    expect(migration, contains("cs.billing_state in ('paid', 'invoiced')"));
    expect(
      migration,
      contains('Duplicate church subscription aliases detected.'),
    );
    expect(
      migration,
      contains('church_subscriptions_prevent_alias_duplicate'),
    );
    expect(
      migration,
      contains('from public.canonical_church_subscriptions() cs'),
    );
    expect(
      migration,
      contains(
        'where cs.church_id = any(public.subscription_church_ids(target_church_id))',
      ),
    );
    expect(
      migration,
      contains("'churchId', canonical_church_id"),
    );
    expect(
      migration,
      contains(
          "public.subscription_request_to_json(r) - 'developerNotes' - 'assignedTo'"),
    );
    expect("- 'developerNotes'".allMatches(migration).length, 2);
    expect("- 'assignedTo'".allMatches(migration).length, 2);
    expect(
      migration,
      contains(
        'update public.church_subscriptions cs\n'
        '  set last_request_id = request_row.id,',
      ),
    );
    final submitRpc = migration.substring(
      migration.indexOf(
        'create or replace function public.submit_church_subscription_request',
      ),
      migration.indexOf(
        'create or replace function public.developer_list_subscription_requests',
      ),
    );
    expect(submitRpc, isNot(contains('set billing_state')));
    expect(
      submitRpc,
      contains("normalized_type not in ('billing_support', 'cancellation')"),
    );
    expect(
      submitRpc,
      contains(
        "lower(trim(coalesce(p_channel, ''))) <> 'android_account_management'",
      ),
    );
    expect(
      submitRpc,
      contains(
        'Billing support and cancellation are available only for an existing church subscription.',
      ),
    );
    expect(submitRpc, isNot(contains("'new_subscription',\n")));
    expect(submitRpc, isNot(contains("'change_plan',\n")));
    expect(submitRpc, isNot(contains("'enterprise_quote',\n")));
    final eventRpc = migration.substring(
      migration.indexOf(
        'create or replace function public.developer_record_subscription_event',
      ),
      migration.indexOf(
        'create or replace function public.developer_get_financial_dashboard',
      ),
    );
    expect(eventRpc, contains("when 'cancelled' then 'cancelled'"));
    expect(
      eventRpc,
      contains('Note events do not change subscription status.'),
    );
    expect(
      eventRpc,
      contains('normalized_status <> expected_status'),
    );
    expect(
      migration,
      contains('p_monthly_usd integer default null'),
    );
    expect(
      migration,
      contains(
        'drop function if exists public.submit_church_subscription_request(\n'
        '  text, text, text, text, text, text\n'
        ');',
      ),
    );
    expect(
      migration,
      contains(
        'revoke all on function public.church_subscription_member_count(text) from public, anon, authenticated;',
      ),
    );
    expect(
      migration,
      isNot(contains(
        'grant execute on function public.church_subscription_member_count(text) to authenticated',
      )),
    );
    expect(
      migration,
      contains(
        'revoke all on function public.developer_set_church_subscription(text, text, text, integer, text)',
      ),
    );
    expect(
      migration,
      contains(
        'revoke all on function public.developer_clear_church_subscription(text, text)',
      ),
    );
  });
}

UserProfile _profile({
  required String role,
  List<String> privileges = const [],
}) {
  return UserProfile(
    uid: 'user-1',
    email: 'finance@example.com',
    fullName: 'Finance User',
    phoneNumber: '',
    placeId: 'church-1',
    placeName: 'Grace Church',
    roles: [role],
    appPrivileges: privileges,
    joinDate: DateTime(2026),
  );
}
