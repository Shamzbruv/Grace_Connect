import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';
import 'supabase_resilience.dart';

class _NotificationSoundProfile {
  const _NotificationSoundProfile({
    required this.channelId,
    required this.channelName,
    required this.description,
    required this.soundName,
  });

  final String channelId;
  final String channelName;
  final String description;
  final String soundName;

  RawResourceAndroidNotificationSound get androidSound =>
      RawResourceAndroidNotificationSound(soundName);

  String get iosSound => '$soundName.wav';
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final SupabaseClient _supabase = Supabase.instance.client;
  StreamSubscription<List<AppNotification>>? _foregroundSubscription;
  Timer? _unansweredReminderTimer;
  DateTime _foregroundStartedAt = DateTime.now();
  final Set<String> _shownForegroundNotificationIds = {};
  final Set<String> _startupPermissionUsers = {};
  static final Uri _topicNotificationEndpoint = Uri.parse(
    'https://us-central1-graceconnect-9a97c.cloudfunctions.net/sendTopicNotification',
  );
  static const String churchWidePrefKey = 'notify_church_wide';
  static const Duration unansweredReminderInterval = Duration(hours: 3);
  static const Duration _unansweredReminderPollInterval = Duration(minutes: 15);

  @visibleForTesting
  static const Set<String> publicBroadcastTypes = {
    'announcement',
    'live_stream',
    'general',
    'testimony',
  };

  static const _defaultSound = _NotificationSoundProfile(
    channelId: 'grace_default_channel_v1',
    channelName: 'Grace Connect',
    description: 'General Grace Connect notifications',
    soundName: 'grace_default',
  );
  static const _androidNotificationLargeIcon =
      DrawableResourceAndroidBitmap('notification_large_icon');

  static const Map<String, _NotificationSoundProfile> _soundProfiles = {
    'general': _defaultSound,
    'announcement': _defaultSound,
    'community': _defaultSound,
    'like': _defaultSound,
    'comment': _defaultSound,
    'message': _NotificationSoundProfile(
      channelId: 'grace_messages_channel_v1',
      channelName: 'Grace Connect Messages',
      description: 'Direct message notifications',
      soundName: 'grace_message',
    ),
    'direct_message': _NotificationSoundProfile(
      channelId: 'grace_messages_channel_v1',
      channelName: 'Grace Connect Messages',
      description: 'Direct message notifications',
      soundName: 'grace_message',
    ),
    'prayer': _NotificationSoundProfile(
      channelId: 'grace_prayer_channel_v1',
      channelName: 'Prayer Requests',
      description: 'Prayer and care notifications',
      soundName: 'grace_prayer',
    ),
    'prayer_request': _NotificationSoundProfile(
      channelId: 'grace_prayer_channel_v1',
      channelName: 'Prayer Requests',
      description: 'Prayer and care notifications',
      soundName: 'grace_prayer',
    ),
    'daily_motivation': _NotificationSoundProfile(
      channelId: 'grace_daily_word_channel_v1',
      channelName: 'Daily Word',
      description: 'Daily devotional and motivation notifications',
      soundName: 'grace_daily',
    ),
    'daily_devotional': _NotificationSoundProfile(
      channelId: 'grace_daily_word_channel_v1',
      channelName: 'Daily Word',
      description: 'Daily devotional and motivation notifications',
      soundName: 'grace_daily',
    ),
    'daily_bible_quiz': _NotificationSoundProfile(
      channelId: 'grace_daily_quiz_channel_v1',
      channelName: 'Daily Bible Quiz',
      description: 'Daily Bible quiz notifications',
      soundName: 'grace_quiz',
    ),
    'quiz': _NotificationSoundProfile(
      channelId: 'grace_daily_quiz_channel_v1',
      channelName: 'Daily Bible Quiz',
      description: 'Daily Bible quiz notifications',
      soundName: 'grace_quiz',
    ),
    'monthly_quiz_winners': _NotificationSoundProfile(
      channelId: 'grace_daily_quiz_channel_v1',
      channelName: 'Daily Bible Quiz',
      description: 'Daily Bible quiz notifications',
      soundName: 'grace_quiz',
    ),
    'live_stream': _NotificationSoundProfile(
      channelId: 'grace_live_channel_v1',
      channelName: 'Live Service',
      description: 'Live service notifications',
      soundName: 'grace_live',
    ),
    'testimony': _defaultSound,
  };

