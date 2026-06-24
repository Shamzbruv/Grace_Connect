import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  });

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
    );
  }

  static const unauthenticated = MembershipContext(
    authenticated: false,
    hasProfile: false,
    accountStatus: 'active',
    membershipStatus: 'none',
    hasPendingChurchApplication: false,
  );
}

class MembershipService {
  MembershipService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<Map<String, dynamic>>> getRequiredPolicies(String flowType) async {
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
    } catch (error) {
      debugPrint('Membership context unavailable: $error');
    }

    return const MembershipContext(
      authenticated: true,
      hasProfile: false,
      accountStatus: 'active',
      membershipStatus: 'none',
      hasPendingChurchApplication: false,
    );
  }

  Stream<MembershipContext> watchCurrentContext() async* {
    yield await getCurrentContext();

    final user = _client.auth.currentUser;
    if (user == null) return;

    yield* _client
        .from('church_memberships')
        .stream(primaryKey: ['id'])
        .eq('user_id', user.id)
        .asyncMap((_) => getCurrentContext());
  }

  Future<void> requestMembership({
    required String churchId,
    String? message,
  }) async {
    await _client.rpc(
      'request_church_membership',
      params: {
        'target_church_id': churchId,
        'request_note': message,
      },
    );
  }

  Future<void> cancelMembershipRequest() async {
    await _client.rpc('cancel_membership_request');
  }
}
