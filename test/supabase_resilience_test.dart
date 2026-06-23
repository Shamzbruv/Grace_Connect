import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/services/supabase_resilience.dart';

void main() {
  group('SupabaseResilience', () {
    test('detects expired JWT realtime errors', () {
      expect(
        SupabaseResilience.isAuthSessionError(
          Exception('InvalidJWTToken: Token has expired 104 seconds ago'),
        ),
        isTrue,
      );
      expect(
        SupabaseResilience.isAuthSessionError(
          Exception('RealtimeSubscribeStatus.channelError'),
        ),
        isFalse,
      );
    });
  });
}
