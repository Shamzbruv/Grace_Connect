import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const MethodChannel _configChannel =
      MethodChannel('love.graceconnect/config');
  StreamSubscription<List<AppNotification>>? _foregroundSubscription;
  Timer? _unansweredReminderTimer;
  DateTime _foregroundStartedAt = DateTime.now();
  final Set<String> _shownForegroundNotificationIds = {};
  final Set<String> _startupPermissionUsers = {};
  static final Uri _topicNotificationEndpoint = Uri.parse(
    'https://us-central1-graceconnect-9a97c.cloudfunctions.net/sendTopicNotification',
  );
  static const String churchWidePrefKey = 'notify_church_wide';
  static const String appWideTopic = 'graceconnect_all';
  static const Duration unansweredReminderInterval = Duration(hours: 3);
  static const Duration _unansweredReminderPollInterval = Duration(minutes: 15);

  static String userTopicFor(String userId) {
    final cleanUserId = userId.trim();
    return 'user_$cleanUserId';
  }

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
    'community_reaction': _defaultSound,
    'community_reply': _defaultSound,
    'community_mention': _defaultSound,
    'social_follow': _defaultSound,
    'social_follow_request': _defaultSound,
    'social_follow_accepted': _defaultSound,
    'circle_invitation': _defaultSound,
    'circle_post': _defaultSound,
    'event_invitation': _defaultSound,
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
    'grace_support_offer': _NotificationSoundProfile(
      channelId: 'grace_messages_channel_v1',
      channelName: 'Grace Connect Messages',
      description: 'Direct message notifications',
      soundName: 'grace_message',
    ),
    'grace_support_response': _NotificationSoundProfile(
      channelId: 'grace_messages_channel_v1',
      channelName: 'Grace Connect Messages',
      description: 'Direct message notifications',
      soundName: 'grace_message',
    ),
    'anonymous_private_message': _NotificationSoundProfile(
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
    await _messaging.setAutoInitEnabled(true);

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
        unawaited(_handleNotificationTapPayload(response.payload));
      },
    );
    await _createAndroidNotificationChannels();
    final launchDetails =
        await _localNotifications.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchResponse?.payload != null) {
      unawaited(Future<void>.delayed(
        const Duration(milliseconds: 500),
        () => _handleNotificationTapPayload(launchResponse!.payload),
      ));
    }

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
          entityTable: _dataValue(message.data, 'entity_table') ??
              _dataValue(message.data, 'entityTable'),
          entityId: _dataValue(message.data, 'entity_id') ??
              _dataValue(message.data, 'entityId'),
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen(
      (message) => unawaited(_openRouteFromMessage(message)),
    );
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
      entityTable: _dataValue(message.data, 'entity_table') ??
          _dataValue(message.data, 'entityTable'),
      entityId: _dataValue(message.data, 'entity_id') ??
          _dataValue(message.data, 'entityId'),
    );
  }

  Future<void> _showLocalNotification(
    String? title,
    String? body, {
    String? route,
    String? type,
    String? entityTable,
    String? entityId,
    String? notificationId,
  }) async {
    if (kIsWeb) return;

    final profile = _profileForType(type);
    final effectiveRoute = _routeForNotification(
      route: route,
      type: type,
      entityTable: entityTable,
      entityId: entityId,
    );
    final notificationTag = _notificationTag(
      type: type,
      route: effectiveRoute,
      entityTable: entityTable,
      entityId: entityId,
    );
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
      tag: notificationTag,
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
        route: effectiveRoute,
        type: type,
        entityTable: entityTable,
        entityId: entityId,
      ),
      title,
      body,
      details,
      payload: _notificationPayload(
        route: effectiveRoute,
        type: type,
        entityTable: entityTable,
        entityId: entityId,
        notificationId: notificationId,
      ),
    );
  }

  int _notificationId({
    required String title,
    required String body,
    required String? route,
    required String? type,
    required String? entityTable,
    required String? entityId,
  }) {
    final cleanEntityTable = entityTable?.trim();
    final cleanEntityId = entityId?.trim();
    if (cleanEntityTable?.isNotEmpty == true &&
        cleanEntityId?.isNotEmpty == true) {
      return _stableNotificationId('entity|$cleanEntityTable|$cleanEntityId');
    }
    final cleanRoute = normalizeRoute(route);
    if (cleanRoute?.isNotEmpty == true) {
      return _stableNotificationId('route|$cleanRoute');
    }
    final seed = '${type ?? 'general'}|${route ?? ''}|$title|$body';
    return _stableNotificationId(seed);
  }

  int _stableNotificationId(String seed) {
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
    bool notifyAttendance = true,
    bool notifyDailyMotivation = true,
    bool notifyDailyQuiz = true,
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

    await _seedStartupNotificationPreferences(
      notifyAttendance: notifyAttendance,
      notifyDailyMotivation: notifyDailyMotivation,
      notifyDailyQuiz: notifyDailyQuiz,
    );
    await syncSubscriptions(
      churchId,
      userId: userId,
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

  Future<void> _openRouteFromMessage(RemoteMessage message) async {
    final payload = _payloadFromMessageData(message.data);
    await _markNotificationPayloadHandled(payload);
    await _cancelNotificationForPayload(payload);
    _navigateToRoute(payload['route']);
  }

  Future<void> _handleNotificationTapPayload(String? rawPayload) async {
    final payload = _decodeNotificationPayload(rawPayload);
    await _markNotificationPayloadHandled(payload);
    await _cancelNotificationForPayload(payload);
    _navigateToRoute(payload['route']);
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

  Map<String, String?> _payloadFromMessageData(Map<String, dynamic> data) {
    final type = _dataValue(data, 'type');
    final entityTable =
        _dataValue(data, 'entity_table') ?? _dataValue(data, 'entityTable');
    final entityId =
        _dataValue(data, 'entity_id') ?? _dataValue(data, 'entityId');
    final route = _routeForNotification(
      route: _dataValue(data, 'route'),
      type: type,
      entityTable: entityTable,
      entityId: entityId,
    );
    return {
      'route': route,
      'type': type,
      'entity_table': entityTable,
      'entity_id': entityId,
      'notification_id': _dataValue(data, 'notification_id') ??
          _dataValue(data, 'notificationId'),
    };
  }

  Map<String, String?> _decodeNotificationPayload(String? rawPayload) {
    if (rawPayload == null || rawPayload.trim().isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(rawPayload);
      if (decoded is Map) {
        return {
          'route': decoded['route']?.toString(),
          'type': decoded['type']?.toString(),
          'entity_table': decoded['entity_table']?.toString(),
          'entity_id': decoded['entity_id']?.toString(),
          'notification_id': decoded['notification_id']?.toString(),
        };
      }
    } catch (_) {
      // Older notifications used the route itself as the payload.
    }
    return {'route': rawPayload};
  }

  String _notificationPayload({
    required String? route,
    required String? type,
    required String? entityTable,
    required String? entityId,
    required String? notificationId,
  }) {
    return jsonEncode({
      if (route?.trim().isNotEmpty == true) 'route': route!.trim(),
      if (type?.trim().isNotEmpty == true) 'type': type!.trim(),
      if (entityTable?.trim().isNotEmpty == true)
        'entity_table': entityTable!.trim(),
      if (entityId?.trim().isNotEmpty == true) 'entity_id': entityId!.trim(),
      if (notificationId?.trim().isNotEmpty == true)
        'notification_id': notificationId!.trim(),
    });
  }

  String? _routeForNotification({
    required String? route,
    required String? type,
    required String? entityTable,
    required String? entityId,
  }) {
    final cleanEntityTable = entityTable?.trim() ?? '';
    final cleanEntityId = entityId?.trim() ?? '';
    final normalizedType = normalizeNotificationType(type ?? '');

    if (cleanEntityTable == 'community_posts' ||
        cleanEntityTable == 'community_comments' ||
        normalizedType == 'community_reaction' ||
        normalizedType == 'community_reply' ||
        normalizedType == 'community_mention' ||
        normalizedType == 'like' ||
        normalizedType == 'comment') {
      if (cleanEntityTable.isNotEmpty && cleanEntityId.isNotEmpty) {
        return Uri(
          path: '/community_post',
          queryParameters: {
            'entityTable': cleanEntityTable,
            'entityId': cleanEntityId,
          },
        ).toString();
      }
    }

    if ((cleanEntityTable == 'social_profiles' ||
            cleanEntityTable == 'users' ||
            normalizedType == 'social_follow' ||
            normalizedType == 'social_follow_request' ||
            normalizedType == 'social_follow_accepted') &&
        cleanEntityId.isNotEmpty) {
      return Uri(
        path: '/public_profile',
        queryParameters: {'id': cleanEntityId},
      ).toString();
    }

    if ((cleanEntityTable == 'grace_circles' ||
            cleanEntityTable == 'grace_circle_posts' ||
            normalizedType == 'circle_invitation' ||
            normalizedType == 'circle_post') &&
        cleanEntityId.isNotEmpty) {
      return Uri(
        path: '/grace_circles/circle',
        queryParameters: {'id': cleanEntityId},
      ).toString();
    }

    if ((cleanEntityTable == 'grace_rooms' ||
            cleanEntityTable == 'grace_room_messages' ||
            normalizedType == 'grace_support_offer' ||
            normalizedType == 'grace_support_response') &&
        cleanEntityId.isNotEmpty) {
      return Uri(
        path: '/grace_rooms/room',
        queryParameters: {'id': cleanEntityId},
      ).toString();
    }

    if (cleanEntityTable == 'events' || normalizedType == 'event_invitation') {
      return '/events';
    }

    if (cleanEntityTable == 'social_saved_items') {
      return '/saved';
    }

    if (normalizedType == 'message' ||
        normalizedType == 'direct_message' ||
        normalizedType == 'anonymous_private_message') {
      return route?.trim().isNotEmpty == true ? route : '/inbox';
    }

    if (cleanEntityTable == 'daily_motivations' && cleanEntityId.isNotEmpty) {
      return Uri(
        path: '/daily_word',
        queryParameters: {'id': cleanEntityId},
      ).toString();
    }

    if (cleanEntityTable == 'daily_bible_quizzes' && cleanEntityId.isNotEmpty) {
      return Uri(
        path: '/daily_bible_quiz',
        queryParameters: {'quizId': cleanEntityId},
      ).toString();
    }

    return route;
  }

  static String? _dataValue(Map<String, dynamic> data, String key) {
    final text = data[key]?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  Future<void> _markNotificationPayloadHandled(
      Map<String, String?> payload) async {
    final notificationId = payload['notification_id']?.trim();
    if (notificationId?.isNotEmpty == true) {
      await markAsRead(notificationId!);
      return;
    }

    final userId = _supabase.auth.currentUser?.id;
    final entityTable = payload['entity_table']?.trim();
    final entityId = payload['entity_id']?.trim();
    if (userId != null &&
        entityTable?.isNotEmpty == true &&
        entityId?.isNotEmpty == true) {
      await markEntityAsRead(
        userId: userId,
        entityTable: entityTable!,
        entityId: entityId!,
      );
      return;
    }

    final route = payload['route']?.trim();
    if (userId != null && route?.isNotEmpty == true) {
      await markRouteAsRead(userId, route!);
    }
  }

  Future<void> _cancelNotificationForPayload(
      Map<String, String?> payload) async {
    final entityTable = payload['entity_table']?.trim();
    final entityId = payload['entity_id']?.trim();
    if (entityTable?.isNotEmpty == true && entityId?.isNotEmpty == true) {
      await clearEntityNotifications(
        entityTable: entityTable!,
        entityId: entityId!,
      );
      return;
    }

    final route = payload['route']?.trim();
    if (route?.isNotEmpty == true) {
      await clearRouteNotifications(route!);
    }
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

    await _sendTopicNotification(
      title,
      body,
      topic,
      route: route,
      type: normalizedType,
    );
  }

  Future<void> sendDirectMessagePush({
    required String recipientUserId,
    required String senderName,
    required String conversationId,
    required String messageId,
    required String preview,
  }) async {
    final cleanRecipientId = recipientUserId.trim();
    if (kIsWeb || cleanRecipientId.isEmpty) return;

    await _sendTopicNotification(
      senderName.trim().isEmpty ? 'New message' : senderName.trim(),
      preview.trim().isEmpty ? 'Sent you a message.' : preview.trim(),
      userTopicFor(cleanRecipientId),
      route: '/inbox',
      type: 'direct_message',
      extraData: {
        'recipientUserId': cleanRecipientId,
        'conversationId': conversationId,
        'entityTable': 'direct_messages',
        'entityId': messageId,
      },
    );
  }

  Future<void> _sendTopicNotification(
    String title,
    String body,
    String topic, {
    String? route,
    required String type,
    Map<String, String> extraData = const {},
  }) async {
    final normalizedType = normalizeNotificationType(type);
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
          'data': extraData,
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
    await clearRouteNotifications(route);
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
    await clearEntityNotifications(
      entityTable: entityTable,
      entityId: entityId,
    );
  }

  Future<void> clearEntityNotifications({
    required String entityTable,
    required String entityId,
  }) async {
    if (kIsWeb) return;
    final tag = _entityNotificationTag(entityTable, entityId);
    final id = _stableNotificationId('entity|$entityTable|$entityId');
    await _localNotifications.cancel(id, tag: tag);
  }

  Future<void> clearRouteNotifications(String route) async {
    if (kIsWeb) return;
    final cleanRoute = normalizeRoute(route);
    if (cleanRoute == null) return;
    final tag = _routeNotificationTag(cleanRoute);
    final id = _stableNotificationId('route|$cleanRoute');
    await _localNotifications.cancel(id, tag: tag);
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
      entityTable: notification.entityTable,
      entityId: notification.entityId,
      notificationId: notification.id,
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

  Future<void> unsubscribeAlwaysOnTopics({String? userId}) async {
    if (kIsWeb) return;
    await unsubscribeFromTopic(appWideTopic);
    final cleanUserId = userId?.trim() ?? '';
    if (cleanUserId.isNotEmpty) {
      await unsubscribeFromTopic(userTopicFor(cleanUserId));
    }
  }

  /// Syncs user subscriptions based on SharedPreferences and Church ID
  Future<void> syncSubscriptions(
    String churchId, {
    String? userId,
    Iterable<String> roles = const [],
    Iterable<String> privileges = const [],
  }) async {
    if (kIsWeb) return;

    final prefs = await SharedPreferences.getInstance();
    final canUsePush = await hasPushPermission();
    await _syncAlwaysOnTopics(canUsePush: canUsePush, userId: userId);

    final cleanChurchId = churchId.trim();
    if (cleanChurchId.isEmpty) return;

    final shouldReceiveChurchWide =
        canUsePush && (prefs.getBool(churchWidePrefKey) ?? false);
    if (shouldReceiveChurchWide) {
      await subscribeToTopic('church_$cleanChurchId');
    } else {
      await unsubscribeFromTopic('church_$cleanChurchId');
    }

    final leaderTopic = 'church_${cleanChurchId}_leaders';
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

      String fullTopic = 'church_${cleanChurchId}_$topicSuffix';

      if (shouldSubscribe) {
        await subscribeToTopic(fullTopic);
      } else {
        await unsubscribeFromTopic(fullTopic);
      }
    }
  }

  Future<void> _syncAlwaysOnTopics({
    required bool canUsePush,
    String? userId,
  }) async {
    final cleanUserId = userId?.trim() ?? '';

    if (canUsePush) {
      await subscribeToTopic(appWideTopic);
      if (cleanUserId.isNotEmpty) {
        await subscribeToTopic(userTopicFor(cleanUserId));
      }
      return;
    }

    await unsubscribeFromTopic(appWideTopic);
    if (cleanUserId.isNotEmpty) {
      await unsubscribeFromTopic(userTopicFor(cleanUserId));
    }
  }

  Future<void> _seedStartupNotificationPreferences({
    required bool notifyAttendance,
    required bool notifyDailyMotivation,
    required bool notifyDailyQuiz,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    Future<void> seed(String key, bool value) async {
      if (!prefs.containsKey(key)) await prefs.setBool(key, value);
    }

    await seed(churchWidePrefKey, true);
    await seed('notify_service', notifyAttendance);
    await seed('notify_devotionals', notifyDailyMotivation);
    await seed('notify_daily_quiz', notifyDailyQuiz);
    await seed('notify_community', true);
    await seed('notify_prayer', true);
    await seed('notify_updates', true);
  }

  Future<bool?> isIgnoringBatteryOptimizations() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await _configChannel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
    } catch (error) {
      debugPrint('Battery optimization check skipped: $error');
      return null;
    }
  }

  Future<void> openBatteryOptimizationSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _configChannel.invokeMethod<void>(
        'openBatteryOptimizationSettings',
      );
    } catch (error) {
      debugPrint('Battery optimization settings failed: $error');
    }
  }

  String? _notificationTag({
    required String? type,
    required String? route,
    required String? entityTable,
    required String? entityId,
  }) {
    final cleanEntityTable = entityTable?.trim();
    final cleanEntityId = entityId?.trim();
    if (cleanEntityTable?.isNotEmpty == true &&
        cleanEntityId?.isNotEmpty == true) {
      return _entityNotificationTag(cleanEntityTable!, cleanEntityId!);
    }

    final cleanRoute = normalizeRoute(route);
    if (cleanRoute?.isNotEmpty == true) {
      return _routeNotificationTag(cleanRoute!);
    }

    return 'type:${normalizeNotificationType(type ?? 'general')}';
  }

  String _entityNotificationTag(String entityTable, String entityId) {
    return 'entity:${entityTable.trim()}:${entityId.trim()}';
  }

  String _routeNotificationTag(String route) {
    return 'route:${route.trim()}';
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