  // Default topics and their pref keys
  static const Map<String, String> topicMap = {
    'events': 'notify_service', // Mapping Service Reminders to events topic
    'updates': 'notify_updates',
    'devotionals': 'notify_devotionals',
    'quiz': 'notify_daily_quiz',
    'community': 'notify_community',
    'prayers': 'notify_prayer',
  };

  Future<void> init() async {
    if (kIsWeb) return;

    try {
      Firebase.app();
    } catch (_) {
      await Firebase.initializeApp();
    }

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('ic_stat_grace_connect');
    const DarwinInitializationSettings iosInit = DarwinInitializationSettings(
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    );
    const InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        _navigateToRoute(response.payload);
      },
    );
    await _createAndroidNotificationChannels();

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final title =
          message.notification?.title ?? message.data['title']?.toString();
      final body =
          message.notification?.body ?? message.data['body']?.toString();
      if ((title?.trim().isNotEmpty ?? false) ||
          (body?.trim().isNotEmpty ?? false)) {
        _showLocalNotification(
          title,
          body,
          route: message.data['route'],
          type: message.data['type'],
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_openRouteFromMessage);
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      unawaited(Future<void>.delayed(
        const Duration(milliseconds: 500),
        () => _openRouteFromMessage(initialMessage),
      ));
    }
  }

  Future<void> showDataOnlyBackgroundMessage(RemoteMessage message) async {
    if (kIsWeb || message.notification != null) return;

    final title = message.data['title']?.toString();
    final body = message.data['body']?.toString();
    if ((title?.trim().isEmpty ?? true) && (body?.trim().isEmpty ?? true)) {
      return;
    }

    const androidInit = AndroidInitializationSettings('ic_stat_grace_connect');
    const iosInit = DarwinInitializationSettings(
      defaultPresentAlert: true,
      defaultPresentBadge: true,
      defaultPresentSound: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _localNotifications.initialize(initSettings);
    await _createAndroidNotificationChannels();
    await _showLocalNotification(
      title,
      body,
      route: message.data['route'],
      type: message.data['type'],
    );
  }

  Future<void> _showLocalNotification(
    String? title,
    String? body, {
    String? route,
    String? type,
  }) async {
    if (kIsWeb) return;

    final profile = _profileForType(type);
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      profile.channelId,
      profile.channelName,
      channelDescription: profile.description,
      importance: Importance.max,
      priority: Priority.high,
      icon: 'ic_stat_grace_connect',
      largeIcon: _androidNotificationLargeIcon,
      color: const Color(0xFF0B5C7D),
      playSound: true,
      sound: profile.androidSound,
    );
    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: profile.iosSound,
    );
    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );
    await _localNotifications.show(
      _notificationId(
        title: title ?? '',
        body: body ?? '',
        route: route,
        type: type,
      ),
      title,
      body,
      details,
      payload: route,
    );
  }

  int _notificationId({
    required String title,
    required String body,
    required String? route,
    required String? type,
  }) {
    final seed = '${type ?? 'general'}|${route ?? ''}|$title|$body';
    var hash = 0;
    for (final unit in seed.codeUnits) {
      hash = 0x1fffffff & (hash + unit);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    hash = 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
    return hash == 0
        ? DateTime.now().millisecondsSinceEpoch & 0x7fffffff
        : hash;
  }

  Future<void> _createAndroidNotificationChannels() async {
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    final uniqueProfiles = <String, _NotificationSoundProfile>{
      for (final p in _soundProfiles.values) p.channelId: p
    };
    for (final profile in uniqueProfiles.values) {
      await androidPlugin.createNotificationChannel(
        AndroidNotificationChannel(
          profile.channelId,
          profile.channelName,
          description: profile.description,
          importance: Importance.max,
          playSound: true,
          sound: profile.androidSound,
        ),
      );
    }
  }

  _NotificationSoundProfile _profileForType(String? type) {
    final normalized = normalizeNotificationType(type ?? 'general');
    return _soundProfiles[normalized] ?? _defaultSound;
  }

  @visibleForTesting
  static String normalizeNotificationType(String type) {
    return type.trim().toLowerCase().replaceAll(
          RegExp(r'[^a-z0-9_]+'),
          '_',
        );
  }

  bool _isAllowedTopicBroadcastType(String type) {
    return publicBroadcastTypes.contains(normalizeNotificationType(type));
  }

  Future<bool> hasPushPermission() async {
    if (kIsWeb) return false;
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<bool> ensurePushPermission() async {
    if (kIsWeb) return false;
    if (await hasPushPermission()) return true;

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<void> ensureStartupPermissionsAndSubscriptions({
    required String userId,
    required String churchId,
    Iterable<String> roles = const [],
    Iterable<String> privileges = const [],
  }) async {
    if (kIsWeb) return;

    final firstPromptThisSession = _startupPermissionUsers.add(userId);
    if (firstPromptThisSession) {
      final canUsePush = await ensurePushPermission();
      if (canUsePush) {
        await _requestLocalNotificationPermission();
      }
      await _ensureLocationPermissionPrompt();
    }

    await syncSubscriptions(
      churchId,
      roles: roles,
      privileges: privileges,
    );
  }

  Future<void> _requestLocalNotificationPermission() async {
    final androidPlugin =
        _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();

    final iosPlugin = _localNotifications.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    await iosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _ensureLocationPermissionPrompt() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permission permanently denied.');
      }
    } catch (error) {
      debugPrint('Location permission prompt skipped: $error');
    }
  }

  void _openRouteFromMessage(RemoteMessage message) {
    _navigateToRoute(message.data['route']);
  }

  void _navigateToRoute(String? route) {
    final cleanRoute = normalizeRoute(route);
    if (cleanRoute == null) return;

    void pushRoute() {
      final navigator = navigatorKey.currentState;
      if (navigator == null) return;
      try {
        navigator.pushNamed(cleanRoute);
      } catch (error) {
        debugPrint('Notification route failed ($cleanRoute): $error');
      }
    }

    if (navigatorKey.currentState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => pushRoute());
    } else {
      pushRoute();
    }
  }

  @visibleForTesting
  static String? normalizeRoute(String? route) {
    final cleanRoute = route?.trim();
    if (cleanRoute == null || cleanRoute.isEmpty) return null;

    final uri = Uri.tryParse(cleanRoute);
    if (uri == null) return cleanRoute.startsWith('/') ? cleanRoute : null;
    if (uri.hasScheme || uri.hasAuthority) {
      final path = uri.path.isNotEmpty
          ? uri.path
          : uri.host.isNotEmpty
              ? '/${uri.host}'
              : '';
      if (!path.startsWith('/')) return null;
      final query = uri.query.isEmpty ? '' : '?${uri.query}';
      return '$path$query';
    }
    if (!uri.path.startsWith('/')) return null;
    return uri.toString();
  }

  Future<void> sendNotification(
    String title,
    String body,
    String topic, {
    String? route,
    String type = 'general',
  }) async {
    final normalizedType = normalizeNotificationType(type);
    if (!_isAllowedTopicBroadcastType(normalizedType)) {
      debugPrint('Topic notification skipped: $type is not public broadcast.');
      return;
    }

    final accessToken = _supabase.auth.currentSession?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      debugPrint('Topic notification skipped: missing Supabase session.');
      return;
    }

    try {
      final response = await http.post(
        _topicNotificationEndpoint,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'title': title,
          'body': body,
          'topic': topic,
          'route': route,
          'type': normalizedType,
        }),
      );

      if (response.statusCode >= 400) {
        debugPrint(
          'Topic notification failed (${response.statusCode}): ${response.body}',
        );
      }
    } catch (error) {
      debugPrint('Topic notification request failed: $error');
    }
  }

  Future<void> sendMembershipRequestPush(String membershipId) async {
    final cleanMembershipId = membershipId.trim();
    if (kIsWeb || cleanMembershipId.isEmpty) return;

    try {
      final response = await _supabase.functions.invoke(
        'send-membership-request-push',
        body: {'membershipId': cleanMembershipId},
      ).timeout(const Duration(seconds: 12));
      final data = response.data;
      if (data is Map && data['ok'] == false) {
        debugPrint('Membership request push queued with warning: $data');
      }
    } catch (error) {
      debugPrint('Membership request push skipped: $error');
    }
  }

  Stream<List<AppNotification>> watchNotifications(String userId) {
    return SupabaseResilience.guardedStream<List<AppNotification>>(
      debugLabel: 'Notifications',
      emptyValue: const <AppNotification>[],
      yieldEmptyOnInitialFailure: true,
      fetchInitial: () async {
        final rows = await _supabase
            .from('notifications')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(100);
        return rows.map((row) => AppNotification.fromMap(row)).toList();
      },
      subscribe: () => _supabase
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(100)
          .map((rows) =>
              rows.map((row) => AppNotification.fromMap(row)).toList()),
    );
  }

  Stream<int> watchUnreadCount(String userId) {
    return watchNotifications(userId).map(
      (notifications) =>
          notifications.where((notification) => !notification.isRead).length,
    );
  }

  Future<void> markAsRead(String notificationId) async {
    await _supabase
        .from('notifications')
        .update({'is_read': true}).eq('id', notificationId);
  }

  Future<void> markAllAsRead(String userId) async {
    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }

  Future<void> markRouteAsRead(String userId, String route) async {
    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('route', route)
        .eq('is_read', false);
  }

  Future<void> markEntityAsRead({
    required String userId,
    required String entityTable,
    required String entityId,
  }) async {
    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('entity_table', entityTable)
        .eq('entity_id', entityId)
        .eq('is_read', false);
  }

  void watchForegroundNotifications(String userId) {
    if (kIsWeb) return;

    _foregroundSubscription?.cancel();
    _foregroundStartedAt = DateTime.now();
    _shownForegroundNotificationIds.clear();
    _startUnansweredReminderLoop(userId);
    _foregroundSubscription = watchNotifications(userId).listen(
      (notifications) {
        for (final notification in notifications) {
          if (notification.isRead) continue;
          if (_shownForegroundNotificationIds.contains(notification.id)) {
            continue;
          }
          if (notification.createdAt.isBefore(_foregroundStartedAt)) continue;
          _shownForegroundNotificationIds.add(notification.id);
          unawaited(_showAndTrackNotification(notification));
        }
      },
      onError: (error) {
        debugPrint('Notification foreground watch failed: $error');
      },
    );
  }

  void stopForegroundNotifications() {
    _foregroundSubscription?.cancel();
    _foregroundSubscription = null;
    _unansweredReminderTimer?.cancel();
    _unansweredReminderTimer = null;
  }

  void _startUnansweredReminderLoop(String userId) {
    _unansweredReminderTimer?.cancel();
    unawaited(_showDueUnansweredReminders(userId));
    _unansweredReminderTimer = Timer.periodic(
      _unansweredReminderPollInterval,
      (_) => unawaited(_showDueUnansweredReminders(userId)),
    );
  }

  Future<void> _showDueUnansweredReminders(String userId) async {
    if (kIsWeb) return;

    try {
      final rows = await _supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .eq('is_read', false)
          .order('created_at', ascending: false)
          .limit(30);

      final notifications =
          rows.map((row) => AppNotification.fromMap(row)).where(
        (notification) {
          return notification.id.isNotEmpty &&
              _isReminderEligible(notification);
        },
      );
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now();
      for (final notification in notifications) {
        if (!_isReminderDue(notification, prefs, now)) continue;
        await _showAndTrackNotification(notification);
      }
    } catch (error) {
      debugPrint('Unread notification reminder check failed: $error');
    }
  }

  bool _isReminderEligible(AppNotification notification) {
    return !notification.isRead &&
        notification.id.isNotEmpty &&
        notification.type.trim().isNotEmpty;
  }

  bool _isReminderDue(
    AppNotification notification,
    SharedPreferences prefs,
    DateTime now,
  ) {
    final key = _reminderPrefKey(notification.id);
    final previous = DateTime.tryParse(prefs.getString(key) ?? '');
    final lastShown = previous ?? notification.createdAt;
    return now.difference(lastShown) >= unansweredReminderInterval;
  }

  Future<void> _showAndTrackNotification(AppNotification notification) async {
    await _showLocalNotification(
      notification.title,
      notification.body,
      route: notification.route,
      type: notification.type,
    );
    await _recordNotificationReminderShown(notification.id);
  }

  Future<void> _recordNotificationReminderShown(String notificationId) async {
    if (notificationId.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _reminderPrefKey(notificationId),
      DateTime.now().toIso8601String(),
    );
  }

  String _reminderPrefKey(String notificationId) {
    return 'notification_reminder_$notificationId';
  }

  Future<String?> getFCMToken() async {
    return await _messaging.getToken();
  }

  Future<void> subscribeToTopic(String topic) async {
    if (kIsWeb) return;
    await _messaging.subscribeToTopic(topic);
    debugPrint("Subscribed to topic: $topic");
  }

  Future<void> unsubscribeFromTopic(String topic) async {
    if (kIsWeb) return;
    await _messaging.unsubscribeFromTopic(topic);
    debugPrint("Unsubscribed from topic: $topic");
  }

  Future<void> unsubscribeFromChurchTopics(String churchId) async {
    if (kIsWeb || churchId.trim().isEmpty) return;
    await unsubscribeFromTopic('church_$churchId');
    await unsubscribeFromTopic('church_${churchId}_leaders');
    for (final suffix in topicMap.keys) {
      await unsubscribeFromTopic('church_${churchId}_$suffix');
    }
  }

  /// Syncs user subscriptions based on SharedPreferences and Church ID
  Future<void> syncSubscriptions(
    String churchId, {
    Iterable<String> roles = const [],
    Iterable<String> privileges = const [],
  }) async {
    if (kIsWeb || churchId.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final canUsePush = await hasPushPermission();

    final shouldReceiveChurchWide =
        canUsePush && (prefs.getBool(churchWidePrefKey) ?? false);
    if (shouldReceiveChurchWide) {
      await subscribeToTopic('church_$churchId');
    } else {
      await unsubscribeFromTopic('church_$churchId');
    }

    final leaderTopic = 'church_${churchId}_leaders';
    if (canUsePush &&
        canReceiveLeaderMembershipPush(
          roles: roles,
          privileges: privileges,
        )) {
      await subscribeToTopic(leaderTopic);
    } else {
      await unsubscribeFromTopic(leaderTopic);
    }

    // Sync optional topics
    for (var entry in topicMap.entries) {
      String topicSuffix = entry.key;
      String prefKey = entry.value;

      bool shouldSubscribe = canUsePush && (prefs.getBool(prefKey) ?? false);

      String fullTopic = 'church_${churchId}_$topicSuffix';

      if (shouldSubscribe) {
        await subscribeToTopic(fullTopic);
      } else {
        await unsubscribeFromTopic(fullTopic);
      }
    }
  }

  @visibleForTesting
  static bool canReceiveLeaderMembershipPush({
    required Iterable<String> roles,
    required Iterable<String> privileges,
  }) {
    final normalizedRoles = roles.map(_normalizeAccessValue).toSet();
    final normalizedPrivileges = privileges.map(_normalizeAccessValue).toSet();
    const leaderRoles = {
      'pastor',
      'seniorpastor',
      'assistantpastor',
      'actingpastor',
      'churchadmin',
      'admin',
      'administrator',
      'secretary',
      'churchsecretary',
    };
    const leaderPrivileges = {
      'approvemembers',
      'managechurchsettings',
      'manageroles',
    };
    return normalizedRoles.any(leaderRoles.contains) ||
        normalizedPrivileges.any(leaderPrivileges.contains);
  }

  static String _normalizeAccessValue(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '');
  }
}
