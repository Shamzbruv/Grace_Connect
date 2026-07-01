import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/church_location.dart';
import '../models/service_schedule.dart';
import '../models/attendance_record.dart';
import 'supabase_resilience.dart';

class AttendanceSetupStatus {
  final bool autoCheckInEnabled;
  final bool locationServicesEnabled;
  final LocationPermission permission;
  final bool hasChurchLocation;
  final bool hasServiceSchedule;
  final String? activeServiceName;

  const AttendanceSetupStatus({
    required this.autoCheckInEnabled,
    required this.locationServicesEnabled,
    required this.permission,
    required this.hasChurchLocation,
    required this.hasServiceSchedule,
    this.activeServiceName,
  });

  bool get hasLocationPermission =>
      permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;

  bool get canMonitor =>
      autoCheckInEnabled &&
      locationServicesEnabled &&
      hasLocationPermission &&
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
    }
    if (!hasChurchLocation) missing.add('Church geofence location is not set.');
    if (!hasServiceSchedule) missing.add('No service schedule is configured.');
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
    this.currentDwellMinutes = 0,
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
  final int currentDwellMinutes;

  int get remainingDwellMinutes =>
      (requiredDwellMinutes - currentDwellMinutes).clamp(0, 999).toInt();
}

class AttendanceService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _activeServicePollTimer;
  DateTime? _entryTime;
  String? _currentServiceId;
  bool _isMonitoring = false;
  bool _isPollingLocation = false;
  String _lastDebugStatus = 'Auto-attendance has not started yet.';
  static const String _pendingAttendanceQueueKey =
      'pending_attendance_records_v1';

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

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final autoCheckInEnabled = prefs.getBool('auto_check_in') ?? false;
    _startPendingAttendanceSync();
    unawaited(flushPendingAttendance());
    if (!autoCheckInEnabled) {
      stopMonitoring();
      _updateDebugStatus('Auto check-in disabled in settings.');
      return;
    }

    // Prevent duplicate listeners
    stopMonitoring();

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _setMonitoring(false);
      _updateDebugStatus('Device location services are turned off.');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

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

    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      _startMonitoring();
    }
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

  void _startMonitoring() {
    _setMonitoring(true);
    _updateDebugStatus('Starting monitoring...');
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20, // Check every 20 meters
    );

    _positionStreamSubscription =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
            (Position position) async {
      try {
        await _checkLocationLogic(position);
      } catch (e) {
        debugPrint('Auto-attendance check failed: $e');
        _updateDebugStatus('Auto-attendance check failed: $e');
      }
    }, onError: (e) {
      debugPrint('Location stream error: $e');
      _setMonitoring(false);
      _updateDebugStatus('Error: $e');
    });

    unawaited(_pollCurrentLocationForAttendance());
    _activeServicePollTimer?.cancel();
    _activeServicePollTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_pollCurrentLocationForAttendance()),
    );
  }

  Future<void> _pollCurrentLocationForAttendance() async {
    if (_isPollingLocation || !_isMonitoring) return;

    _isPollingLocation = true;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
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
    final user = _supabase.auth.currentUser;
    if (user == null) {
      _updateDebugStatus('User not logged in');
      return;
    }

    // 1. Fetch User's Church Location
    // We get placeId from Firestore 'users' collection for now, as that's where church assignment might be living.
    final userDoc = await _supabase
        .from('users')
        .select('placeId')
        .eq('uid', user.id)
        .maybeSingle();
    final placeId = userDoc?['placeId']?.toString();
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
      // Outside Geofence
      _updateDebugStatus(
          'Outside Geofence (${distanceInMeters.toStringAsFixed(1)}m)');
      _entryTime = null;
      _currentServiceId = null;
    }
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
  }

  /// Returns the currently active recurring service for the given church.
  Future<Map<String, dynamic>?> getActiveService(String churchId) async {
    final now = DateTime.now();
    final servicesSnapshot = await _supabase
        .from('service_schedules')
        .select()
        .eq('churchId', churchId)
        .eq('dayOfWeek', now.weekday)
        .eq('attendanceEnabled', true);

    for (var doc in servicesSnapshot) {
      final schedule = ServiceSchedule.fromMap(doc);
      if (_isTimeWithinSchedule(now, schedule)) {
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
      _entryTime = null;
      _updateDebugStatus('Inside, but no active service.');
      return;
    }

    final activeServiceId = activeService['id']!;
    final activeServiceStartTime = activeService['startTime']!;
    final activeServiceName = activeService['name']!;
    final requiredDwellMinutes =
        activeService['minimumDwellMinutes'] as int? ?? 10;

    // 4. Dwell Logic
    if (_entryTime == null) {
      _entryTime = DateTime.now();
      _currentServiceId = activeServiceId;
      _updateDebugStatus('Entered zone. Waiting for dwell...');
      await _saveDwellEntry(userId, activeServiceId, _entryTime!);
      debugPrint('Entered church geofence for service: $activeServiceId');
    } else if (_currentServiceId == activeServiceId) {
      final dwellDuration = DateTime.now().difference(_entryTime!);
      _updateDebugStatus(
          'Dwelling: ${dwellDuration.inMinutes}m / ${requiredDwellMinutes}m');
      if (dwellDuration.inMinutes >= requiredDwellMinutes) {
        // 5. Mark Present
        _updateDebugStatus('Marking present...');
        await _markPresent(userId, churchId, activeServiceId,
            activeServiceStartTime, activeServiceName,
            detectedAt: _entryTime);
      }
    } else {
      // Service changed while inside? Reset
      _entryTime = DateTime.now();
      _currentServiceId = activeServiceId;
      await _saveDwellEntry(userId, activeServiceId, _entryTime!);
      _updateDebugStatus('Service changed. Resetting dwell.');
    }
  }

  bool _isTimeWithinSchedule(DateTime now, ServiceSchedule schedule) {
    final startParts = _parseTimeParts(schedule.startTime);
    final endParts = _parseTimeParts(schedule.endTime);
    if (startParts == null || endParts == null) {
      _updateDebugStatus('A service schedule has an invalid time format.');
      return false;
    }

    final startTime =
        DateTime(now.year, now.month, now.day, startParts[0], startParts[1]);
    final endTime =
        DateTime(now.year, now.month, now.day, endParts[0], endParts[1]);

    final validStart = startTime.subtract(
      Duration(minutes: schedule.checkInOpensMinutesBefore),
    );
    final validEnd = endTime.add(
      Duration(minutes: schedule.checkInClosesMinutesAfter),
    );

    return now.isAfter(validStart) && now.isBefore(validEnd);
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

  Future<void> _markPresent(
    String userId,
    String churchId,
    String serviceId,
    String? serviceStartTime,
    String? serviceName, {
    String method = 'auto_geofence',
    DateTime? detectedAt,
  }) async {
    // Check duplication
    final todayStart =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    final existingQuery = await _supabase
        .from('attendance')
        .select('id')
        .eq('user_id', userId)
        .eq('service_id', serviceId)
        .gte('timestamp', todayStart.toIso8601String())
        .limit(1);

    if ((existingQuery as List).isNotEmpty) {
      _updateDebugStatus('Already marked present for today.');
      return;
    }

    // Calculate Late Status
    String status = 'on_time';
    int? minutesLate;

    if (serviceStartTime != null) {
      final now = detectedAt ?? DateTime.now();
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
      timestamp: DateTime.now(),
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

    if (await _hasAttendanceForToday(user.id, serviceId)) {
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

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      churchLocation.latitude,
      churchLocation.longitude,
    );
    final isInside = distance <= churchLocation.radiusMeters;

    if (!isInside) {
      await _clearDwellEntry(user.id, serviceId);
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

    final entryTime = await _readOrStartDwellEntry(user.id, serviceId);
    final currentDwell = DateTime.now().difference(entryTime).inMinutes;
    final canMarkPresent = currentDwell >= requiredDwellMinutes;

    return AttendanceCheckInPrompt(
      hasActiveService: true,
      canMarkPresent: canMarkPresent,
      isInsideGeofence: true,
      alreadyMarked: false,
      message: canMarkPresent
          ? 'You are verified on-site for $serviceName.'
          : 'Stay on property for ${requiredDwellMinutes - currentDwell} more minute(s) to unlock check-in.',
      serviceId: serviceId,
      serviceName: serviceName,
      distanceMeters: distance,
      radiusMeters: churchLocation.radiusMeters,
      requiredDwellMinutes: requiredDwellMinutes,
      currentDwellMinutes: currentDwell,
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
    final detectedAt = await _readDwellEntry(user.id, prompt.serviceId!);
    await _markPresent(
      user.id,
      churchId,
      prompt.serviceId!,
      activeService?['startTime'] as String?,
      prompt.serviceName,
      method: 'manual_geofence',
      detectedAt: detectedAt,
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
    if (await _hasAttendanceForToday(user.id, serviceId)) {
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

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
    final distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      churchLocation.latitude,
      churchLocation.longitude,
    );
    final isInside = distance <= churchLocation.radiusMeters;
    if (isInside) {
      await _readOrStartDwellEntry(user.id, serviceId);
    } else {
      await _clearDwellEntry(user.id, serviceId);
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
      currentDwellMinutes: isInside ? 0 : 0,
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
    final detectedAt = await _readDwellEntry(user.id, prompt.serviceId!);
    await _markPresent(
      user.id,
      churchId,
      prompt.serviceId!,
      activeService?['startTime'] as String?,
      prompt.serviceName,
      method: 'manual_geofence',
      detectedAt: detectedAt,
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

    // 2. Check if already marked present for this service (or today broadly if ad-hoc)
    final todayStart =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    final existingQuery = await _supabase
        .from('attendance')
        .select('id')
        .eq('user_id', userId)
        .eq('service_id', finalServiceId)
        .gte('timestamp', todayStart.toIso8601String())
        .limit(1);

    if ((existingQuery as List).isNotEmpty) {
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
      await _supabase.from('attendance').insert(record.toMap());
      unawaited(flushPendingAttendance());
    } catch (error) {
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
          await _supabase.from('attendance').insert(record);
        }
      } catch (error) {
        debugPrint('Pending attendance sync failed: $error');
        if (_isRetryableAttendanceWriteError(error)) {
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
    final serviceId = record['service_id']?.toString() ?? '';
    final timestamp = DateTime.tryParse(record['timestamp']?.toString() ?? '');
    if (userId.isEmpty || serviceId.isEmpty || timestamp == null) return false;

    final dayStart = DateTime(timestamp.year, timestamp.month, timestamp.day);
    final rows = await _supabase
        .from('attendance')
        .select('id')
        .eq('user_id', userId)
        .eq('service_id', serviceId)
        .gte('timestamp', dayStart.toIso8601String())
        .limit(1);
    return rows.isNotEmpty;
  }

  String _attendanceDedupeKey(Map<dynamic, dynamic> record) {
    final timestamp = DateTime.tryParse(record['timestamp']?.toString() ?? '');
    final dateKey = timestamp == null
        ? DateTime.now().toIso8601String().substring(0, 10)
        : timestamp.toIso8601String().substring(0, 10);
    return [
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

  Future<bool> _hasAttendanceForToday(String userId, String serviceId) async {
    final todayStart =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

    final existingQuery = await _supabase
        .from('attendance')
        .select('id')
        .eq('user_id', userId)
        .eq('service_id', serviceId)
        .gte('timestamp', todayStart.toIso8601String())
        .limit(1);

    return (existingQuery as List).isNotEmpty;
  }

  Future<DateTime> _readOrStartDwellEntry(
      String userId, String serviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _dwellKey(userId, serviceId);
    final stored = prefs.getString(key);
    final parsed = stored == null ? null : DateTime.tryParse(stored);
    if (parsed != null) return parsed;

    final now = DateTime.now();
    await prefs.setString(key, now.toIso8601String());
    _entryTime = now;
    _currentServiceId = serviceId;
    return now;
  }

  Future<DateTime?> _readDwellEntry(String userId, String serviceId) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_dwellKey(userId, serviceId));
    return stored == null ? null : DateTime.tryParse(stored);
  }

  Future<void> _saveDwellEntry(
      String userId, String serviceId, DateTime entryTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _dwellKey(userId, serviceId), entryTime.toIso8601String());
  }

  Future<void> _clearDwellEntry(String userId, String serviceId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_dwellKey(userId, serviceId));
  }

  String _dwellKey(String userId, String serviceId) {
    final now = DateTime.now();
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

    return AttendanceSetupStatus(
      autoCheckInEnabled: autoCheckInEnabled,
      locationServicesEnabled: locationServicesEnabled,
      permission: permission,
      hasChurchLocation: churchLocation != null,
      hasServiceSchedule: hasSchedule,
      activeServiceName: activeServiceName,
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

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

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

    final userDoc = await _supabase
        .from('users')
        .select('placeId')
        .eq('uid', user.id)
        .maybeSingle();
    final userChurchId = userDoc?['placeId']?.toString();

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

  void stopMonitoring() {
    _positionStreamSubscription?.cancel();
    _activeServicePollTimer?.cancel();
    _positionStreamSubscription = null;
    _activeServicePollTimer = null;
    _isPollingLocation = false;
    _entryTime = null;
    _currentServiceId = null;
    _setMonitoring(false);
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
