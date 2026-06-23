import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
  DateTime _foregroundStartedAt = DateTime.now();
  final Set<String> _shownForegroundNotificationIds = {};
  static final Uri _topicNotificationEndpoint = Uri.parse(
    'https://us-central1-graceconnect-9a97c.cloudfunctions.net/sendTopicNotification',
  );

  static const _defaultSound = _NotificationSoundProfile(
    channelId: 'grace_default_channel_v1',
    channelName: 'Grace Connect',
    description: 'General Grace Connect notifications',
    soundName: 'grace_default',
  );

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

    await _messaging.requestPermission();

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
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
      if (message.notification != null) {
        _showLocalNotification(
          message.notification!.title,
          message.notification!.body,
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
    final normalized = (type ?? 'general')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_');
    return _soundProfiles[normalized] ?? _defaultSound;
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
          'type': type,
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

  void watchForegroundNotifications(String userId) {
    if (kIsWeb) return;

    _foregroundSubscription?.cancel();
    _foregroundStartedAt = DateTime.now();
    _shownForegroundNotificationIds.clear();
    _foregroundSubscription = watchNotifications(userId).listen(
      (notifications) {
        for (final notification in notifications) {
          if (notification.isRead) continue;
          if (_shownForegroundNotificationIds.contains(notification.id)) {
            continue;
          }
          if (notification.createdAt.isBefore(_foregroundStartedAt)) continue;
          _shownForegroundNotificationIds.add(notification.id);
          _showLocalNotification(
            notification.title,
            notification.body,
            route: notification.route,
            type: notification.type,
          );
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
    for (final suffix in topicMap.keys) {
      await unsubscribeFromTopic('church_${churchId}_$suffix');
    }
  }

  /// Syncs user subscriptions based on SharedPreferences and Church ID
  Future<void> syncSubscriptions(String churchId) async {
    if (kIsWeb || churchId.trim().isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    // Always subscribe to the main church topic
    await subscribeToTopic('church_$churchId');

    // Sync optional topics
    for (var entry in topicMap.entries) {
      String topicSuffix = entry.key;
      String prefKey = entry.value;

      // Default to true if not set
      bool shouldSubscribe = prefs.getBool(prefKey) ?? true;

      String fullTopic = 'church_${churchId}_$topicSuffix';

      if (shouldSubscribe) {
        await subscribeToTopic(fullTopic);
      } else {
        await unsubscribeFromTopic(fullTopic);
      }
    }
  }
}
