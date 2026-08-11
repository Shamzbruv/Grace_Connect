import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
      MembershipLoadStatus.migrationMismatch => 'Membership Unavailable',
      MembershipLoadStatus.unexpectedResponse => 'Membership Unavailable',
      _ => 'Membership Unavailable',
    };
  }

  String get loadErrorMessage {
    return switch (loadStatus) {
      MembershipLoadStatus.permissionDenied =>
        'We could not confirm your church access because the server denied the membership lookup. Please try again or contact support.',
      MembershipLoadStatus.migrationMismatch ||
      MembershipLoadStatus.unexpectedResponse =>
        'Grace Connect could not verify your membership right now. No account changes were made. Please check again in a moment.',
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

  Map<String, dynamic> toMap() {
    return {
      'authenticated': authenticated,
      'hasProfile': hasProfile,
      'accountStatus': accountStatus,
      'membershipStatus': membershipStatus,
      if (membershipId != null) 'membershipId': membershipId,
      if (churchId != null) 'churchId': churchId,
      if (churchName != null) 'churchName': churchName,
      if (churchStatus != null) 'churchStatus': churchStatus,
      if (decisionReason != null) 'decisionReason': decisionReason,
      'hasPendingChurchApplication': hasPendingChurchApplication,
      if (churchApplicationStatus != null)
        'churchApplicationStatus': churchApplicationStatus,
      'loadStatus': loadStatus,
      if (loadError != null) 'loadError': loadError,
    };
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
  static const String _cacheKeyPrefix = 'membership_context_v1';
  static const Duration _cacheMaxAge = Duration(minutes: 15);

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
      final data = await _loadCurrentContextWithRetry();
      if (data is Map<String, dynamic>) {
        final context = MembershipContext.fromMap(data);
        unawaited(_cacheContext(user.id, context));
        return context;
      }
      if (data is Map) {
        final context =
            MembershipContext.fromMap(Map<String, dynamic>.from(data));
        unawaited(_cacheContext(user.id, context));
        return context;
      }
      debugPrint('Membership context returned unexpected data: $data');
      final cached = await _readCachedContext(user.id);
      if (cached != null) return cached;
      final profileFallback = await _readProfileFallbackContext(user.id);
      if (profileFallback != null) {
        unawaited(_cacheContext(user.id, profileFallback));
        return profileFallback;
      }
      return MembershipContext.loadFailed(
        status: MembershipLoadStatus.unexpectedResponse,
        error: 'Unexpected membership context response.',
      );
    } catch (error) {
      debugPrint('Membership context unavailable: $error');
      final status = classifyContextError(error);
      if (status != MembershipLoadStatus.permissionDenied) {
        final cached = await _readCachedContext(user.id);
        if (cached != null) {
          debugPrint(
              'Using cached membership context after transient failure.');
          return cached;
        }
        final profileFallback = await _readProfileFallbackContext(user.id);
        if (profileFallback != null) {
          debugPrint(
              'Using profile membership fallback after transient failure.');
          unawaited(_cacheContext(user.id, profileFallback));
          return profileFallback;
        }
      }
      return MembershipContext.loadFailed(
        status: status,
        error: error,
      );
    }
  }

  Future<dynamic> _loadCurrentContextWithRetry() async {
    Object? lastError;
    const delays = [
      Duration(milliseconds: 300),
      Duration(milliseconds: 900),
    ];
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _client
            .rpc('get_current_membership_context')
            .timeout(const Duration(seconds: 12));
      } catch (error) {
        lastError = error;
        final status = classifyContextError(error);
        if (status == MembershipLoadStatus.permissionDenied || attempt == 2) {
          rethrow;
        }
        await Future<void>.delayed(delays[attempt]);
      }
    }
    throw lastError ?? StateError('Membership lookup failed.');
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
      final status = classifyContextError(error);
      if (status != MembershipLoadStatus.permissionDenied) {
        final cached = await _readCachedContext(user.id);
        if (cached != null) {
          yield cached;
          return;
        }
        final profileFallback = await _readProfileFallbackContext(user.id);
        if (profileFallback != null) {
          yield profileFallback;
          return;
        }
        // A realtime transport/schema-cache interruption must not replace a
        // membership context that was already loaded successfully with a
        // full-screen setup error.
        yield initial;
        return;
      }
      yield MembershipContext.loadFailed(
        status: status,
        error: error,
      );
    }
  }

  Future<void> _cacheContext(
    String userId,
    MembershipContext context,
  ) async {
    if (userId.isEmpty || context.hasLoadError || !context.authenticated) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey(userId),
        jsonEncode({
          'cachedAt': DateTime.now().toUtc().toIso8601String(),
          'context': context.toMap(),
        }),
      );
    } catch (error) {
      debugPrint('Membership context cache skipped: $error');
    }
  }

  Future<MembershipContext?> _readCachedContext(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(userId));
      if (raw == null || raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final wrappedContext = decoded['context'];
      final cachedAt = DateTime.tryParse(decoded['cachedAt']?.toString() ?? '');
      if (cachedAt != null &&
          DateTime.now().toUtc().difference(cachedAt.toUtc()) > _cacheMaxAge) {
        return null;
      }
      final context = MembershipContext.fromMap(
        wrappedContext is Map
            ? Map<String, dynamic>.from(wrappedContext)
            : Map<String, dynamic>.from(decoded),
      );
      if (!context.authenticated || context.hasLoadError) return null;
      return context;
    } catch (error) {
      debugPrint('Membership context cache read skipped: $error');
      return null;
    }
  }

  String _cacheKey(String userId) => '$_cacheKeyPrefix:$userId';

  Future<MembershipContext?> _readProfileFallbackContext(String userId) async {
    if (userId.trim().isEmpty) return null;

    try {
      final data = await _client
          .from('users')
          .select('uid,id,accountState,accountStatus,placeId,placeName')
          .or('uid.eq.$userId,id.eq.$userId')
          .maybeSingle();
      if (data == null) return null;

      final membershipRows = await _client
          .from('church_memberships')
          .select('id,church_id,membership_status,decision_reason,requested_at')
          .eq('user_id', userId)
          .inFilter('membership_status', ['active', 'pending'])
          .order('requested_at', ascending: false)
          .limit(10);
      final memberships = List<Map<String, dynamic>>.from(membershipRows);
      Map<String, dynamic>? membership;
      for (final row in memberships) {
        if (row['membership_status']?.toString() == 'active') {
          membership = row;
          break;
        }
      }
      membership ??= memberships.isEmpty ? null : memberships.first;

      final churchId = membership?['church_id']?.toString().trim() ?? '';
      Map<String, dynamic>? church;
      if (churchId.isNotEmpty) {
        church = await _client
            .from('churches')
            .select('id,placeId,display_name,name,church_status')
            .or('id.eq.$churchId,placeId.eq.$churchId')
            .maybeSingle();
      }
      final membershipStatus =
          membership?['membership_status']?.toString() ?? 'none';
      final churchStatus = church?['church_status']?.toString();
      if (membershipStatus == 'active' && churchStatus != 'approved') {
        return null;
      }
      final churchName =
          (church?['display_name'] ?? church?['name'] ?? data['placeName'])
              ?.toString()
              .trim();
      final accountStatus =
          (data['accountStatus'] ?? data['accountState'] ?? 'active')
              .toString();

      return MembershipContext(
        authenticated: true,
        hasProfile: true,
        accountStatus: accountStatus,
        membershipStatus: membershipStatus,
        membershipId: membership?['id']?.toString(),
        churchId: churchId.isEmpty ? null : churchId,
        churchName: churchName?.isEmpty == true ? null : churchName,
        churchStatus: churchStatus,
        decisionReason: membership?['decision_reason']?.toString(),
        hasPendingChurchApplication: false,
      );
    } catch (error) {
      debugPrint('Membership profile fallback unavailable: $error');
      return null;
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
    final current = await getCurrentContext();
    if (current.hasActiveMembership) {
      throw StateError(
        'You already belong to a church. Use Church Transfer if you need to change churches.',
      );
    }
    if (current.hasPendingMembership) {
      throw StateError('Your church membership request is already pending.');
    }

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
