import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChurchSubscriptionContext {
  const ChurchSubscriptionContext({
    required this.churchId,
    required this.status,
    required this.isActive,
    this.rawStatus,
    this.planCode,
    this.source,
    this.activeUntil,
    this.updatedAt,
    this.loadError,
  });

  final String? churchId;
  final String status;
  final String? rawStatus;
  final bool isActive;
  final String? planCode;
  final String? source;
  final DateTime? activeUntil;
  final DateTime? updatedAt;
  final String? loadError;

  bool get hasLoadError => loadError != null;

  factory ChurchSubscriptionContext.fromMap(Map<String, dynamic> data) {
    return ChurchSubscriptionContext(
      churchId: data['churchId']?.toString(),
      status: (data['status'] ?? 'inactive').toString(),
      rawStatus: data['rawStatus']?.toString(),
      isActive: data['isActive'] == true,
      planCode: data['planCode']?.toString(),
      source: data['source']?.toString(),
      activeUntil: _parseDate(data['activeUntil']),
      updatedAt: _parseDate(data['updatedAt']),
    );
  }

  factory ChurchSubscriptionContext.loadFailed(Object error) {
    return ChurchSubscriptionContext(
      churchId: null,
      status: 'inactive',
      isActive: false,
      loadError: error.toString(),
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

class ChurchSubscriptionService {
  ChurchSubscriptionService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<ChurchSubscriptionContext> getCurrentChurchSubscription({
    String? churchId,
  }) async {
    try {
      final data = await _client.rpc(
        'get_church_subscription_context',
        params: {'p_church_id': churchId},
      );
      if (data is Map<String, dynamic>) {
        return ChurchSubscriptionContext.fromMap(data);
      }
      if (data is Map) {
        return ChurchSubscriptionContext.fromMap(
          Map<String, dynamic>.from(data),
        );
      }
      throw StateError('Unexpected church subscription response: $data');
    } catch (error) {
      debugPrint('Church subscription context unavailable: $error');
      return ChurchSubscriptionContext.loadFailed(error);
    }
  }

  Future<ChurchSubscriptionContext> grantManualSubscription({
    required String churchId,
    required int months,
    String planCode = 'manual_free',
    String notes = 'Developer manual grant',
  }) async {
    final data = await _client.rpc(
      'developer_set_church_subscription',
      params: {
        'p_church_id': churchId,
        'p_status': 'active',
        'p_plan_code': planCode,
        'p_months': months,
        'p_notes': notes,
      },
    );
    if (data is Map<String, dynamic>) {
      return ChurchSubscriptionContext.fromMap(data);
    }
    return ChurchSubscriptionContext.fromMap(Map<String, dynamic>.from(data));
  }

  Future<ChurchSubscriptionContext> clearManualSubscription({
    required String churchId,
    String reason = 'Developer manual disable',
  }) async {
    final data = await _client.rpc(
      'developer_clear_church_subscription',
      params: {
        'p_church_id': churchId,
        'p_reason': reason,
      },
    );
    if (data is Map<String, dynamic>) {
      return ChurchSubscriptionContext.fromMap(data);
    }
    return ChurchSubscriptionContext.fromMap(Map<String, dynamic>.from(data));
  }
}
