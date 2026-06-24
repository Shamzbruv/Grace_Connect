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
}
