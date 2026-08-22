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
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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

class _PushInstallationCredentials {
  const _PushInstallationCredentials({
    required this.installationId,
    required this.unregisterSecret,
  });

  final String installationId;
  final String unregisterSecret;
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
  // Keep this lazy. Firebase Messaging creates this singleton in a background
  // isolate where Firebase is initialized but the app's Supabase bootstrap has
  // not run. Data-only pushes only need local notifications, so eagerly reading
  // Supabase.instance here would abort delivery while the app is closed.
  SupabaseClient get _supabase => Supabase.instance.client;
  static const MethodChannel _configChannel =
      MethodChannel('love.graceconnect/config');
  StreamSubscription<List<AppNotification>>? _foregroundSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  Timer? _unansweredReminderTimer;
  DateTime _foregroundStartedAt = DateTime.now();
  final Set<String> _shownForegroundNotificationIds = {};
  final Set<String> _startupPermissionUsers = {};
  Set<String> _lastPushTopics = const {};
  Future<void> _topicPersistenceChain = Future<void>.value();
  Future<void>? _signedOutStartupCleanup;
  bool _initialized = false;
  static final Uri _topicNotificationEndpoint = Uri.parse(
    'https://us-central1-graceconnect-9a97c.cloudfunctions.net/sendTopicNotification',
  );
  static const String churchWidePrefKey = 'notify_church_wide';
  static const String appWideTopic = 'graceconnect_all';
  static const String _registeredDeliveryTopic =
      'graceconnect_registered_delivery_v1';
  static const String _installationIdKey = 'push_installation_id_v2';
  static const String _unregisterSecretKey = 'push_unregister_secret_v2';
  static const String _subscribedTopicsKey = 'push_subscribed_topics_v2';
  static const String _registeredUserKey = 'push_registered_user_v2';
  static const String _registeredTokenKey = 'push_registered_token_v2';
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
    'grace_room_invitation': _defaultSound,
    'event_invitation': _defaultSound,
    'event_rsvp_reminder': _defaultSound,
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
    'message_request_received': _NotificationSoundProfile(
      channelId: 'grace_messages_channel_v1',
      channelName: 'Grace Connect Messages',
      description: 'Message request notifications',
      soundName: 'grace_message',
    ),
    'message_request_accepted': _NotificationSoundProfile(
      channelId: 'grace_messages_channel_v1',
      channelName: 'Grace Connect Messages',
      description: 'Message request notifications',
      soundName: 'grace_message',
    ),
    'message_request_denied': _NotificationSoundProfile(
      channelId: 'grace_messages_channel_v1',
      channelName: 'Grace Connect Messages',
      description: 'Message request notifications',
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
    'bible_streak_reminder': _NotificationSoundProfile(
      channelId: 'grace_daily_word_channel_v1',
      channelName: 'Daily Word',
      description: 'Daily devotional and Bible streak reminders',
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
    if (_initialized) return;

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

    await _tokenRefreshSubscription?.cancel();
    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
      (token) => unawaited(_refreshPushRegistration(token)),
      onError: (Object error) {
        debugPrint('FCM token refresh listener failed: $error');
      },
    );
    _initialized = true;
    if (_supabase.auth.currentUser == null) {
      _signedOutStartupCleanup = _runSignedOutStartupCleanup();
      unawaited(_signedOutStartupCleanup);
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

    final startupCleanup = _signedOutStartupCleanup;
    if (startupCleanup != null) await startupCleanup;
    _signedOutStartupCleanup = null;
    await _cleanupPreviousAccountIfNeeded(userId);
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

    // Invitation rows use the delivery-run id as their deduplication entity,
    // while the signed route carries the actual room id. Never reinterpret the
    // run id as a room id when opening the notification.
    if (normalizedType == 'grace_room_invitation') {
      final invitationRoute = normalizeRoute(route);
      if (invitationRoute != null) return invitationRoute;
    }

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

    if ((cleanEntityTable == 'grace_rooms' ||
            cleanEntityTable == 'grace_room_messages' ||
            normalizedType == 'grace_room_invitation' ||
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
        normalizedType == 'message_request_received' ||
        normalizedType == 'message_request_accepted' ||
        normalizedType == 'message_request_denied' ||
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
    await _sendMembershipPush(membershipId, event: 'request');
  }

  Future<void> sendMembershipApprovedPush(String membershipId) async {
    await _sendMembershipPush(membershipId, event: 'approved');
  }

  Future<void> _sendMembershipPush(
    String membershipId, {
    required String event,
  }) async {
    final cleanMembershipId = membershipId.trim();
    if (kIsWeb || cleanMembershipId.isEmpty) return;

    try {
      final response = await _supabase.functions.invoke(
        'send-membership-request-push',
        body: {
          'membershipId': cleanMembershipId,
          'event': event,
        },
      ).timeout(const Duration(seconds: 12));
      final data = response.data;
      if (data is Map && data['ok'] == false) {
        debugPrint('Membership $event push queued with warning: $data');
      }
    } catch (error) {
      debugPrint('Membership $event push skipped: $error');
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

  Future<bool> subscribeToTopic(String topic) async {
    if (kIsWeb || topic.trim().isEmpty) return false;
    final cleanTopic = topic.trim();
    try {
      await _messaging.subscribeToTopic(cleanTopic);
      await _rememberTopicSubscription(cleanTopic, subscribed: true);
      debugPrint('Subscribed to topic: $cleanTopic');
      return true;
    } catch (error) {
      debugPrint('Topic subscription deferred ($cleanTopic): $error');
      return false;
    }
  }

  Future<bool> unsubscribeFromTopic(String topic) async {
    if (kIsWeb || topic.trim().isEmpty) return false;
    final cleanTopic = topic.trim();
    try {
      await _messaging.unsubscribeFromTopic(cleanTopic);
      await _rememberTopicSubscription(cleanTopic, subscribed: false);
      debugPrint('Unsubscribed from topic: $cleanTopic');
      return true;
    } catch (error) {
      debugPrint('Topic unsubscribe deferred ($cleanTopic): $error');
      return false;
    }
  }

  Future<void> unsubscribeFromChurchTopics(String churchId) async {
    if (kIsWeb || churchId.trim().isEmpty) return;
    await unsubscribeFromTopic('church_$churchId');
    await unsubscribeFromTopic('church_${churchId}_leaders');
    for (final suffix in topicMap.keys) {
      await unsubscribeFromTopic('church_${churchId}_$suffix');
    }
  }

  Future<void> unsubscribeAlwaysOnTopics({
    String? userId,
    String? churchId,
  }) async {
    if (kIsWeb) return;
    await _disableCurrentPushDevice();

    final prefs = await SharedPreferences.getInstance();
    final topics = await _storedSubscribedTopics();
    topics.add(appWideTopic);
    final rememberedUserId = prefs.getString(_registeredUserKey)?.trim() ?? '';
    final cleanUserId = (userId?.trim().isNotEmpty ?? false)
        ? userId!.trim()
        : rememberedUserId;
    if (cleanUserId.isNotEmpty) {
      topics.add(userTopicFor(cleanUserId));
    }
    final cleanChurchId = churchId?.trim() ?? '';
    if (cleanChurchId.isNotEmpty) {
      topics.add('church_$cleanChurchId');
      topics.add('church_${cleanChurchId}_leaders');
      for (final suffix in topicMap.keys) {
        topics.add('church_${cleanChurchId}_$suffix');
      }
    }

    // Keep the marker until every content topic has been removed. Otherwise a
    // signed-out installation could become eligible for the legacy fallback in
    // the middle of cleanup.
    final contentTopics = topics
        .where((topic) => topic != _registeredDeliveryTopic)
        .toList()
      ..sort();
    for (final topic in contentTopics) {
      await _retryTopicChange(topic, subscribe: false);
    }
    await _retryTopicChange(_registeredDeliveryTopic, subscribe: false);

    final remainingTopics = await _storedSubscribedTopics();
    if (remainingTopics.isEmpty) {
      await prefs.remove(_registeredUserKey);
    }
    _lastPushTopics = const {};
  }

  Future<void> _cleanupPreviousAccountIfNeeded(String currentUserId) async {
    final cleanCurrentUserId = currentUserId.trim();
    if (cleanCurrentUserId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final previousUserId = prefs.getString(_registeredUserKey)?.trim() ?? '';
    if (previousUserId.isEmpty || previousUserId == cleanCurrentUserId) return;

    await unsubscribeAlwaysOnTopics(userId: previousUserId);
  }

  Future<void> _runSignedOutStartupCleanup() async {
    try {
      await unsubscribeAlwaysOnTopics();
    } catch (error) {
      debugPrint('Signed-out push cleanup will retry next launch: $error');
    }
  }

  Future<void> _unsubscribeStoredTopicsOutside(
      Set<String> desiredTopics) async {
    final storedTopics = await _storedSubscribedTopics();
    final staleTopics = storedTopics
        .where((topic) =>
            topic != _registeredDeliveryTopic && !desiredTopics.contains(topic))
        .toList()
      ..sort();
    for (final topic in staleTopics) {
      await _retryTopicChange(topic, subscribe: false);
    }
  }

  Future<bool> _retryTopicChange(
    String topic, {
    required bool subscribe,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final succeeded = subscribe
          ? await subscribeToTopic(topic)
          : await unsubscribeFromTopic(topic);
      if (succeeded) return true;
      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    }
    return false;
  }

  Future<Set<String>> _storedSubscribedTopics() async {
    await _topicPersistenceChain;
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_subscribedTopicsKey) ?? const <String>[])
        .map((topic) => topic.trim())
        .where((topic) => topic.isNotEmpty)
        .toSet();
  }

  Future<void> _rememberTopicSubscription(
    String topic, {
    required bool subscribed,
  }) {
    _topicPersistenceChain = _topicPersistenceChain.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final topics =
            (prefs.getStringList(_subscribedTopicsKey) ?? const <String>[])
                .toSet();
        if (subscribed) {
          topics.add(topic);
        } else {
          topics.remove(topic);
        }
        final sortedTopics = topics.toList()..sort();
        if (sortedTopics.isEmpty) {
          await prefs.remove(_subscribedTopicsKey);
        } else {
          await prefs.setStringList(_subscribedTopicsKey, sortedTopics);
        }
      } catch (error) {
        debugPrint('Push topic state persistence skipped: $error');
      }
    });
    return _topicPersistenceChain;
  }

  Future<_PushInstallationCredentials> _installationCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    var installationId = prefs.getString(_installationIdKey)?.trim() ?? '';
    var unregisterSecret = prefs.getString(_unregisterSecretKey)?.trim() ?? '';
    final uuidPattern = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    if (!uuidPattern.hasMatch(installationId)) {
      installationId = const Uuid().v4();
      await prefs.setString(_installationIdKey, installationId);
    }
    if (unregisterSecret.length < 20) {
      unregisterSecret = '${const Uuid().v4()}${const Uuid().v4()}';
      await prefs.setString(_unregisterSecretKey, unregisterSecret);
    }
    return _PushInstallationCredentials(
      installationId: installationId,
      unregisterSecret: unregisterSecret,
    );
  }

