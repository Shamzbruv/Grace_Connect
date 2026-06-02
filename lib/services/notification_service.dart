import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final SupabaseClient _supabase = Supabase.instance.client;
  StreamSubscription<List<AppNotification>>? _foregroundSubscription;
  DateTime _foregroundStartedAt = DateTime.now();
  final Set<String> _shownForegroundNotificationIds = {};

  // Default topics and their pref keys
  static const Map<String, String> topicMap = {
    'events': 'notify_service', // Mapping Service Reminders to events topic
    'updates': 'notify_updates',
    'devotionals': 'notify_devotionals',
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
    const InitializationSettings initSettings =
        InitializationSettings(android: androidInit);
    await _localNotifications.initialize(initSettings);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        _showLocalNotification(
            message.notification!.title, message.notification!.body);
      }
    });
  }

  Future<void> _showLocalNotification(String? title, String? body) async {
    if (kIsWeb) return;

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'channel_id',
      'GraceConnect Notifications',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails details =
        NotificationDetails(android: androidDetails);
    await _localNotifications.show(0, title, body, details);
  }

  Future<void> sendNotification(String title, String body, String topic) async {
    // In production, this would trigger a Cloud Function or call FCM API
    debugPrint(
        "Simulated sending notification to topic '$topic': $title - $body");
  }

  Stream<List<AppNotification>> watchNotifications(String userId) {
    return _supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(100)
        .map(
            (rows) => rows.map((row) => AppNotification.fromMap(row)).toList());
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
          _showLocalNotification(notification.title, notification.body);
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

  /// Syncs user subscriptions based on SharedPreferences and Church ID
  Future<void> syncSubscriptions(String churchId) async {
    if (kIsWeb) return;

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
