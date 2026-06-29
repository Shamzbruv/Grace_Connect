import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/services/membership_service.dart';

void main() {
  group('MembershipService error handling', () {
    test('classifies RPC and schema problems as migration mismatches', () {
      expect(
        MembershipService.classifyContextError(
          Exception(
              'Could not find the function get_current_membership_context'),
        ),
        MembershipLoadStatus.migrationMismatch,
      );
      expect(
        MembershipService.classifyContextError(
          Exception('column "church_name" does not exist'),
        ),
        MembershipLoadStatus.migrationMismatch,
      );
    });

    test('classifies RLS problems as permission denied', () {
      expect(
        MembershipService.classifyContextError(
          Exception('new row violates row-level security policy'),
        ),
        MembershipLoadStatus.permissionDenied,
      );
    });

    test('load failures do not masquerade as missing profiles', () {
      final context = MembershipContext.loadFailed(
        status: MembershipLoadStatus.backendUnavailable,
        error: Exception('network timeout'),
      );

      expect(context.authenticated, isTrue);
      expect(context.hasProfile, isTrue);
      expect(context.hasLoadError, isTrue);
      expect(context.loadErrorTitle, 'Membership Unavailable');
    });
  });
}