  /// Syncs user subscriptions based on SharedPreferences and Church ID
  Future<void> syncSubscriptions(
    String churchId, {
    String? userId,
    // Retained for released call sites. Leader delivery is authorized by the
    // server RPC below, never by these denormalized client profile values.
    Iterable<String> roles = const [],
    Iterable<String> privileges = const [],
  }) async {
    if (kIsWeb) return;

    final prefs = await SharedPreferences.getInstance();
    final canUsePush = await hasPushPermission();
    final desiredTopics = <String>{};
    if (canUsePush) {
      desiredTopics.add(appWideTopic);
      final cleanUserId = userId?.trim() ?? '';
      if (cleanUserId.isNotEmpty) {
        desiredTopics.add(userTopicFor(cleanUserId));
      }
    }
    await _syncAlwaysOnTopics(canUsePush: canUsePush, userId: userId);

    final cleanChurchId = churchId.trim();
    if (cleanChurchId.isEmpty) {
      await _unsubscribeStoredTopicsOutside(desiredTopics);
      await _syncPushDeviceRegistration(
        desiredTopics,
        canUsePush: canUsePush,
      );
      return;
    }

    final shouldReceiveChurchWide =
        canUsePush && (prefs.getBool(churchWidePrefKey) ?? false);
    if (shouldReceiveChurchWide) {
      final topic = 'church_$cleanChurchId';
      desiredTopics.add(topic);
      await subscribeToTopic(topic);
    } else {
      await unsubscribeFromTopic('church_$cleanChurchId');
    }

    final leaderTopic = 'church_${cleanChurchId}_leaders';
    final canManageMembers =
        canUsePush && await _canManageChurchMembers(cleanChurchId);
    if (canManageMembers) {
      desiredTopics.add(leaderTopic);
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
        desiredTopics.add(fullTopic);
        await subscribeToTopic(fullTopic);
      } else {
        await unsubscribeFromTopic(fullTopic);
      }
    }

