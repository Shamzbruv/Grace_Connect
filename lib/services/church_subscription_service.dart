import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/church_subscription_management.dart';
import '../models/user_profile.dart';

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

  static const Set<String> _managementRoles = {
    'pastor',
    'senior_pastor',
    'assistant_pastor',
    'acting_pastor',
    'church_admin',
    'church_administrator',
    'admin',
    'administrator',
    'treasurer',
    'financial_secretary',
    'finance',
    'finance_officer',
    'accountant',
  };

  static const Set<String> _managementPrivileges = {
    'manageChurchSubscription',
    'manageFinances',
  };

  /// This is an advisory visibility check only. Every read and write is also
  /// authorized server-side against the caller's active membership roles.
  static bool canManageForProfile(UserProfile? profile) {
    if (profile == null || profile.churchId.trim().isEmpty) return false;
    final normalizedRoles = profile.roles.map(_normalizeRole).toSet();
    return normalizedRoles.any(_managementRoles.contains) ||
        profile.appPrivileges.any(_managementPrivileges.contains);
  }

  static String _normalizeRole(String role) {
    return role
        .trim()
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

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

  Future<ChurchSubscriptionManagement> getManagement({
    String? churchId,
  }) async {
    final data = await _client.rpc(
      'get_church_subscription_management',
      params: {'p_church_id': churchId},
    );
    if (data is Map<String, dynamic>) {
      return ChurchSubscriptionManagement.fromMap(data);
    }
    if (data is Map) {
      return ChurchSubscriptionManagement.fromMap(
        Map<String, dynamic>.from(data),
      );
    }
    throw StateError('Unexpected subscription management response: $data');
  }

  Future<ChurchSubscriptionRequest> submitRequest({
    required String requestType,
    required String requestedTierCode,
    required String contactName,
    required String contactEmail,
    String? contactPhone,
    String? message,
  }) async {
    if (requestType != 'billing_support' && requestType != 'cancellation') {
      throw ArgumentError.value(
        requestType,
        'requestType',
        'The Android app only supports existing-plan account management.',
      );
    }
    final data = await _client.rpc(
      'submit_church_subscription_request',
      params: {
        'p_request_type': requestType,
        'p_requested_tier_code': requestedTierCode,
        'p_contact_name': contactName.trim(),
        'p_contact_email': contactEmail.trim(),
        'p_contact_phone': contactPhone?.trim(),
        'p_message': message?.trim(),
        'p_channel': 'android_account_management',
      },
    );
    if (data is Map<String, dynamic>) {
      return ChurchSubscriptionRequest.fromMap(data);
    }
    if (data is Map) {
      return ChurchSubscriptionRequest.fromMap(
        Map<String, dynamic>.from(data),
      );
    }
    throw StateError('Unexpected subscription request response: $data');
  }
}
