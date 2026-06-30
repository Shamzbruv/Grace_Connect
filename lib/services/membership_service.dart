import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_service.dart';

class MembershipLoadStatus {
  static const ready = 'ready';
  static const backendUnavailable = 'backend_unavailable';
  static const permissionDenied = 'permission_denied';
  static const migrationMismatch = 'migration_mismatch';
  static const unexpectedResponse = 'unexpected_response';
}

class MembershipContext {
  final bool authenticated;
  final bool hasProfile;
  final String accountStatus;
  final String membershipStatus;
  final String? membershipId;
  final String? churchId;
  final String? churchName;
  final String? churchStatus;
  final String? decisionReason;
  final bool hasPendingChurchApplication;
  final String? churchApplicationStatus;
  final String loadStatus;
  final String? loadError;

  const MembershipContext({
    required this.authenticated,
    required this.hasProfile,
    required this.accountStatus,
    required this.membershipStatus,
    this.membershipId,
    this.churchId,
    this.churchName,
    this.churchStatus,
    this.decisionReason,
    required this.hasPendingChurchApplication,
    this.churchApplicationStatus,
    this.loadStatus = MembershipLoadStatus.ready,
    this.loadError,
  });

  bool get hasLoadError => loadStatus != MembershipLoadStatus.ready;

  String get loadErrorTitle {
    return switch (loadStatus) {
      MembershipLoadStatus.permissionDenied => 'Membership Access Blocked',
      MembershipLoadStatus.migrationMismatch => 'Membership Setup Mismatch',
      MembershipLoadStatus.unexpectedResponse => 'Membership Setup Mismatch',
      _ => 'Membership Unavailable',
    };
  }

  String get loadErrorMessage {
    return switch (loadStatus) {
      MembershipLoadStatus.permissionDenied =>
        'We could not confirm your church access because the server denied the membership lookup. Please try again or contact support.',
      MembershipLoadStatus.migrationMismatch ||
      MembershipLoadStatus.unexpectedResponse =>
        'Grace Connect could not read the membership setup from the server. Please try again after the latest backend update is applied.',
      _ =>
        'Grace Connect could not load your membership right now. Check your connection and try again.',
    };
  }

  bool get isAccountRestricted =>
      accountStatus == 'suspended' ||
      accountStatus == 'disabled' ||
      accountStatus == 'deleted' ||
      accountStatus == 'deletion_requested';

  bool get hasActiveMembership =>
      membershipStatus == 'active' && (churchId ?? '').isNotEmpty;

  bool get hasPendingMembership => membershipStatus == 'pending';

  bool get hasBlockedMembership =>
      membershipStatus == 'declined' || membershipStatus == 'removed';

  factory MembershipContext.fromMap(Map<String, dynamic> data) {
    return MembershipContext(
      authenticated: data['authenticated'] == true,
      hasProfile: data['hasProfile'] == true,
      accountStatus: (data['accountStatus'] ?? 'active').toString(),
      membershipStatus: (data['membershipStatus'] ?? 'none').toString(),
      membershipId: data['membershipId']?.toString(),
      churchId: data['churchId']?.toString(),
      churchName: data['churchName']?.toString(),
      churchStatus: data['churchStatus']?.toString(),
      decisionReason: data['decisionReason']?.toString(),
      hasPendingChurchApplication: data['hasPendingChurchApplication'] == true,
      churchApplicationStatus: data['churchApplicationStatus']?.toString(),
      loadStatus: (data['loadStatus'] ?? MembershipLoadStatus.ready).toString(),
      loadError: data['loadError']?.toString(),
    );
  }

  static const unauthenticated = MembershipContext(
    authenticated: false,
    hasProfile: false,
    accountStatus: 'active',
    membershipStatus: 'none',
    hasPendingChurchApplication: false,
  );

  factory MembershipContext.loadFailed({
    required String status,
    Object? error,
  }) {
    return MembershipContext(
      authenticated: true,
      hasProfile: true,
      accountStatus: 'active',
      membershipStatus: 'unknown',
      hasPendingChurchApplication: false,
      loadStatus: status,
      loadError: error?.toString(),
    );
  }
}

