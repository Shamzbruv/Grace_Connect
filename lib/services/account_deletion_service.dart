import 'package:supabase_flutter/supabase_flutter.dart';

class AccountDeletionService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<String> requestDeletion({String? reason}) async {
    final result = await _supabase.rpc(
      'request_account_deletion',
      params: {'request_reason': reason?.trim()},
    );
    return result?.toString() ?? '';
  }
}
