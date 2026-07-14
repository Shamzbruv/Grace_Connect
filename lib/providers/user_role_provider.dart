import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_profile.dart';
import '../services/attendance_service.dart';
import '../services/notification_service.dart';

class UserRoleProvider with ChangeNotifier {
  UserProfile? _userProfile;
  bool _isLoading = true;
  StreamSubscription<List<Map<String, dynamic>>>? _profileSubscription;
  String? _subscribedUid;

  UserProfile? get userProfile => _userProfile;
  UserProfile? get user => _userProfile;
  bool get isLoading => _isLoading;
  bool get isDeveloper => _userProfile?.isDeveloper ?? false;

  // Legacy accessor - returns the first role or 'Member'
  // Updated to use the new role list
  String get role => _userProfile?.roles.isNotEmpty == true
      ? _userProfile!.roles.first
      : "Member";

  UserRoleProvider() {
    _init();
  }

  void _init() {
    try {
      if (Supabase.instance.client.auth.currentUser != null) {
        unawaited(fetchUserProfile());
      } else {
        _isLoading = false;
      }

      Supabase.instance.client.auth.onAuthStateChange.listen((data) {
        final Session? session = data.session;
        final User? user = session?.user;

        if (user != null) {
          fetchUserProfile();
        } else {
          final previousProfile = _userProfile;
          _stopProfileSubscription();
          NotificationService().stopForegroundNotifications();
          unawaited(NotificationService().unsubscribeAlwaysOnTopics(
            userId: previousProfile?.uid,
          ));
          _userProfile = null;
          _isLoading = false;
          notifyListeners();
        }
      });
    } catch (error) {
      debugPrint('Supabase not initialized, skipping auth listener: $error');
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchUserProfile() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      _stopProfileSubscription();
      _userProfile = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    try {
      // 1. First try to get profile directly from Supabase
      try {
        final data = await Supabase.instance.client
            .from('users')
            .select()
            .eq('uid', user.id)
            .maybeSingle();

        if (data != null) {
          _applyProfile(UserProfile.fromMap(data));
          _startProfileSubscription(user.id);
          return; // Success, exit early
        }
      } catch (e) {
        debugPrint("Warning: Failed to fetch profile from Supabase: $e");
      }
    } catch (e) {
      debugPrint("Error fetching user profile: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Alias for fetchUserProfile to fix legacy calls
  Future<void> refreshProfile() => fetchUserProfile();

  void setUserProfile(UserProfile profile) {
    _applyProfile(profile);
    _startProfileSubscription(profile.uid);
  }

  void _applyProfile(UserProfile profile) {
    final previousChurchId = _userProfile?.churchId;
    _userProfile = profile;
    _isLoading = false;

    if (previousChurchId != null &&
        previousChurchId.isNotEmpty &&
        previousChurchId != profile.churchId) {
      unawaited(NotificationService().unsubscribeFromChurchTopics(
        previousChurchId,
      ));
    }
    unawaited(NotificationService().ensureStartupPermissionsAndSubscriptions(
      userId: profile.uid,
      churchId: profile.churchId,
      roles: profile.roles,
      privileges: profile.appPrivileges,
      notifyAttendance: profile.notifyAttendance,
      notifyDailyMotivation: profile.notifyDailyMotivation,
      notifyDailyQuiz: profile.notifyDailyQuiz,
    ));
    NotificationService().watchForegroundNotifications(profile.uid);
    if (!kIsWeb && !AttendanceService().isMonitoring) {
      unawaited(AttendanceService().initialize());
    }
    notifyListeners();
  }

  void _startProfileSubscription(String uid) {
    if (_subscribedUid == uid && _profileSubscription != null) return;

    _stopProfileSubscription();
    _subscribedUid = uid;
    _profileSubscription = Supabase.instance.client
        .from('users')
        .stream(primaryKey: ['uid'])
        .eq('uid', uid)
        .listen((rows) {
          if (rows.isEmpty) {
            _userProfile = null;
            _isLoading = false;
            notifyListeners();
            return;
          }

          _applyProfile(UserProfile.fromMap(rows.first));
        }, onError: (Object error) {
          debugPrint('Profile subscription error: $error');
        });
  }

  void _stopProfileSubscription() {
    unawaited(_profileSubscription?.cancel());
    _profileSubscription = null;
    _subscribedUid = null;
  }

  bool hasRole(String role) {
    if (_userProfile == null) return false;
    final targetRole = _normalizeRole(role);
    return _userProfile!.roles
        .map(_normalizeRole)
        .any((userRole) => userRole == targetRole);
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

  // Use Capabilities instead of string matching
  bool get canManageEvents =>
      _userProfile?.capabilities.canCreateEvents ?? false;

  @override
  void dispose() {
    _stopProfileSubscription();
    super.dispose();
  }
}
