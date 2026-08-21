import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:native_geofence/native_geofence.dart';
import 'package:permission_handler/permission_handler.dart' as permissions;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/church_location.dart';
import '../models/service_schedule.dart';
import '../models/attendance_record.dart';
import 'attendance_dwell_session.dart';
import 'notification_service.dart';
import 'supabase_resilience.dart';

const String _attendanceSupabaseUrl =
    'https://nimgsgnkcvddomrgkawb.supabase.co';
const String _attendanceSupabaseAnonKey =
    'sb_publishable_-lsEclVqaNPAlO4h7z3vtw_Q8xZY3cN';

/// Entry point invoked by Android's native, battery-efficient Geofence API.
///
/// The plugin starts a short-lived background Flutter isolate for a transition,
/// rather than keeping a location foreground service alive. Supabase restores
/// and refreshes its persisted member session in that isolate before any
/// attendance write is attempted.
@pragma('vm:entry-point')
Future<void> attendanceGeofenceTriggered(
  GeofenceCallbackParams params,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    try {
      Supabase.instance.client;
    } catch (_) {
      await Supabase.initialize(
        url: _attendanceSupabaseUrl,
        anonKey: _attendanceSupabaseAnonKey,
        authOptions: const FlutterAuthClientOptions(
          authFlowType: AuthFlowType.pkce,
          detectSessionInUri: false,
        ),
      );
    }
    await AttendanceService().handleNativeGeofenceEvent(params);
  } catch (error, stackTrace) {
    debugPrint('Native attendance geofence callback failed: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

class AttendanceSetupStatus {
  final bool autoCheckInEnabled;
  final bool locationServicesEnabled;
  final LocationPermission permission;
  final bool hasChurchLocation;
  final bool hasServiceSchedule;
  final String? activeServiceName;
  final bool requiresBackgroundLocation;
  // null on platforms where this doesn't apply (iOS, web). false means
  // Android is still allowed to restrict this app in the background, which
  // silently blocks the geofence's background delivery even though
  // everything else here can show green -- the geofence stays registered,
  // Android just may not wake the app to act on it. This is the state that
  // makes auto-attendance look like it "stopped working" until the member
  // reopens the app.
  final bool? batteryOptimizationIgnored;

  const AttendanceSetupStatus({
    required this.autoCheckInEnabled,
    required this.locationServicesEnabled,
    required this.permission,
    required this.hasChurchLocation,
    required this.hasServiceSchedule,
    this.requiresBackgroundLocation = false,
    this.activeServiceName,
    this.batteryOptimizationIgnored,
  });

  bool get hasLocationPermission =>
      permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;

  bool get hasAutoAttendanceLocationPermission =>
      hasLocationPermission &&
      (!requiresBackgroundLocation || permission == LocationPermission.always);

  bool get canMonitor =>
      autoCheckInEnabled &&
      locationServicesEnabled &&
      hasAutoAttendanceLocationPermission &&
      hasChurchLocation &&
      hasServiceSchedule;

  List<String> get blockers {
    final missing = <String>[];
    if (!autoCheckInEnabled) missing.add('Auto check-in is turned off.');
    if (!locationServicesEnabled) {
      missing.add('Device location services are off.');
    }
    if (!hasLocationPermission) {
      missing.add('Location permission is not granted.');
    } else if (!hasAutoAttendanceLocationPermission) {
      missing.add(
        'Allow location all the time so Android can detect the church geofence when the app is closed.',
      );
    }
    if (!hasChurchLocation) missing.add('Church geofence location is not set.');
    if (!hasServiceSchedule) missing.add('No service schedule is configured.');
    if (requiresBackgroundLocation && batteryOptimizationIgnored == false) {
      missing.add(
        'Battery optimization is still restricting this app, which can silently block auto-attendance while the app is closed.',
      );
    }
    return missing;
  }
}

class AttendanceCheckInPrompt {
  const AttendanceCheckInPrompt({
    required this.hasActiveService,
    required this.canMarkPresent,
    required this.isInsideGeofence,
    required this.alreadyMarked,
    required this.message,
    this.serviceId,
    this.serviceName,
    this.distanceMeters,
    this.radiusMeters,
    this.requiredDwellMinutes = 10,
    this.currentDwellSeconds = 0,
  });

  final bool hasActiveService;
  final bool canMarkPresent;
  final bool isInsideGeofence;
  final bool alreadyMarked;
  final String message;
  final String? serviceId;
  final String? serviceName;
  final double? distanceMeters;
  final double? radiusMeters;
  final int requiredDwellMinutes;
  final int currentDwellSeconds;

  int get currentDwellMinutes => currentDwellSeconds ~/ 60;

  int get remainingDwellSeconds =>
      (requiredDwellMinutes * 60 - currentDwellSeconds).clamp(0, 59940).toInt();

  int get remainingDwellMinutes => (remainingDwellSeconds + 59) ~/ 60;
}

class AttendanceService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _activeServicePollTimer;
  Timer? _monitoringRestartTimer;
  Future<void>? _initializationFuture;
  String? _currentServiceId;
  bool _isMonitoring = false;
  bool _monitoringRequested = false;
  bool _isPollingLocation = false;
  bool _isProcessingLocation = false;
  int _monitoringRestartAttempts = 0;
  String _lastDebugStatus = 'Auto-attendance has not started yet.';
  static const String _pendingAttendanceQueueKey =
      'pending_attendance_records_v1';
  static const String _legacyRegisteredNativeGeofenceIdKey =
      'attendance_native_geofence_id_v1';
  static const String _registeredNativeGeofenceIdsKey =
      'attendance_native_geofence_ids_v2';
  static const String _registeredNativeGeofenceSignatureKey =
      'attendance_native_geofence_signature_v2';
  static const String _nativeGeofenceIdPrefix = 'grace_auto_attendance_';
  static const Duration _requiredClearOutsideDuration = Duration(minutes: 2);
  static const Duration _maximumClearOutsideEvidenceGap = Duration(seconds: 90);

  // Singleton pattern for continuous monitoring
  static final AttendanceService _instance = AttendanceService._internal();
  factory AttendanceService() => _instance;
  AttendanceService._internal() {
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('ic_stat_grace_connect');
    const iosSettings = DarwinInitializationSettings();
    const settings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);
    await _notificationsPlugin.initialize(settings);
  }

  Future<void> initialize() {
    return _initializationFuture ??=
        _initialize().whenComplete(() => _initializationFuture = null);
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final autoCheckInEnabled = prefs.getBool('auto_check_in') ?? false;
    _startPendingAttendanceSync();
    unawaited(flushPendingAttendance());
    if (!autoCheckInEnabled) {
      _monitoringRequested = false;
      stopMonitoring();
      _updateDebugStatus('Auto check-in disabled in settings.');
      return;
    }
    _monitoringRequested = true;

    // Several screens initialize this singleton. Keep the existing listener so
    // navigating or tapping Recheck cannot restart the dwell countdown.
    if (_isMonitoring &&
        (_positionStreamSubscription != null || _usesNativeAndroidGeofence)) {
      if (_usesNativeAndroidGeofence) {
        await _registerAndroidNativeGeofence();
      } else {
        unawaited(_pollCurrentLocationForAttendance());
      }
      return;
    }

    _clearMonitoringState(resetRestartAttempts: false);

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _setMonitoring(false);
      _updateDebugStatus('Device location services are turned off.');
      return;
    }

    final permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.deniedForever) {
      _setMonitoring(false);
      _updateDebugStatus(
          'Location permission is permanently denied. Enable it in system settings.');
      return;
    }

    if (permission == LocationPermission.denied) {
      _setMonitoring(false);
      _updateDebugStatus('Location permission was denied.');
      return;
    }

    if (_needsAlwaysLocationPermission &&
        permission != LocationPermission.always) {
      _setMonitoring(false);
      _updateDebugStatus(
        'Auto-attendance needs “Always” location access so it can detect '
        'your arrival even when the app is closed.',
      );
      return;
    }

    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      await _startMonitoring();
    }
  }

  bool get _usesNativeAndroidGeofence =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  // iOS auto-attendance runs on a continuous Geolocator position stream
  // (see _startMonitoring), not the native geofence API Android uses -- but
  // that stream is paused by iOS the moment the app truly backgrounds
  // unless the app holds "Always" location access, same as Android's
  // background geofence. Without this, iOS silently "starts" monitoring on
  // While-Using-App access and then goes quiet the instant the phone locks,
  // which looks identical to auto-attendance being broken.
  bool get _needsAlwaysLocationPermission => !kIsWeb;

  /// Requests only the permissions needed for user-enabled auto-attendance.
  /// UI callers must show the prominent background-location disclosure first.
  /// Both Android and iOS request "Always" here -- permission_handler
  /// drives each platform's real native flow for that upgrade (Android's
  /// second system dialog; iOS's Settings hand-off after the first grant).
  Future<bool> requestAutoAttendancePermissions() async {
    if (kIsWeb) return false;

    final foreground =
        await permissions.Permission.locationWhenInUse.request();
    if (!foreground.isGranted) return false;

    var background = await permissions.Permission.locationAlways.status;
    if (!background.isGranted) {
      background = await permissions.Permission.locationAlways.request();
    }
    return background.isGranted;
  }

  // Debug / Status Streams
  final _isMonitoringController = StreamController<bool>.broadcast();
  Stream<bool> get isMonitoringStream => _isMonitoringController.stream;
  bool get isMonitoring => _isMonitoring;

  final _debugStatusController = StreamController<String>.broadcast();
  Stream<String> get debugStatusStream => _debugStatusController.stream;
  String get lastDebugStatus => _lastDebugStatus;

  void _updateDebugStatus(String status) {
    _lastDebugStatus = status;
    _debugStatusController.add(status);
  }

  void _setMonitoring(bool value) {
    _isMonitoring = value;
    _isMonitoringController.add(value);
  }

  Future<void> _startMonitoring() async {
    _monitoringRestartTimer?.cancel();
    _monitoringRestartTimer = null;
    _monitoringRequested = true;

    if (_usesNativeAndroidGeofence) {
      final registered = await _registerAndroidNativeGeofence();
      _setMonitoring(registered);
      if (!registered) return;
      _updateDebugStatus(
        'Android geofence active. Auto-attendance will check the scheduled service after the required dwell.',
      );
      unawaited(_pollCurrentLocationForAttendance());
      return;
    }

    _setMonitoring(true);
    _updateDebugStatus('Starting monitoring...');
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20,
    );

    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
            (Position position) async {
      _monitoringRestartAttempts = 0;
      try {
        await _checkLocationLogic(position);
      } catch (e) {
        debugPrint('Auto-attendance check failed: $e');
        _updateDebugStatus('Auto-attendance check failed: $e');
      }
    }, onError: (e) {
      debugPrint('Location stream error: $e');
      _recoverFromLocationStreamError(e);
    });

    unawaited(_pollCurrentLocationForAttendance());
    _activeServicePollTimer?.cancel();
    _activeServicePollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_pollCurrentLocationForAttendance()),
    );
  }

  void _recoverFromLocationStreamError(Object error) {
    unawaited(_positionStreamSubscription?.cancel());
    _positionStreamSubscription = null;
    _activeServicePollTimer?.cancel();
    _activeServicePollTimer = null;
    _isPollingLocation = false;
    _setMonitoring(false);

    if (!_monitoringRequested || _monitoringRestartTimer != null) {
      _updateDebugStatus('Auto-attendance location monitoring paused.');
      return;
    }

    const delays = <Duration>[
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
      Duration(minutes: 1),
    ];
    final delay =
        delays[_monitoringRestartAttempts.clamp(0, delays.length - 1).toInt()];
    _monitoringRestartAttempts++;
    _updateDebugStatus(
      'Location monitoring was interrupted. Retrying automatically in ${delay.inSeconds} seconds.',
    );
    _monitoringRestartTimer = Timer(delay, () {
      _monitoringRestartTimer = null;
      if (!_monitoringRequested) return;
      unawaited(initialize().catchError((Object restartError) {
        debugPrint('Auto-attendance restart failed: $restartError');
        _recoverFromLocationStreamError(restartError);
      }));
    });
  }

  Future<void> _pollCurrentLocationForAttendance() async {
    if (_isPollingLocation || !_isMonitoring) return;

    _isPollingLocation = true;
    try {
      final position = await _getReliablePosition();
      _monitoringRestartAttempts = 0;
      await _checkLocationLogic(position);
    } catch (error) {
      debugPrint('Auto-attendance polling failed: $error');
      _updateDebugStatus(
          'Auto-attendance polling failed. Tap Recheck if this continues.');
    } finally {
      _isPollingLocation = false;
    }
  }

  Future<void> _checkLocationLogic(Position position) async {
    if (_isProcessingLocation) return;
    _isProcessingLocation = true;
    try {
      await _processLocationLogic(position);
    } finally {
      _isProcessingLocation = false;
    }
  }

  Future<void> _processLocationLogic(Position position) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      _updateDebugStatus('User not logged in');
      return;
    }

    // Profiles created during different migrations may identify the same auth
    // user through either users.id or users.uid. Active membership is the
    // canonical fallback, so those profiles still receive auto-attendance.
    final placeId = await _getCurrentUserChurchId(user.id);
    if (placeId == null || placeId.isEmpty) {
      _updateDebugStatus('No church configured for user');
      return;
    }

    final churchLocation = await _getChurchLocation(placeId);
    if (churchLocation == null) {
      _updateDebugStatus('Church location not found');
      return;
    }

    // 2. Check Geofence
    double distanceInMeters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      churchLocation.latitude,
      churchLocation.longitude,
    );

    if (distanceInMeters <= churchLocation.radiusMeters) {
      // Inside Geofence
      _updateDebugStatus(
          'Inside Geofence (${distanceInMeters.toStringAsFixed(1)}m)');
      await _handleInsideGeofence(user.id, placeId);
    } else {
      final accuracyBuffer = position.accuracy.clamp(25, 150).toDouble();
      final clearlyOutside =
          distanceInMeters > churchLocation.radiusMeters + accuracyBuffer;
      final activeService = await getActiveService(placeId);
      final serviceId = activeService?['id']?.toString() ?? _currentServiceId;
      final dwellExpired = serviceId == null
          ? true
          : await _recordOutsideObservation(
              user.id,
              serviceId,
              clearlyOutside: clearlyOutside,
            );

      if (dwellExpired) {
        _currentServiceId = null;
        _updateDebugStatus(
          'Outside Geofence (${distanceInMeters.toStringAsFixed(1)}m)',
        );
      } else {
        _updateDebugStatus(
          clearlyOutside
              ? 'Outside geofence; waiting for a stable GPS reading before resetting dwell.'
              : 'GPS accuracy is near the geofence edge; preserving the dwell timer.',
        );
      }
    }
  }

  Future<Position> _getReliablePosition() async {
    // A single high-accuracy (GPS-only) request with a 20s window regularly
    // fails to get any fix at all inside a church building -- concrete and
    // metal roofing block the GPS signal, which is exactly when a member is
    // trying to check in. Reported in production as a scary "check your
    // connection" error while sitting inside the sanctuary with a normal
    // network connection; the real problem was GPS, not connectivity.
    // Falling back to reduced accuracy (network/cell-assisted, works
    // indoors) is far more likely to actually succeed, and is still easily
    // precise enough for a geofence radius measured in tens of meters.
    for (final accuracy in const [
      LocationAccuracy.high,
      LocationAccuracy.medium,
      LocationAccuracy.reduced,
    ]) {
      try {
        return await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: accuracy,
            timeLimit: const Duration(seconds: 15),
          ),
        );
      } catch (_) {
        continue;
      }
    }

    // Every live attempt failed. A last-known fix is better than nothing,
    // and is widened from 5 to 15 minutes -- someone who has been sitting
    // still inside the same building for a while is not meaningfully more
    // likely to have moved than someone whose last fix is 6 minutes old.
    final lastKnown = await Geolocator.getLastKnownPosition();
    final timestamp = lastKnown?.timestamp;
    final isRecent = timestamp != null &&
        DateTime.now().difference(timestamp).abs() <=
            const Duration(minutes: 15);
    if (lastKnown != null && isRecent) return lastKnown;

    throw Exception(
      'Your device could not get a location fix. GPS can be unreliable indoors -- try moving near a window or door, or wait a moment and tap Recheck.',
    );
  }

  Future<ChurchLocation?> _getChurchLocation(String churchId) async {
    final locations = await _supabase
        .from('church_locations')
        .select()
        .or('placeId.eq.$churchId,churchId.eq.$churchId')
        .limit(1);

    if (locations.isNotEmpty) {
      return ChurchLocation.fromMap(locations.first);
    }

    final churches = await _supabase
        .from('churches')
        .select('id, placeId, latitude, longitude, timezone, address')
        .or('id.eq.$churchId,placeId.eq.$churchId')
        .limit(1);

    if (churches.isEmpty) return null;
    final church = churches.first;
    final latitude = church['latitude'];
    final longitude = church['longitude'];
    if (latitude == null || longitude == null) return null;

    return ChurchLocation.fromMap({
      'churchId': church['id'] ?? churchId,
      'placeId': church['placeId'] ?? church['id'] ?? churchId,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': 150,
      'timezone': church['timezone'] ?? 'America/Jamaica',
    });
  }

  Future<ChurchLocation?> getChurchLocation(String churchId) {
    return _getChurchLocation(churchId);
  }

  Future<String?> _getCurrentUserChurchId(String userId) async {
    final users = await _supabase
        .from('users')
        .select('placeId')
        .or('uid.eq.$userId,id.eq.$userId')
        .limit(1);
    final profileChurchId =
        users.isEmpty ? '' : users.first['placeId']?.toString().trim() ?? '';
    if (profileChurchId.isNotEmpty) return profileChurchId;

    final memberships = await _supabase
        .from('church_memberships')
        .select('church_id')
        .eq('user_id', userId)
        .eq('membership_status', 'active')
        .order('reviewed_at', ascending: false)
        .limit(1);
    if (memberships.isEmpty) return null;
    final membershipChurchId =
        memberships.first['church_id']?.toString().trim() ?? '';
    return membershipChurchId.isEmpty ? null : membershipChurchId;
  }

  String _nativeGeofenceId(String churchId, int dwellMinutes) {
    final safeChurchId = churchId.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '_',
    );
    return '$_nativeGeofenceIdPrefix${safeChurchId}_dwell_$dwellMinutes';
  }

  String _nativeGeofenceSignature(
    String churchId,
    ChurchLocation churchLocation,
    List<int> dwellMinutes,
  ) {
    return <String>[
      churchId,
      churchLocation.latitude.toStringAsFixed(6),
      churchLocation.longitude.toStringAsFixed(6),
      churchLocation.radiusMeters.toStringAsFixed(1),
      dwellMinutes.join(','),
    ].join('|');
  }

  Future<List<int>> _configuredNativeDwellMinutes(String churchId) async {
    final schedules = await _supabase
        .from('service_schedules')
        .select('minimumDwellMinutes')
        .eq('churchId', churchId)
        .eq('attendanceEnabled', true);
    final values = schedules
        .map(
            (row) => int.tryParse(row['minimumDwellMinutes']?.toString() ?? ''))
        .whereType<int>()
        .where((minutes) => minutes > 0 && minutes <= 60)
        .toSet()
        .toList()
      ..sort();
    return values.isEmpty ? const [10] : values;
  }

  Set<String> _storedNativeGeofenceIds(SharedPreferences prefs) {
    final ids = <String>{
      ...?prefs.getStringList(_registeredNativeGeofenceIdsKey),
    };
    final legacyId = prefs.getString(_legacyRegisteredNativeGeofenceIdKey);
    if (legacyId != null && legacyId.isNotEmpty) ids.add(legacyId);
    return ids;
  }

  Future<bool> _registerAndroidNativeGeofence() async {
    if (!_usesNativeAndroidGeofence) return false;

    final user = _supabase.auth.currentUser;
    if (user == null) {
      _updateDebugStatus('Sign in again to register auto-attendance.');
      return false;
    }

    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always) {
      _updateDebugStatus(
        'Allow location all the time to register Android auto-attendance.',
      );
      return false;
    }

    final churchId = await _getCurrentUserChurchId(user.id);
    if (churchId == null || churchId.isEmpty) {
      _updateDebugStatus('No active church is configured for this member.');
      return false;
    }

    final churchLocation = await _getChurchLocation(churchId);
    if (churchLocation == null) {
      _updateDebugStatus(
        'The church geofence must be configured before auto-attendance can start.',
      );
      return false;
    }

    final dwellMinutes = await _configuredNativeDwellMinutes(churchId);
    final geofenceIds = dwellMinutes
        .map((minutes) => _nativeGeofenceId(churchId, minutes))
        .toList(growable: false);
    final geofenceSignature = _nativeGeofenceSignature(
      churchId,
      churchLocation,
      dwellMinutes,
    );
    final prefs = await SharedPreferences.getInstance();
    final previousIds = _storedNativeGeofenceIds(prefs);
    final previousSignature =
        prefs.getString(_registeredNativeGeofenceSignatureKey);

    try {
      await NativeGeofenceManager.instance.initialize();
      if (previousSignature == geofenceSignature) {
        final registeredIds =
            await NativeGeofenceManager.instance.getRegisteredGeofenceIds();
        if (geofenceIds.every(registeredIds.contains)) {
          // Re-opening Attendance or tapping Recheck must not replace the
          // native geofences: doing so restarts Android's dwell countdown.
          return true;
        }
      }
      for (final previousId in previousIds.difference(geofenceIds.toSet())) {
        try {
          await NativeGeofenceManager.instance.removeGeofenceById(previousId);
        } catch (_) {
          // A church transfer can leave a stale local ID after Android has
          // already discarded the old geofence. Registration can continue.
        }
      }

      for (final minutes in dwellMinutes) {
        await NativeGeofenceManager.instance.createGeofence(
          Geofence(
            id: _nativeGeofenceId(churchId, minutes),
            location: Location(
              latitude: churchLocation.latitude,
              longitude: churchLocation.longitude,
            ),
            radiusMeters: churchLocation.radiusMeters,
            triggers: const {
              GeofenceEvent.enter,
              GeofenceEvent.exit,
              GeofenceEvent.dwell,
            },
            iosSettings: const IosGeofenceSettings(initialTrigger: false),
            androidSettings: AndroidGeofenceSettings(
              initialTriggers: const {GeofenceEvent.enter},
              loiteringDelay: Duration(minutes: minutes),
              notificationResponsiveness: const Duration(minutes: 1),
            ),
          ),
          attendanceGeofenceTriggered,
        );
      }
      await prefs.setStringList(_registeredNativeGeofenceIdsKey, geofenceIds);
      await prefs.remove(_legacyRegisteredNativeGeofenceIdKey);
      await prefs.setString(
        _registeredNativeGeofenceSignatureKey,
        geofenceSignature,
      );
      return true;
    } catch (error) {
      debugPrint('Could not register Android attendance geofence: $error');
      _updateDebugStatus(
        'Android could not register the church geofence. Check “Allow all the time” location access and Google Play services.',
      );
      return false;
    }
  }

  Future<void> _removeAndroidNativeGeofence() async {
    if (!_usesNativeAndroidGeofence) return;
    final prefs = await SharedPreferences.getInstance();
    final geofenceIds = _storedNativeGeofenceIds(prefs);
    if (geofenceIds.isEmpty) return;

    try {
      await NativeGeofenceManager.instance.initialize();
      for (final geofenceId in geofenceIds) {
        await NativeGeofenceManager.instance.removeGeofenceById(geofenceId);
      }
    } catch (error) {
      debugPrint('Android attendance geofence removal skipped: $error');
    } finally {
      await prefs.remove(_registeredNativeGeofenceIdsKey);
      await prefs.remove(_legacyRegisteredNativeGeofenceIdKey);
      await prefs.remove(_registeredNativeGeofenceSignatureKey);
    }
  }

  Future<void> handleNativeGeofenceEvent(
    GeofenceCallbackParams params,
  ) async {
    if (!_usesNativeAndroidGeofence || params.geofences.isEmpty) return;

    final user = _supabase.auth.currentUser;
    if (user == null) {
      debugPrint('Attendance geofence ignored because the session expired.');
      return;
    }

    final churchId = await _getCurrentUserChurchId(user.id);
    if (churchId == null || churchId.isEmpty) return;
    final safeChurchId = churchId.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '_',
    );
    final expectedPrefix = '$_nativeGeofenceIdPrefix${safeChurchId}_dwell_';
    if (!params.geofences
        .any((geofence) => geofence.id.startsWith(expectedPrefix))) {
      debugPrint(
          'Attendance geofence ignored after church membership changed.');
      return;
    }

    final observedAt = DateTime.now();
    final activeService = await getActiveServiceAt(churchId, observedAt);
    final serviceId = activeService?['id']?.toString();

    if (params.event == GeofenceEvent.exit) {
      if (serviceId != null && serviceId.isNotEmpty) {
        await _clearDwellEntry(user.id, serviceId);
      }
      _updateDebugStatus('Android detected that the member left the geofence.');
      return;
    }

    if (activeService == null || serviceId == null || serviceId.isEmpty) {
      _updateDebugStatus(
        'Church geofence detected, but no attendance-enabled service is open.',
      );
      return;
    }

    if (params.event == GeofenceEvent.enter) {
      await _readOrStartDwellEntry(
        user.id,
        serviceId,
        observedAt: observedAt,
      );
      _updateDebugStatus('Android detected arrival at church.');
      return;
    }

    if (params.event != GeofenceEvent.dwell) return;

    final requiredDwellMinutes =
        activeService['minimumDwellMinutes'] as int? ?? 10;
    final requiredGeofenceId =
        _nativeGeofenceId(churchId, requiredDwellMinutes);
    if (!params.geofences
        .any((geofence) => geofence.id == requiredGeofenceId)) {
      // Multiple service schedules can use different dwell requirements at
      // the same church. Only the active service's exact timer may check in.
      return;
    }

    final churchLocation = await _getChurchLocation(churchId);
    final triggerLocation = params.location;
    if (churchLocation == null) return;
    if (triggerLocation != null) {
      final distance = Geolocator.distanceBetween(
        triggerLocation.latitude,
        triggerLocation.longitude,
        churchLocation.latitude,
        churchLocation.longitude,
      );
      if (distance > churchLocation.radiusMeters + 50) {
        debugPrint(
          'Delayed attendance dwell ignored because the trigger location is no longer near church.',
        );
        return;
      }
    }

    await _initializeNotifications();
    await _markPresent(
      user.id,
      churchId,
      serviceId,
      activeService['startTime']?.toString(),
      activeService['name']?.toString(),
      checkedInAt: observedAt,
    );
  }

  Future<void> saveChurchLocation({
    required String churchId,
    required double latitude,
    required double longitude,
    required double radiusMeters,
    String? address,
  }) async {
    await _supabase.from('church_locations').upsert({
      'placeId': churchId,
      'churchId': churchId,
      'latitude': latitude,
      'longitude': longitude,
      'radiusMeters': radiusMeters,
      'timezone': 'America/Jamaica',
      if (address != null && address.trim().isNotEmpty)
        'address': address.trim(),
      'updatedAt': DateTime.now().toIso8601String(),
    });

    _updateDebugStatus('Church geofence saved for auto-attendance.');
    if (_usesNativeAndroidGeofence && _monitoringRequested) {
      unawaited(_registerAndroidNativeGeofence());
    }
  }

  /// Returns the currently active recurring service for the given church.
  Future<Map<String, dynamic>?> getActiveService(String churchId) async {
    return getActiveServiceAt(churchId, DateTime.now());
  }

  Future<Map<String, dynamic>?> getActiveServiceAt(
    String churchId,
    DateTime observedAt,
  ) async {
    final jamaicaNow = _jamaicaWallClock(observedAt);
    final servicesSnapshot = await _supabase
        .from('service_schedules')
        .select()
        .eq('churchId', churchId)
        .eq('dayOfWeek', jamaicaNow.weekday)
        .eq('attendanceEnabled', true);

    for (var doc in servicesSnapshot) {
      final schedule = ServiceSchedule.fromMap(doc);
      if (_isTimeWithinSchedule(observedAt, schedule)) {
        return {
          'id': schedule.serviceId,
          'startTime': schedule.startTime,
          'name': schedule.name.isNotEmpty ? schedule.name : 'Church Service',
          'minimumDwellMinutes': schedule.minimumDwellMinutes,
        };
      }
    }
    return null;
  }

  Future<void> _handleInsideGeofence(String userId, String churchId) async {
    // 3. Check Schedule
    final activeService = await getActiveService(churchId);

    if (activeService == null) {
      _updateDebugStatus('Inside, but no active service.');
      return;
    }

    final activeServiceId = activeService['id']!;
    final activeServiceStartTime = activeService['startTime']!;
    final activeServiceName = activeService['name']!;
    final requiredDwellMinutes =
        activeService['minimumDwellMinutes'] as int? ?? 10;

    // Always restore the durable session before calculating dwell. The app has
    // several legitimate initialization entry points, and none of them should
    // be able to overwrite a countdown that is already in progress.
    final observedAt = DateTime.now();
    final entryTime = await _readOrStartDwellEntry(
      userId,
      activeServiceId,
      observedAt: observedAt,
    );
    _currentServiceId = activeServiceId;
    final dwellDuration = observedAt.difference(entryTime);
    final requiredDwellSeconds = requiredDwellMinutes * 60;
    _updateDebugStatus(
        'Dwelling: ${_formatDwellCountdown((requiredDwellSeconds - dwellDuration.inSeconds).clamp(0, 59940).toInt())} remaining');

    if (dwellDuration.inSeconds >= requiredDwellSeconds) {
      _updateDebugStatus('Marking present...');
      // entryTime is when this person was first verified on church
      // property, not "now" (which is always requiredDwellMinutes later by
      // design, and can be pushed even further out by background delivery
      // delays). Grading lateness against the write time instead of the
      // true arrival time was inflating minutesLate by roughly the dwell
      // window for everyone, and could flip an on-time arrival into "late"
      // outright once background delays stacked on top of it.
      await _markPresent(
        userId,
        churchId,
        activeServiceId,
        activeServiceStartTime,
        activeServiceName,
        checkedInAt: entryTime,
      );
    }
  }

  bool _isTimeWithinSchedule(DateTime now, ServiceSchedule schedule) {
    final jamaicaNow = _jamaicaWallClock(now);
    final startParts = _parseTimeParts(schedule.startTime);
    final endParts = _parseTimeParts(schedule.endTime);
    if (startParts == null || endParts == null) {
      _updateDebugStatus('A service schedule has an invalid time format.');
      return false;
    }

    final startTime = DateTime(jamaicaNow.year, jamaicaNow.month,
        jamaicaNow.day, startParts[0], startParts[1]);
    final endTime = DateTime(jamaicaNow.year, jamaicaNow.month, jamaicaNow.day,
        endParts[0], endParts[1]);

    final validStart = startTime.subtract(
      Duration(minutes: schedule.checkInOpensMinutesBefore),
    );
    final validEnd = endTime.add(
      Duration(minutes: schedule.checkInClosesMinutesAfter),
    );

    return jamaicaNow.isAfter(validStart) && jamaicaNow.isBefore(validEnd);
  }

  DateTime _jamaicaWallClock(DateTime instant) {
    final jamaica = instant.toUtc().subtract(const Duration(hours: 5));
    return DateTime(
      jamaica.year,
      jamaica.month,
      jamaica.day,
      jamaica.hour,
      jamaica.minute,
      jamaica.second,
      jamaica.millisecond,
      jamaica.microsecond,
    );
  }

  DateTime _jamaicaDayStartUtc(DateTime instant) {
    final jamaica = _jamaicaWallClock(instant);
    return DateTime.utc(jamaica.year, jamaica.month, jamaica.day, 5);
  }

  String _jamaicaDateKey(DateTime instant) {
    final jamaica = _jamaicaWallClock(instant);
    return '${jamaica.year.toString().padLeft(4, '0')}-'
        '${jamaica.month.toString().padLeft(2, '0')}-'
        '${jamaica.day.toString().padLeft(2, '0')}';
  }

  List<int>? _parseTimeParts(String value) {
    final parts = value.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return [hour, minute];
  }

  String _formatDwellCountdown(int seconds) {
    final safeSeconds = seconds.clamp(0, 59940).toInt();
    final minutes = safeSeconds ~/ 60;
    final remainder = safeSeconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }

  Future<void> _markPresent(
    String userId,
    String churchId,
    String serviceId,
    String? serviceStartTime,
    String? serviceName, {
    String method = 'auto_geofence',
    DateTime? checkedInAt,
  }) async {
    final effectiveCheckedInAt = checkedInAt ?? DateTime.now();
    // A failed duplicate-check must not prevent the offline queue from saving
    // attendance when the dwell countdown completes.
    if (await _hasAttendanceForToday(
      userId,
      churchId,
      serviceId,
      continueWhenOffline: true,
      forTimestamp: effectiveCheckedInAt,
    )) {
      _updateDebugStatus('Already marked present for today.');
      return;
    }

    // Calculate Late Status
    String status = 'on_time';
    int? minutesLate;

    if (serviceStartTime != null) {
      final now = _jamaicaWallClock(effectiveCheckedInAt);
      final startParts = _parseTimeParts(serviceStartTime);
      if (startParts != null) {
        final scheduleTime = DateTime(
            now.year, now.month, now.day, startParts[0], startParts[1]);

        // Configurable Grace Period (10 mins)
        final graceTime = scheduleTime.add(const Duration(minutes: 10));

        if (now.isAfter(graceTime)) {
          status = 'late';
          minutesLate = now.difference(scheduleTime).inMinutes;
        }
      }
    }

    final record = AttendanceRecord(
      id: '',
      userId: userId,
      churchId: churchId,
      serviceId: serviceId,
      timestamp: effectiveCheckedInAt,
      method: method,
      present: true,
      status: status,
      minutesLate: minutesLate,
      serviceName: serviceName,
    );

    await _insertAttendanceRecord(record);
    debugPrint('Marked present successfully: $status');
    _updateDebugStatus('Success! Marked present ($status)');
    await _clearDwellEntry(userId, serviceId);

    // Trigger local notification
    _showPostServiceNotification(status);
  }

  Future<AttendanceCheckInPrompt> getCurrentCheckInPrompt(
      String churchId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return const AttendanceCheckInPrompt(
        hasActiveService: false,
        canMarkPresent: false,
        isInsideGeofence: false,
        alreadyMarked: false,
        message: 'Sign in again before marking attendance.',
      );
    }

    final activeService = await getActiveService(churchId);
    if (activeService == null) {
      return const AttendanceCheckInPrompt(
        hasActiveService: false,
        canMarkPresent: false,
        isInsideGeofence: false,
        alreadyMarked: false,
        message: 'No recurring service is in session right now.',
      );
    }

    final serviceId = activeService['id'] as String;
    final serviceName = activeService['name'] as String;
    final requiredDwellMinutes =
        activeService['minimumDwellMinutes'] as int? ?? 10;

    if (await _hasAttendanceForToday(user.id, churchId, serviceId)) {
      return AttendanceCheckInPrompt(
        hasActiveService: true,
        canMarkPresent: false,
        isInsideGeofence: true,
        alreadyMarked: true,
        message: 'You are already marked for $serviceName.',
        serviceId: serviceId,
        serviceName: serviceName,
        requiredDwellMinutes: requiredDwellMinutes,
      );
    }

    final churchLocation = await _getChurchLocation(churchId);
    if (churchLocation == null) {
      return AttendanceCheckInPrompt(
        hasActiveService: true,
        canMarkPresent: false,
        isInsideGeofence: false,
        alreadyMarked: false,
        message: 'The pastor needs to set the church geofence first.',
        serviceId: serviceId,
        serviceName: serviceName,
        requiredDwellMinutes: requiredDwellMinutes,
      );
    }

    final permissionReady = await _ensureLocationPermission();
    if (!permissionReady) {
      return AttendanceCheckInPrompt(
        hasActiveService: true,
        canMarkPresent: false,
        isInsideGeofence: false,
        alreadyMarked: false,
        message: 'Location permission is needed to verify you are at church.',
        serviceId: serviceId,
        serviceName: serviceName,
        requiredDwellMinutes: requiredDwellMinutes,
      );
    }

    final position = await _getReliablePosition();
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      churchLocation.latitude,
      churchLocation.longitude,
    );
    final isInside = distance <= churchLocation.radiusMeters;

    if (!isInside) {
      final accuracyBuffer = position.accuracy.clamp(25, 150).toDouble();
      await _recordOutsideObservation(
        user.id,
        serviceId,
        clearlyOutside: distance > churchLocation.radiusMeters + accuracyBuffer,
      );
      return AttendanceCheckInPrompt(
        hasActiveService: true,
        canMarkPresent: false,
        isInsideGeofence: false,
        alreadyMarked: false,
        message:
            'You are ${distance.toStringAsFixed(0)}m from church. Attendance unlocks on property.',
        serviceId: serviceId,
        serviceName: serviceName,
        distanceMeters: distance,
        radiusMeters: churchLocation.radiusMeters,
        requiredDwellMinutes: requiredDwellMinutes,
      );
    }

    final observedAt = DateTime.now();
    final entryTime = await _readOrStartDwellEntry(
      user.id,
      serviceId,
      observedAt: observedAt,
    );
    final currentDwellSeconds = observedAt.difference(entryTime).inSeconds;
    final requiredDwellSeconds = requiredDwellMinutes * 60;
    final remainingDwellSeconds =
        (requiredDwellSeconds - currentDwellSeconds).clamp(0, 59940).toInt();
    final canMarkPresent = currentDwellSeconds >= requiredDwellSeconds;

    return AttendanceCheckInPrompt(
      hasActiveService: true,
      canMarkPresent: canMarkPresent,
      isInsideGeofence: true,
      alreadyMarked: false,
      message: canMarkPresent
          ? 'You are verified on-site for $serviceName.'
          : 'Stay on property for ${_formatDwellCountdown(remainingDwellSeconds)} to unlock automatic check-in.',
      serviceId: serviceId,
      serviceName: serviceName,
      distanceMeters: distance,
      radiusMeters: churchLocation.radiusMeters,
      requiredDwellMinutes: requiredDwellMinutes,
      currentDwellSeconds: currentDwellSeconds,
    );
  }

  Future<void> markCurrentServicePresent(String churchId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Sign in again before marking attendance.');
    }

    final prompt = await getCurrentCheckInPrompt(churchId);
    if (prompt.alreadyMarked) return;
    if (!prompt.hasActiveService ||
        prompt.serviceId == null ||
        prompt.serviceName == null) {
      throw Exception(prompt.message);
    }
    if (!prompt.isInsideGeofence || !prompt.canMarkPresent) {
      throw Exception(prompt.message);
    }

    final activeService = await getActiveService(churchId);
    await _markPresent(
      user.id,
      churchId,
      prompt.serviceId!,
      activeService?['startTime'] as String?,
      prompt.serviceName,
      method: 'manual_geofence',
    );
  }

  Future<AttendanceCheckInPrompt> getManualOnSiteCheckInPrompt(
      String churchId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      return const AttendanceCheckInPrompt(
        hasActiveService: false,
        canMarkPresent: false,
        isInsideGeofence: false,
        alreadyMarked: false,
        message: 'Sign in again before marking attendance.',
      );
    }

    final activeService = await getActiveService(churchId);
    if (activeService == null) {
      return const AttendanceCheckInPrompt(
        hasActiveService: false,
        canMarkPresent: false,
        isInsideGeofence: false,
        alreadyMarked: false,
        message: 'Manual sign-in only opens during an active service.',
      );
    }

    final serviceId = activeService['id'] as String;
    final serviceName = activeService['name'] as String;
    if (await _hasAttendanceForToday(user.id, churchId, serviceId)) {
      return AttendanceCheckInPrompt(
        hasActiveService: true,
        canMarkPresent: false,
        isInsideGeofence: true,
        alreadyMarked: true,
        message: 'You are already marked for $serviceName.',
        serviceId: serviceId,
        serviceName: serviceName,
      );
    }

    final churchLocation = await _getChurchLocation(churchId);
    if (churchLocation == null) {
      return AttendanceCheckInPrompt(
        hasActiveService: true,
        canMarkPresent: false,
        isInsideGeofence: false,
        alreadyMarked: false,
        message: 'The pastor needs to set the church geofence first.',
        serviceId: serviceId,
        serviceName: serviceName,
      );
    }

    final permissionReady = await _ensureLocationPermission();
    if (!permissionReady) {
      return AttendanceCheckInPrompt(
        hasActiveService: true,
        canMarkPresent: false,
        isInsideGeofence: false,
        alreadyMarked: false,
        message: 'Location permission is needed to verify you are at church.',
        serviceId: serviceId,
        serviceName: serviceName,
      );
    }

    final position = await _getReliablePosition();
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      churchLocation.latitude,
      churchLocation.longitude,
    );
    final isInside = distance <= churchLocation.radiusMeters;
    if (isInside) {
      await _readOrStartDwellEntry(
        user.id,
        serviceId,
        observedAt: DateTime.now(),
      );
    } else {
      final accuracyBuffer = position.accuracy.clamp(25, 150).toDouble();
      await _recordOutsideObservation(
        user.id,
        serviceId,
        clearlyOutside: distance > churchLocation.radiusMeters + accuracyBuffer,
      );
    }

    return AttendanceCheckInPrompt(
      hasActiveService: true,
      canMarkPresent: isInside,
      isInsideGeofence: isInside,
      alreadyMarked: false,
      message: isInside
          ? 'Location confirmed at church for $serviceName.'
          : 'You are ${distance.toStringAsFixed(0)}m from church. Manual sign-in unlocks on property.',
      serviceId: serviceId,
      serviceName: serviceName,
      distanceMeters: distance,
      radiusMeters: churchLocation.radiusMeters,
      requiredDwellMinutes: 0,
      currentDwellSeconds: 0,
    );
  }

  Future<void> markManualOnSitePresent(String churchId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw Exception('Sign in again before marking attendance.');
    }

    final prompt = await getManualOnSiteCheckInPrompt(churchId);
    if (prompt.alreadyMarked) return;
    if (!prompt.hasActiveService ||
        prompt.serviceId == null ||
        prompt.serviceName == null) {
      throw Exception(prompt.message);
    }
    if (!prompt.canMarkPresent || !prompt.isInsideGeofence) {
      throw Exception(prompt.message);
    }

    final activeService = await getActiveService(churchId);
    // getManualOnSiteCheckInPrompt just called _readOrStartDwellEntry, which
    // returns the *first* time this person was ever verified on property for
    // this service (it never overwrites an existing session) -- not the
    // moment they happened to notice auto-detection hadn't fired and tapped
    // this button. A member who arrived on time and only manually signed in
    // because the automatic path silently failed must be graded on when they
    // actually arrived, not on when they gave up waiting and intervened.
    final arrivalTime = await _readOrStartDwellEntry(
      user.id,
      prompt.serviceId!,
      observedAt: DateTime.now(),
    );
    await _markPresent(
      user.id,
      churchId,
      prompt.serviceId!,
      activeService?['startTime'] as String?,
      prompt.serviceName,
      method: 'manual_geofence',
      checkedInAt: arrivalTime,
    );
  }

  Future<void> markRemotePresent({
    required String userId,
    required String churchId,
    required String reason,
    required String engagementAnswer,
    int? watchedMinutes,
  }) async {
    final activeService = await getActiveService(churchId);
    if (activeService == null) {
      throw Exception('Remote check-in only opens during an active service.');
    }
    final finalServiceId = activeService['id']! as String;
    final finalServiceName = activeService['name']! as String;

    // 2. Check if already marked present for this service. Continue into the
    // offline queue if only the read check is unavailable.
    if (await _hasAttendanceForToday(
      userId,
      churchId,
      finalServiceId,
      continueWhenOffline: true,
    )) {
      throw Exception('You have already checked in for this service.');
    }

    // 3. Create Record
    final record = AttendanceRecord(
      id: '',
      userId: userId,
      churchId: churchId,
      serviceId: finalServiceId,
      timestamp: DateTime.now(),
      method: 'remote',
      present: true,
      status: 'remote_verified',
      reasonForAbsence: reason,
      engagementAnswer: watchedMinutes == null
          ? engagementAnswer
          : '$engagementAnswer\nWatched in app: $watchedMinutes minutes',
      serviceName: finalServiceName,
    );

    // 4. Save
    await _insertAttendanceRecord(record);
    debugPrint('Marked remote present successfully');
  }

  Future<void> _insertAttendanceRecord(AttendanceRecord record) async {
    try {
      await _writeAttendanceRecord(record.toMap());
      unawaited(flushPendingAttendance());
    } catch (error) {
      if (_isDuplicateAttendanceError(error)) {
        _updateDebugStatus('Already marked present for today.');
        return;
      }
      if (!_isRetryableAttendanceWriteError(error)) {
        _updateDebugStatus(
            'Attendance could not be saved. Please refresh and try again.');
        debugPrint('Attendance insert rejected without queueing: $error');
        rethrow;
      }
      await _queueAttendanceRecord(record);
      _updateDebugStatus(
          'Attendance saved on this device and will sync when online.');
      debugPrint('Attendance queued for sync: $error');
    }
  }

  Future<void> _writeAttendanceRecord(Map<String, dynamic> record) async {
    try {
      await _supabase.rpc('record_my_attendance', params: {
        'p_church_id': record['church_id'],
        'p_service_id': record['service_id'],
        'p_timestamp': record['timestamp'],
        'p_method': record['method'],
        'p_present': record['present'],
        'p_status': record['status'],
        'p_minutes_late': record['minutes_late'],
        'p_reason_for_absence': record['reason_for_absence'],
        'p_engagement_answer': record['engagement_answer'],
        'p_service_name': record['service_name'],
      });
    } catch (error) {
      if (!_isMissingAttendanceRpcError(error)) rethrow;
      // Forward-compatible fallback while the app and database migration roll
      // out independently.
      await _supabase.from('attendance').insert(record);
    }
  }

  Future<void> _queueAttendanceRecord(AttendanceRecord record) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_pendingAttendanceQueueKey) ?? <String>[];
    final recordMap = record.toMap();
    final dedupeKey = _attendanceDedupeKey(recordMap);
    final withoutDuplicate = queue.where((encoded) {
      try {
        final item = jsonDecode(encoded);
        return item is! Map || _attendanceDedupeKey(item) != dedupeKey;
      } catch (_) {
        return false;
      }
    }).toList();
    withoutDuplicate.add(jsonEncode(recordMap));
    await prefs.setStringList(_pendingAttendanceQueueKey, withoutDuplicate);
  }

  Future<void> flushPendingAttendance() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_pendingAttendanceQueueKey) ?? <String>[];
    if (queue.isEmpty) return;

    final remaining = <String>[];
    for (final encoded in queue) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is! Map) continue;
        final record = Map<String, dynamic>.from(decoded);
        final exists = await _queuedAttendanceAlreadySynced(record);
        if (!exists) {
          await _writeAttendanceRecord(record);
        }
      } catch (error) {
        debugPrint('Pending attendance sync failed: $error');
        if (_isRetryableAttendanceWriteError(error) &&
            !_isDuplicateAttendanceError(error)) {
          remaining.add(encoded);
        }
      }
    }

    await prefs.setStringList(_pendingAttendanceQueueKey, remaining);
    if (remaining.isEmpty) {
      _updateDebugStatus('Pending attendance sync complete.');
    }
  }

  Future<bool> _queuedAttendanceAlreadySynced(
      Map<String, dynamic> record) async {
    final userId = record['user_id']?.toString() ?? '';
    final churchId = record['church_id']?.toString() ?? '';
    final serviceId = record['service_id']?.toString() ?? '';
    final timestamp = DateTime.tryParse(record['timestamp']?.toString() ?? '');
    if (userId.isEmpty ||
        churchId.isEmpty ||
        serviceId.isEmpty ||
        timestamp == null) {
      return false;
    }

    final dayStart = _jamaicaDayStartUtc(timestamp);
    final nextDayStart = dayStart.add(const Duration(days: 1));
    final rows = await _supabase
        .from('attendance')
        .select('id, present')
        .eq('user_id', userId)
        .eq('church_id', churchId)
        .eq('service_id', serviceId)
        .gte('timestamp', dayStart.toIso8601String())
        .lt('timestamp', nextDayStart.toIso8601String())
        .limit(5);
    return rows.any((row) => row['present'] == true);
  }

  String _attendanceDedupeKey(Map<dynamic, dynamic> record) {
    final timestamp = DateTime.tryParse(record['timestamp']?.toString() ?? '');
    final dateKey = timestamp == null
        ? _jamaicaDateKey(DateTime.now())
        : _jamaicaDateKey(timestamp);
    return [
      record['church_id'] ?? '',
      record['user_id'] ?? '',
      record['service_id'] ?? '',
      record['status'] ?? '',
      dateKey,
    ].join('|');
  }

  bool _isRetryableAttendanceWriteError(Object error) {
    final text = error.toString().toLowerCase();
    if (SupabaseResilience.isAuthSessionError(error)) return false;
    if (text.contains('permission') ||
        text.contains('row-level security') ||
        text.contains('rls') ||
        text.contains('duplicate') ||
        text.contains('violates') ||
        text.contains('invalid input') ||
        text.contains('not-null') ||
        text.contains('foreign key') ||
        text.contains('401') ||
        text.contains('403') ||
        text.contains('23505') ||
        text.contains('23502') ||
        text.contains('23503') ||
        text.contains('42501') ||
        text.contains('22p02')) {
      return false;
    }
    return text.contains('timeout') ||
        text.contains('timed out') ||
        text.contains('connection') ||
        text.contains('network') ||
        text.contains('socket') ||
        text.contains('failed host lookup') ||
        text.contains('software caused connection abort') ||
        text.contains('service unavailable') ||
        text.contains('bad gateway') ||
        text.contains('gateway timeout') ||
        text.contains('502') ||
        text.contains('503') ||
        text.contains('504');
  }

  bool _isMissingAttendanceRpcError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('record_my_attendance') &&
        (text.contains('pgrst202') ||
            text.contains('42883') ||
            text.contains('function') && text.contains('not found'));
  }

  bool _isDuplicateAttendanceError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('23505') ||
        text.contains('duplicate key') ||
        text.contains('attendance_one_record_per_member_service_day_idx');
  }

  Future<void> _showPostServiceNotification(String status) async {
    const androidDetails = AndroidNotificationDetails(
      'attendance_channel',
      'Attendance Updates',
      channelDescription: 'Notifications for automatic attendance tracking',
      importance: Importance.high,
      priority: Priority.high,
      icon: 'ic_stat_grace_connect',
      largeIcon: DrawableResourceAndroidBitmap('notification_large_icon'),
    );
    const iosDetails = DarwinNotificationDetails();
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);

    String body = 'You have been checked in.';
    if (status == 'late') {
      body = 'You have been checked in (Late). Better late than never!';
    } else {
      body = 'You have been checked in. How was the service?';
    }

    await _notificationsPlugin.show(
      0,
      'Marked Present! ✅',
      body,
      details,
    );
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<bool> _hasAttendanceForToday(
    String userId,
    String churchId,
    String serviceId, {
    bool continueWhenOffline = false,
    DateTime? forTimestamp,
  }) async {
    final attendanceAt = forTimestamp ?? DateTime.now();
    if (await _hasQueuedAttendanceForToday(
      userId,
      churchId,
      serviceId,
      forTimestamp: attendanceAt,
    )) {
      return true;
    }

    final todayStart = _jamaicaDayStartUtc(attendanceAt);
    final tomorrowStart = todayStart.add(const Duration(days: 1));

    try {
      final existingQuery = await _supabase
          .from('attendance')
          .select('id, present')
          .eq('user_id', userId)
          .eq('church_id', churchId)
          .eq('service_id', serviceId)
          .gte('timestamp', todayStart.toIso8601String())
          .lt('timestamp', tomorrowStart.toIso8601String())
          .limit(5);

      return existingQuery.any((row) => row['present'] == true);
    } catch (error) {
      if (continueWhenOffline && _isRetryableAttendanceWriteError(error)) {
        return false;
      }
      rethrow;
    }
  }

  Future<bool> _hasQueuedAttendanceForToday(
    String userId,
    String churchId,
    String serviceId, {
    DateTime? forTimestamp,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_pendingAttendanceQueueKey) ?? const [];
    final todayKey = _jamaicaDateKey(forTimestamp ?? DateTime.now());
    for (final encoded in queue) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is! Map) continue;
        final timestamp =
            DateTime.tryParse(decoded['timestamp']?.toString() ?? '');
        if (decoded['user_id']?.toString() == userId &&
            decoded['church_id']?.toString() == churchId &&
            decoded['service_id']?.toString() == serviceId &&
            decoded['present'] == true &&
            timestamp != null &&
            _jamaicaDateKey(timestamp) == todayKey) {
          return true;
        }
      } catch (_) {
        // A corrupt queue entry is discarded during the next flush.
      }
    }
    return false;
  }

  Future<bool> hasAttendanceForActiveService(
    String churchId, {
    String? userId,
  }) async {
    final activeService = await getActiveService(churchId);
    final serviceId = activeService?['id']?.toString();
    final effectiveUserId = userId ?? _supabase.auth.currentUser?.id;
    if (serviceId == null ||
        serviceId.isEmpty ||
        effectiveUserId == null ||
        effectiveUserId.isEmpty) {
      return false;
    }
    return _hasAttendanceForToday(effectiveUserId, churchId, serviceId);
  }

  Future<DateTime> _readOrStartDwellEntry(
    String userId,
    String serviceId, {
    required DateTime observedAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _dwellKey(userId, serviceId);
    final stored = prefs.getString(key);
    final parsed = AttendanceDwellSession.tryParse(
      stored,
      legacyObservedAt: observedAt,
    );
    final session = (parsed ??
            AttendanceDwellSession(
              startedAt: observedAt,
              lastInsideAt: observedAt,
            ))
        .observedInsideAt(observedAt);

    await prefs.setString(key, session.encode());
    _currentServiceId = serviceId;
    return session.startedAt;
  }

  Future<bool> _recordOutsideObservation(
    String userId,
    String serviceId, {
    required bool clearlyOutside,
    DateTime? observedAt,
  }) async {
    // Poor-accuracy readings near the radius are not proof that somebody left
    // church. Preserve the countdown until multiple reliable fixes establish
    // that they remained clearly outside.
    if (!clearlyOutside) return false;

    final prefs = await SharedPreferences.getInstance();
    final key = _dwellKey(userId, serviceId);
    final now = observedAt ?? DateTime.now();
    final session = AttendanceDwellSession.tryParse(
      prefs.getString(key),
      legacyObservedAt: now,
    );
    if (session == null) return true;
    if (!session.isValidAt(now)) {
      await prefs.remove(key);
      return true;
    }

    final observed = session.observedClearlyOutsideAt(
      now,
      maximumEvidenceGap: _maximumClearOutsideEvidenceGap,
    );
    if (observed.hasSustainedClearOutsideEvidence(
      _requiredClearOutsideDuration,
    )) {
      await prefs.remove(key);
      return true;
    }

    await prefs.setString(key, observed.encode());
    return false;
  }

  Future<void> _clearDwellEntry(String userId, String serviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dwellKey(userId, serviceId));
  }

  String _dwellKey(String userId, String serviceId) {
    final now = _jamaicaWallClock(DateTime.now());
    final dateKey = '${now.year}-${now.month}-${now.day}';
    return 'attendance_dwell_${userId}_${serviceId}_$dateKey';
  }

  Stream<List<AttendanceRecord>> getAttendanceHistory(String userId) async* {
    var lastGoodRecords = const <AttendanceRecord>[];

    while (true) {
      try {
        final records = await _fetchAttendanceHistory(userId);
        lastGoodRecords = records;
        yield records;
      } catch (error) {
        debugPrint('Attendance history refresh failed: $error');
        if (SupabaseResilience.isAuthSessionError(error) &&
            await SupabaseResilience.refreshSession(
              context: 'Attendance history',
            )) {
          try {
            final records = await _fetchAttendanceHistory(userId);
            lastGoodRecords = records;
            yield records;
            await Future<void>.delayed(const Duration(seconds: 45));
            continue;
          } catch (retryError) {
            debugPrint('Attendance history retry failed: $retryError');
          }
        }
        if (lastGoodRecords.isNotEmpty) {
          yield lastGoodRecords;
        } else {
          rethrow;
        }
      }

      await Future<void>.delayed(const Duration(seconds: 45));
    }
  }

  Future<List<AttendanceRecord>> _fetchAttendanceHistory(String userId) async {
    final rows = await _supabase
        .from('attendance')
        .select()
        .eq('user_id', userId)
        .order('timestamp', ascending: false);

    return rows
        .map<AttendanceRecord>((record) => AttendanceRecord.fromMap(record))
        .toList();
  }

  Future<AttendanceSetupStatus> getSetupStatus(String churchId) async {
    final prefs = await SharedPreferences.getInstance();
    final autoCheckInEnabled = prefs.getBool('auto_check_in') ?? false;
    final locationServicesEnabled = await Geolocator.isLocationServiceEnabled();
    final permission = await Geolocator.checkPermission();

    final churchLocation = await _getChurchLocation(churchId);

    bool hasSchedule = false;
    String? activeServiceName;
    try {
      final schedules = await _supabase
          .from('service_schedules')
          .select('serviceId')
          .eq('churchId', churchId)
          .limit(1);
      hasSchedule = schedules.isNotEmpty;

      final activeService = await getActiveService(churchId);
      activeServiceName = activeService?['name'];
    } catch (e) {
      debugPrint('Failed to inspect attendance schedule: $e');
    }

    bool? batteryOptimizationIgnored;
    if (_usesNativeAndroidGeofence) {
      try {
        batteryOptimizationIgnored =
            await NotificationService().isIgnoringBatteryOptimizations();
      } catch (e) {
        debugPrint('Could not read battery optimization status: $e');
      }
    }

    return AttendanceSetupStatus(
      autoCheckInEnabled: autoCheckInEnabled,
      locationServicesEnabled: locationServicesEnabled,
      permission: permission,
      hasChurchLocation: churchLocation != null,
      hasServiceSchedule: hasSchedule,
      requiresBackgroundLocation: _needsAlwaysLocationPermission,
      activeServiceName: activeServiceName,
      batteryOptimizationIgnored: batteryOptimizationIgnored,
    );
  }

  Future<void> saveChurchLocationFromCurrentPosition(
    String churchId, {
    double radiusMeters = 150,
  }) async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      throw Exception(
          'Location permission is required to set church location.');
    }

    final position = await _getReliablePosition();

    await saveChurchLocation(
      churchId: churchId,
      latitude: position.latitude,
      longitude: position.longitude,
      radiusMeters: radiusMeters,
    );
  }

  // Seeding Logic (Client-Side)
  Future<String> seedAttendanceData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return 'Error: Not logged in.';

    // 1. Get Church
    // We assume the user is an admin of *some* church, or we just pick the first one for testing.
    // For safety in this test app, let's pick the first church in the collection if the user isn't assigned one,
    // OR just use the user's assigned church if available.

    String churchId;
    String churchName = 'Test Church';

    final userChurchId = await _getCurrentUserChurchId(user.id);

    if (userChurchId != null) {
      churchId = userChurchId;
    } else {
      final churchesSnap = await _supabase.from('churches').select().limit(1);
      if (churchesSnap.isEmpty) return 'Error: No churches found in DB.';
      churchId = churchesSnap.first['id'];
      churchName = churchesSnap.first['name'] ?? 'Test Church';
    }

    // 2. Create Location
    final matchLocation = {
      'churchId': churchId,
      'latitude': 18.0179, // Kingston
      'longitude': -76.8099,
      'radiusMeters': 200.0,
      'placeId': churchId,
      'timezone': 'America/Jamaica',
      'address': 'Kingston, Jamaica'
    };

    await _supabase.from('church_locations').upsert(matchLocation);

    // 3. Create Schedule (Daily 6am - 10pm)
    final List<Map<String, dynamic>> schedules = [];
    for (int day = 1; day <= 7; day++) {
      final serviceId = 'svc_${churchId}_$day';
      final schedule = ServiceSchedule(
          serviceId: serviceId,
          churchId: churchId,
          name: 'Daily Test Service',
          dayOfWeek: day,
          startTime: '06:00',
          endTime: '22:00');
      schedules.add(schedule.toMap());
    }
    await _supabase.from('service_schedules').upsert(schedules);

    return 'Success! Created location & schedules for $churchName.\nPlace ID: $churchId';
  }

  void _clearMonitoringState({required bool resetRestartAttempts}) {
    _positionStreamSubscription?.cancel();
    _activeServicePollTimer?.cancel();
    _monitoringRestartTimer?.cancel();
    _positionStreamSubscription = null;
    _activeServicePollTimer = null;
    _monitoringRestartTimer = null;
    _isPollingLocation = false;
    _isProcessingLocation = false;
    _currentServiceId = null;
    if (resetRestartAttempts) _monitoringRestartAttempts = 0;
    _setMonitoring(false);
  }

  void stopMonitoring() {
    _monitoringRequested = false;
    _clearMonitoringState(resetRestartAttempts: true);
    if (_usesNativeAndroidGeofence) {
      unawaited(_removeAndroidNativeGeofence());
    }
    _updateDebugStatus('Monitoring stopped');
  }

  void _startPendingAttendanceSync() {
    _connectivitySubscription ??=
        Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection =
          results.any((result) => result != ConnectivityResult.none);
      if (hasConnection) unawaited(flushPendingAttendance());
    });
  }
}
