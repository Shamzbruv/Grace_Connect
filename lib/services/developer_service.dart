import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import 'church_subscription_service.dart';

class DeveloperService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<bool> hasDeveloperAccess() async {
    try {
      return await getDeveloperSession() != null;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getDeveloperSession() async {
    final data = await _supabase.rpc('developer_get_session');
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  Future<Map<String, dynamic>> getPlatformStats() async {
    final data = await _supabase.rpc('developer_get_dashboard');
    final dashboard = data is Map<String, dynamic>
        ? data
        : Map<String, dynamic>.from(data as Map);

    return {
      'totalUsers': dashboard['total_users'] ?? 0,
      'totalChurches': dashboard['total_churches'] ?? 0,
      'approvedChurches': dashboard['approved_churches'] ?? 0,
      'pendingChurches': dashboard['pending_churches'] ?? 0,
      'subscribedChurches': dashboard['subscribed_churches'] ?? 0,
      'unsubscribedChurches': dashboard['unsubscribed_churches'] ?? 0,
      'developerAccounts': dashboard['developer_accounts'] ?? 0,
      'serverHealth': 'Connected',
    };
  }

  Future<List<Map<String, dynamic>>> getAllChurches() async {
    final data = await _supabase.rpc(
      'developer_list_churches',
      params: {'p_status': null, 'p_search': null},
    );
    if (data is List) {
      return data.map((row) => Map<String, dynamic>.from(row)).toList();
    }
    return const [];
  }

  Future<List<UserProfile>> searchUsersGlobal(String email) async {
    final data = await _supabase.rpc(
      'developer_search_users',
      params: {'p_search': email, 'p_church_id': null},
    );

    if (data is List) {
      return data
          .map((row) => UserProfile.fromMap(Map<String, dynamic>.from(row)))
          .toList();
    }
    return const [];
  }

  Future<List<Map<String, dynamic>>> getReportedUsers() async {
    final data = await _supabase.rpc('developer_list_reported_users');
    if (data is List) {
      return data.map((row) => Map<String, dynamic>.from(row)).toList();
    }
    return const [];
  }

  Future<void> updateContentReportStatus({
    required String reportId,
    required String status,
  }) async {
    await _supabase.rpc(
      'developer_update_content_report_status',
      params: {
        'p_report_id': reportId,
        'p_status': status,
      },
    );
  }

  Future<ChurchSubscriptionContext> grantFreeSubscription({
    required String churchId,
    required int months,
  }) {
    return ChurchSubscriptionService(client: _supabase)
        .grantManualSubscription(churchId: churchId, months: months);
  }

  Future<ChurchSubscriptionContext> clearSubscription({
    required String churchId,
  }) {
    return ChurchSubscriptionService(client: _supabase)
        .clearManualSubscription(churchId: churchId);
  }
}
