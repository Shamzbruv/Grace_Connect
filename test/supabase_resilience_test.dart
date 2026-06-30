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

    test('detects transient network and edge function failures', () {
      expect(
        SupabaseResilience.isTransientNetworkError(
          Exception('SocketException: Software caused connection abort'),
        ),
        isTrue,
      );
      expect(
        SupabaseResilience.isTransientNetworkError(
          Exception('HttpException: Connection closed while receiving data'),
        ),
        isTrue,
      );
      expect(
        SupabaseResilience.isTransientNetworkError(
          Exception('FunctionException(status: 404, details: not found)'),
        ),
        isTrue,
      );
      expect(
        SupabaseResilience.isTransientNetworkError(
          StateError('A real local state bug'),
        ),
        isFalse,
      );
    });
  });
}