class MembershipService {
  MembershipService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> getRequiredPolicies(
      String flowType) async {
    final response = await _client.rpc(
      'get_active_policy_documents',
      params: {'p_flow_type': flowType},
    );
    if (response is List) {
      return List<Map<String, dynamic>>.from(response);
    }
    return [];
  }

  Future<void> acceptPolicies(
    List<Map<String, dynamic>> policies, {
    required String source,
    Map<String, dynamic> metadata = const {},
  }) async {
    for (final policy in policies) {
      await _client.rpc('accept_policy_document', params: {
        'target_document_key': policy['document_key'],
        'target_document_version': policy['document_version'],
        'acceptance_source': source,
        'metadata': metadata,
      });
    }
  }

  Future<MembershipContext> getCurrentContext() async {
    final user = _client.auth.currentUser;
    if (user == null) return MembershipContext.unauthenticated;

    try {
      final data = await _client.rpc('get_current_membership_context');
      if (data is Map<String, dynamic>) {
        return MembershipContext.fromMap(data);
      }
      if (data is Map) {
        return MembershipContext.fromMap(Map<String, dynamic>.from(data));
      }
      debugPrint('Membership context returned unexpected data: $data');
      return MembershipContext.loadFailed(
        status: MembershipLoadStatus.unexpectedResponse,
        error: 'Unexpected membership context response.',
      );
    } catch (error) {
      debugPrint('Membership context unavailable: $error');
      return MembershipContext.loadFailed(
        status: classifyContextError(error),
        error: error,
      );
    }
  }

  Stream<MembershipContext> watchCurrentContext() async* {
    final initial = await getCurrentContext();
    yield initial;

    final user = _client.auth.currentUser;
    if (user == null || initial.hasLoadError) return;

    try {
      await for (final _ in _client
          .from('church_memberships')
          .stream(primaryKey: ['id']).eq('user_id', user.id)) {
        yield await getCurrentContext();
      }
    } catch (error) {
      debugPrint('Membership context stream unavailable: $error');
      yield MembershipContext.loadFailed(
        status: classifyContextError(error),
        error: error,
      );
    }
  }

  static String classifyContextError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('permission denied') ||
        text.contains('row-level security') ||
        text.contains('rls') ||
        text.contains('42501') ||
        text.contains('403')) {
      return MembershipLoadStatus.permissionDenied;
    }
    if (text.contains('get_current_membership_context') ||
        text.contains('could not find the function') ||
        text.contains('function') && text.contains('not found') ||
        text.contains('schema cache') ||
        text.contains('ambiguous') ||
        text.contains('column') && text.contains('does not exist') ||
        text.contains('42703') ||
        text.contains('42883') ||
        text.contains('42725')) {
      return MembershipLoadStatus.migrationMismatch;
    }
    if (text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('connection') ||
        text.contains('network') ||
        text.contains('socket') ||
        text.contains('failed host lookup') ||
        text.contains('service unavailable') ||
        text.contains('bad gateway') ||
        text.contains('gateway timeout') ||
        text.contains('502') ||
        text.contains('503') ||
        text.contains('504')) {
      return MembershipLoadStatus.backendUnavailable;
    }
    return MembershipLoadStatus.backendUnavailable;
  }

  Future<void> requestMembership({
    required String churchId,
    String? message,
  }) async {
    final membershipId = await _client.rpc(
      'request_church_membership',
      params: {
        'target_church_id': churchId,
        'request_note': message,
      },
    );
    final cleanMembershipId = membershipId?.toString().trim() ?? '';
    if (cleanMembershipId.isNotEmpty) {
      unawaited(
        NotificationService().sendMembershipRequestPush(cleanMembershipId),
      );
    }
  }

  Future<void> cancelMembershipRequest() async {
    await _client.rpc('cancel_membership_request');
  }
}