    await _unsubscribeStoredTopicsOutside(desiredTopics);
    await _syncPushDeviceRegistration(
      desiredTopics,
      canUsePush: canUsePush,
    );
  }

  Future<bool> _canManageChurchMembers(String churchId) async {
    if (_supabase.auth.currentUser == null || churchId.trim().isEmpty) {
      return false;
    }
    try {
      final result = await _supabase.rpc(
        'can_manage_church_members',
        params: {'target_church_id': churchId.trim()},
      ).timeout(const Duration(seconds: 8));
      return result == true;
    } catch (error) {
      debugPrint('Membership push capability check failed closed: $error');
      return false;
    }
  }

  Future<void> _syncPushDeviceRegistration(
    Set<String> topics, {
    required bool canUsePush,
  }) async {
    _lastPushTopics = Set<String>.unmodifiable(topics);
    if (!canUsePush) {
      await _disableCurrentPushDevice();
      await _retryTopicChange(_registeredDeliveryTopic, subscribe: false);
      return;
    }

    final registered = await _registerCurrentPushDevice(topics: topics);
    if (registered) {
      final markerSubscribed = await _retryTopicChange(
        _registeredDeliveryTopic,
        subscribe: true,
      );
      if (!markerSubscribed) {
        // Keep token delivery active. A missing marker can cause replacement of
        // the same tagged notification through the fallback, while removing the
        // registration here could lose the notification altogether.
        debugPrint(
          'Registered delivery marker unavailable; token delivery remains active.',
        );
      }
    } else {
      // The marker excludes registered installations from the legacy topic
      // fallback. Never keep it when registration failed.
      final markerRemoved = await _retryTopicChange(
        _registeredDeliveryTopic,
        subscribe: false,
      );
      if (!markerRemoved) {
        debugPrint(
          'Push fallback marker could not be removed; delivery will retry at the next sync.',
        );
      }
    }
  }

  Future<void> _refreshPushRegistration(String token) async {
    if (kIsWeb || _lastPushTopics.isEmpty) return;
    final registered = await _registerCurrentPushDevice(
      token: token,
      topics: _lastPushTopics,
    );
    if (registered) {
      await _retryTopicChange(_registeredDeliveryTopic, subscribe: true);
    } else {
      await _retryTopicChange(_registeredDeliveryTopic, subscribe: false);
    }
  }

  Future<bool> _registerCurrentPushDevice({
    String? token,
    required Set<String> topics,
  }) async {
    if (kIsWeb || _supabase.auth.currentUser == null) return false;

    try {
      final cleanToken = (token ?? await _messaging.getToken())?.trim() ?? '';
      if (cleanToken.isEmpty) return false;
      final credentials = await _installationCredentials();
      final packageInfo = await PackageInfo.fromPlatform();
      await _supabase.rpc(
        'register_push_device',
        params: {
          'p_token': cleanToken,
          'p_platform': _pushPlatformName(),
          'p_app_version': '${packageInfo.version}+${packageInfo.buildNumber}',
          'p_topics': topics.toList()..sort(),
          'p_installation_id': credentials.installationId,
          'p_unregister_secret': credentials.unregisterSecret,
        },
      ).timeout(const Duration(seconds: 12));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _registeredUserKey,
        _supabase.auth.currentUser!.id,
      );
      await prefs.setString(_registeredTokenKey, cleanToken);
      return true;
    } catch (error) {
      debugPrint('Push device registration unavailable; using topics: $error');
      return false;
    }
  }

  Future<bool> _disableCurrentPushDevice() async {
    if (kIsWeb) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentToken = (await _messaging.getToken())?.trim() ?? '';
      final rememberedToken =
          prefs.getString(_registeredTokenKey)?.trim() ?? '';
      final candidateTokens = {currentToken, rememberedToken}
        ..removeWhere((token) => token.isEmpty);
      if (candidateTokens.isEmpty) return false;
      final credentials = await _installationCredentials();
      var disabled = false;
      for (final token in candidateTokens) {
        final result = await _supabase.rpc(
          'unregister_push_device',
          params: {
            'p_token': token,
            'p_installation_id': credentials.installationId,
            'p_unregister_secret': credentials.unregisterSecret,
          },
        ).timeout(const Duration(seconds: 8));
        disabled = disabled || result == true;
      }
      if (disabled) await prefs.remove(_registeredTokenKey);
      return disabled;
    } catch (error) {
      debugPrint('Push device unregister skipped: $error');
      return false;
    }
  }

  String _pushPlatformName() {
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'unknown',
    };
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
}
