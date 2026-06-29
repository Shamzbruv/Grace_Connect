import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/attendance_service.dart';
import '../../models/attendance_record.dart';
import '../../widgets/ui/app_card.dart';

import '../../widgets/ui/app_loader.dart';
import 'church_location_picker_screen.dart';
import 'remote_attendance_screen.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  String _filter = 'All';
  bool _autoCheckIn = true;
  bool _showDiagnostics = false;
  bool _isSetupLoading = false;
  bool _isPromptLoading = false;
  bool _isMarkingPresent = false;
  String? _loadedChurchId;
  String? _attendanceStreamUserId;
  Stream<List<AttendanceRecord>>? _attendanceHistoryStream;
  AttendanceSetupStatus? _setupStatus;
  AttendanceCheckInPrompt? _checkInPrompt;
  Timer? _promptRefreshTimer;

  @override
  void initState() {
    super.initState();
    _loadAutoCheckInPreference();
    _promptRefreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      final churchId = _loadedChurchId;
      if (churchId == null || !mounted || _isPromptLoading) return;
      unawaited(_refreshCheckInPrompt(churchId));
    });
  }

  @override
  void dispose() {
    _promptRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadAutoCheckInPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('auto_check_in') ?? false;
    if (!mounted) return;
    setState(() => _autoCheckIn = enabled);
    if (enabled && !kIsWeb) {
      await _attendanceService.initialize();
    }
  }

  Future<void> _toggleAutoCheckIn(bool value) async {
    setState(() => _autoCheckIn = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_check_in', value);

    if (value && !kIsWeb) {
      await _attendanceService.initialize();
    } else {
      _attendanceService.stopMonitoring();
    }

    final churchId = _loadedChurchId;
    if (churchId != null) {
      await _refreshSetupStatus(churchId);
    }
  }

  void _queueSetupRefresh(String churchId) {
    if (_loadedChurchId == churchId || _isSetupLoading) return;
    _loadedChurchId = churchId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _refreshSetupStatus(churchId);
      if (mounted) await _refreshCheckInPrompt(churchId);
    });
  }

  Future<void> _refreshSetupStatus(String churchId) async {
    setState(() => _isSetupLoading = true);
    try {
      final status = await _attendanceService.getSetupStatus(churchId);
      if (mounted) setState(() => _setupStatus = status);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not check attendance setup: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSetupLoading = false);
    }
  }

  Future<void> _refreshCheckInPrompt(String churchId) async {
    setState(() => _isPromptLoading = true);
    try {
      final prompt = await _attendanceService.getCurrentCheckInPrompt(churchId);
      if (mounted) setState(() => _checkInPrompt = prompt);
    } catch (e) {
      debugPrint('Could not check active service: $e');
      if (!mounted) return;
      setState(() {
        _checkInPrompt = const AttendanceCheckInPrompt(
          hasActiveService: false,
          canMarkPresent: false,
          isInsideGeofence: false,
          alreadyMarked: false,
          message:
              'Could not reach attendance right now. Tap Recheck and make sure your connection is active.',
        );
      });
    } finally {
      if (mounted) setState(() => _isPromptLoading = false);
    }
  }

  Future<void> _markPresentForActiveService(String churchId) async {
    setState(() => _isMarkingPresent = true);
    try {
      await _attendanceService.markManualOnSitePresent(churchId);
      await _refreshCheckInPrompt(churchId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manual sign-in marked present.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not mark attendance: $e')),
      );
      await _refreshCheckInPrompt(churchId);
    } finally {
      if (mounted) setState(() => _isMarkingPresent = false);
    }
  }

  bool _canManageAttendanceSetup(UserProfile user) {
    if (user.capabilities.canManageSchedules ||
        user.capabilities.canManageMembersBasic) {
      return true;
    }

    const allowedRoles = {
      'pastor',
      'senior_pastor',
      'assistant_pastor',
      'acting_pastor',
      'admin',
      'church_admin',
      'administrator',
      'secretary',
      'church_secretary',
      'head_usher',
      'attendance_scanner',
    };

    return user.roles
        .map((role) => role
            .trim()
            .toLowerCase()
            .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
            .replaceAll(RegExp(r'_+'), '_')
            .replaceAll(RegExp(r'^_|_$'), ''))
        .any(allowedRoles.contains);
  }

  Stream<List<AttendanceRecord>> _historyStream(String userId) {
    if (_attendanceStreamUserId != userId || _attendanceHistoryStream == null) {
      _attendanceStreamUserId = userId;
      _attendanceHistoryStream =
          _attendanceService.getAttendanceHistory(userId);
    }
    return _attendanceHistoryStream!;
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserRoleProvider>(context).user;
    if (user == null) return const AppLoader();
    _queueSetupRefresh(user.churchId);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Attendance History',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_canManageAttendanceSetup(user))
            IconButton(
              tooltip: 'Service Schedules',
              onPressed: () =>
                  Navigator.pushNamed(context, '/schedule_management'),
              icon: const Icon(Icons.event_available_outlined),
            ),
          TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const RemoteAttendanceScreen()),
              );
            },
            icon: const Icon(Icons.wifi_tethering, color: Colors.indigo),
            label: Text('Remote Check-In',
                style: GoogleFonts.poppins(
                    color: Colors.indigo, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<AttendanceRecord>>(
        stream: _historyStream(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoader();
          }

          if (snapshot.hasError) {
            return _buildAttendanceLoadError(context, user.churchId);
          }

          final records = snapshot.data ?? [];
          final filteredRecords = _filterRecords(records);
          final stats = _calculateStats(filteredRecords);

          return RefreshIndicator(
            onRefresh: () async {
              await _refreshSetupStatus(user.churchId);
              await _refreshCheckInPrompt(user.churchId);
            },
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                _buildActiveServiceCard(context, user),
                const SizedBox(height: 16),
                _buildGpsStatusCard(context, user),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                        child: _buildStatCard(context, 'Present',
                            stats['present']!, Colors.green)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _buildStatCard(
                            context, 'Late', stats['late']!, Colors.orange)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: _buildStatCard(
                            context, 'Absent', stats['absent']!, Colors.red)),
                  ],
                ),
                const SizedBox(height: 16),
                _buildAttendanceAnalysis(context, filteredRecords, stats),
                const SizedBox(height: 16),
                _buildAttendanceCalendar(context, filteredRecords),
                const SizedBox(height: 20),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', 'This Week', 'This Month', 'This Year']
                        .map((filter) {
                      final isSelected = _filter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          label: Text(filter),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) setState(() => _filter = filter);
                          },
                          backgroundColor: Theme.of(context).cardColor,
                          selectedColor: Theme.of(context).colorScheme.primary,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? Theme.of(context).colorScheme.onPrimary
                                : Theme.of(context).textTheme.bodyMedium?.color,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                if (filteredRecords.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_toggle_off,
                            size: 48,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.2)),
                        const SizedBox(height: 16),
                        Text('No attendance records found.',
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  )
                else
                  ...filteredRecords.map(
                    (record) => _buildRecordCard(context, record),
                  ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAttendanceLoadError(BuildContext context, String churchId) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.wifi_off_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'Attendance could not load right now.',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again. Your existing records will reappear as soon as Grace Connect reconnects.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () {
                setState(() => _attendanceHistoryStream = null);
                unawaited(_refreshSetupStatus(churchId));
                unawaited(_refreshCheckInPrompt(churchId));
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGpsStatusCard(BuildContext context, UserProfile user) {
    return StreamBuilder<bool>(
        stream: _attendanceService.isMonitoringStream,
        initialData: _attendanceService.isMonitoring,
        builder: (context, snapshot) {
          final isMonitoring = snapshot.data ?? false;
          final status = _setupStatus;
          final canManageSetup = _canManageAttendanceSetup(user);
          final blockers = status?.blockers ?? const <String>[];
          return AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on,
                            color: isMonitoring ? Colors.green : Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          'Auto-Attendance',
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                      ],
                    ),
                    Switch(
                      value: _autoCheckIn,
                      onChanged: _toggleAutoCheckIn,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _autoCheckIn
                      ? (isMonitoring
                          ? 'Monitoring your location for church arrival.'
                          : blockers.isNotEmpty
                              ? blockers.first
                              : _attendanceService.lastDebugStatus)
                      : 'Auto-attendance is turned off.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_isSetupLoading) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(minHeight: 2),
                ],
                if (status != null) ...[
                  const SizedBox(height: 14),
                  _buildSetupRow(
                    context,
                    label: 'Location permission',
                    isReady: status.hasLocationPermission,
                  ),
                  _buildSetupRow(
                    context,
                    label: 'Device location services',
                    isReady: status.locationServicesEnabled,
                  ),
                  _buildSetupRow(
                    context,
                    label: 'Church geofence',
                    isReady: status.hasChurchLocation,
                  ),
                  _buildSetupRow(
                    context,
                    label: 'Service schedule',
                    isReady: status.hasServiceSchedule,
                  ),
                  if (status.activeServiceName != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Active now: ${status.activeServiceName}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        await _refreshSetupStatus(user.churchId);
                        if (context.mounted) {
                          await _refreshCheckInPrompt(user.churchId);
                        }
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Recheck'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() => _showDiagnostics = !_showDiagnostics);
                      },
                      icon: const Icon(Icons.terminal),
                      label:
                          Text(_showDiagnostics ? 'Hide Details' : 'Details'),
                    ),
                    if (canManageSetup)
                      FilledButton.icon(
                        onPressed: () async {
                          final updated = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  const ChurchLocationPickerScreen(),
                            ),
                          );
                          if (updated == true && context.mounted) {
                            await _refreshSetupStatus(user.churchId);
                            await _refreshCheckInPrompt(user.churchId);
                          }
                        },
                        icon: const Icon(Icons.add_location_alt_outlined),
                        label: const Text('Pin Location'),
                      ),
                    if (canManageSetup)
                      OutlinedButton.icon(
                        onPressed: () => Navigator.pushNamed(
                            context, '/schedule_management'),
                        icon: const Icon(Icons.event_available),
                        label: const Text('Schedules'),
                      ),
                  ],
                ),
                if (_showDiagnostics) ...[
                  const Divider(height: 24),
                  Text(
                    'Diagnostics',
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 100,
                    child: StreamBuilder<String>(
                      stream: _attendanceService.debugStatusStream,
                      initialData: _attendanceService.lastDebugStatus,
                      builder: (context, debugSnapshot) {
                        return SingleChildScrollView(
                          reverse: true,
                          child: Text(
                            debugSnapshot.data ?? 'Waiting for GPS update...',
                            style: const TextStyle(
                              fontFamily: 'Courier',
                              fontSize: 12,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!isMonitoring && _autoCheckIn)
                    TextButton(
                      onPressed: () => _attendanceService.initialize(),
                      child: const Text('Force Resume Monitoring'),
                    ),
                ],
              ],
            ),
          );
        });
  }

  Widget _buildActiveServiceCard(BuildContext context, UserProfile user) {
    final theme = Theme.of(context);
    final prompt = _checkInPrompt;
    final serviceName = prompt?.serviceName ?? 'Current Service';
    final hasActive = prompt?.hasActiveService == true;
    final isVerified = prompt?.alreadyMarked == true;
    final isInside = prompt?.isInsideGeofence == true;
    final canMark = hasActive && !isVerified && !_isMarkingPresent;

    return AppCard(
      color: hasActive
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.18)
          : null,
      border: Border.all(
        color: hasActive
            ? theme.colorScheme.primary.withValues(alpha: 0.35)
            : theme.dividerColor.withValues(alpha: 0.14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasActive ? Icons.church_outlined : Icons.event_busy_outlined,
                color: hasActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasActive ? serviceName : 'No Service In Session',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ),
              if (_isPromptLoading)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            hasActive
                ? (prompt?.message ??
                    'Checking active service and church location...')
                : (prompt?.message ??
                    'No recurring service is in session right now.'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (prompt != null && hasActive) ...[
            const SizedBox(height: 12),
            _buildCheckInStep(
              context,
              label: 'Service in session',
              isComplete: true,
            ),
            _buildCheckInStep(
              context,
              label: 'Inside church radius',
              isComplete: isInside,
            ),
            const SizedBox(height: 8),
            Text(
              isVerified
                  ? 'Present recorded for today.'
                  : isInside
                      ? 'Location is inside the church radius. Tap Manual Sign-In to mark present.'
                      : 'Tap Manual Sign-In to request location access and confirm you are at church.',
              style: theme.textTheme.labelMedium,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: canMark
                      ? () => _markPresentForActiveService(user.churchId)
                      : null,
                  icon: _isMarkingPresent
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.how_to_reg_outlined),
                  label:
                      Text(isVerified ? 'Already Present' : 'Manual Sign-In'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Join live or remote service',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RemoteAttendanceScreen(),
                  ),
                ),
                icon: const Icon(Icons.wifi_tethering),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Refresh',
                onPressed: _isPromptLoading
                    ? null
                    : () => _refreshCheckInPrompt(user.churchId),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCheckInStep(
    BuildContext context, {
    required String label,
    required bool isComplete,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            isComplete ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 18,
            color: isComplete ? Colors.green : theme.colorScheme.outline,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isComplete
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: isComplete ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceAnalysis(
    BuildContext context,
    List<AttendanceRecord> records,
    Map<String, int> stats,
  ) {
    final theme = Theme.of(context);
    final remote = records.where((record) => record.method == 'remote').length;
    final lateRecords = records
        .where(
            (record) => record.status == 'late' && record.minutesLate != null)
        .toList();
    final avgLate = lateRecords.isEmpty
        ? 0
        : (lateRecords.fold<int>(
                    0, (total, record) => total + (record.minutesLate ?? 0)) /
                lateRecords.length)
            .round();
    final attendedServices = records
        .where((record) => record.present)
        .map((record) => record.serviceName?.trim())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toSet()
        .take(3)
        .join(', ');

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                'Attendance Analysis',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildAnalysisPill(
                  context, '${stats['present'] ?? 0}', 'present'),
              _buildAnalysisPill(context, '$remote', 'remote'),
              _buildAnalysisPill(context, '$avgLate min', 'avg late'),
              _buildAnalysisPill(
                context,
                '${stats['absent'] ?? 0}',
                'absent',
              ),
            ],
          ),
          if (attendedServices.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Services attended: $attendedServices',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnalysisPill(BuildContext context, String value, String label) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(20),
      ),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.labelMedium,
          children: [
            TextSpan(
              text: value,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
            TextSpan(text: ' $label'),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceCalendar(
    BuildContext context,
    List<AttendanceRecord> records,
  ) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final leadingSlots = firstDay.weekday % 7;
    final byDay = <int, AttendanceRecord>{};
    for (final record in records) {
      if (record.timestamp.year == now.year &&
          record.timestamp.month == now.month) {
        byDay[record.timestamp.day] = record;
      }
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_outlined,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(now),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                'Calendar View',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: const [
              _WeekdayLabel('S'),
              _WeekdayLabel('M'),
              _WeekdayLabel('T'),
              _WeekdayLabel('W'),
              _WeekdayLabel('T'),
              _WeekdayLabel('F'),
              _WeekdayLabel('S'),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: leadingSlots + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemBuilder: (context, index) {
              if (index < leadingSlots) return const SizedBox.shrink();
              final day = index - leadingSlots + 1;
              final record = byDay[day];
              final color = record == null
                  ? theme.colorScheme.surfaceContainerHighest
                  : _colorForRecord(record);
              final isToday = day == now.day;

              return Tooltip(
                message: record == null
                    ? 'No record'
                    : '${record.serviceName ?? 'Service'} - ${_labelForRecord(record)}',
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color:
                        color.withValues(alpha: record == null ? 0.35 : 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isToday
                          ? theme.colorScheme.primary
                          : color.withValues(
                              alpha: record == null ? 0.18 : 0.7),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$day',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: record == null
                            ? theme.colorScheme.onSurfaceVariant
                            : color,
                        fontWeight:
                            record == null ? FontWeight.w500 : FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _buildLegend(context, Colors.green, 'On time'),
              _buildLegend(context, Colors.orange, 'Late'),
              _buildLegend(context, Colors.purple, 'Remote'),
              _buildLegend(context, Colors.redAccent, 'Absent'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }

  Widget _buildSetupRow(
    BuildContext context, {
    required String label,
    required bool isReady,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(
            isReady ? Icons.check_circle : Icons.error_outline,
            size: 18,
            color: isReady ? Colors.green : Colors.orange,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
      BuildContext context, String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          )
        ],
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        children: [
          Text(
            value.toString(),
            style: GoogleFonts.poppins(
                fontSize: 24, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            label,
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCard(BuildContext context, AttendanceRecord record) {
    final isLate = record.status == 'late';
    final isRemote = record.method == 'remote';
    final isAbsent = !record.present || record.status == 'absent';
    final dateStr = DateFormat('MMM d, yyyy').format(record.timestamp);
    final timeStr = DateFormat('h:mm a').format(record.timestamp);

    Color statusColor;
    IconData statusIcon;
    Widget statusChip;

    if (isAbsent) {
      statusColor = Colors.redAccent;
      statusIcon = Icons.event_busy_outlined;
      statusChip = Chip(
        label: const Text('Absent', style: TextStyle(fontSize: 10)),
        backgroundColor: Colors.redAccent.withValues(alpha: 0.12),
        labelStyle: const TextStyle(color: Colors.redAccent),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      );
    } else if (isRemote) {
      statusColor = Colors.purple;
      statusIcon = Icons.wifi;
      statusChip = Chip(
        label: const Text('Remote', style: TextStyle(fontSize: 10)),
        backgroundColor: Colors.purple.withValues(alpha: 0.1),
        labelStyle: const TextStyle(color: Colors.purple),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      );
    } else if (isLate) {
      statusColor = Colors.orange;
      statusIcon = Icons.access_time;
      statusChip = Chip(
        label: Text('${record.minutesLate ?? "?"} min late',
            style: const TextStyle(fontSize: 10)),
        backgroundColor: Colors.orange.withValues(alpha: 0.2),
        labelStyle: const TextStyle(color: Colors.orange),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      );
    } else {
      statusColor = Colors.green;
      statusIcon = Icons.check;
      statusChip = const Chip(
        label: Text('On Time', style: TextStyle(fontSize: 10)),
        backgroundColor: Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: Colors.green)),
        labelStyle: TextStyle(color: Colors.green),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            statusIcon,
            color: statusColor,
            size: 20,
          ),
        ),
        title: Text(
          record.serviceName?.trim().isNotEmpty == true
              ? record.serviceName!
              : dateStr,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (record.serviceName?.trim().isNotEmpty == true) Text(dateStr),
            Text(isAbsent
                ? 'Marked absent at $timeStr'
                : 'Checked in at $timeStr'),
            if (isRemote && record.reasonForAbsence != null)
              Text(
                'Reason: ${record.reasonForAbsence}',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic),
              ),
          ],
        ),
        trailing: statusChip,
      ),
    );
  }

  List<AttendanceRecord> _filterRecords(List<AttendanceRecord> records) {
    final now = DateTime.now();
    if (_filter == 'This Week') {
      final startOfWeek = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      return records.where((r) => !r.timestamp.isBefore(startOfWeek)).toList();
    } else if (_filter == 'This Month') {
      return records
          .where((r) =>
              r.timestamp.month == now.month && r.timestamp.year == now.year)
          .toList();
    } else if (_filter == 'This Year') {
      return records.where((r) => r.timestamp.year == now.year).toList();
    }
    return records;
  }

  Map<String, int> _calculateStats(List<AttendanceRecord> records) {
    int present = 0;
    int late = 0;
    int absent =
        0; // Absent logic usually requires knowing total possible services vs attended.
    // For now, we only count explicit 'absent' records if they exist, or just show 0 if not tracked explicitly yet.

    for (var r in records) {
      if (r.present) {
        present++;
        if (r.status == 'late') late++;
      } else {
        absent++;
      }
    }
    return {'present': present, 'late': late, 'absent': absent};
  }

  Color _colorForRecord(AttendanceRecord record) {
    if (!record.present || record.status == 'absent') return Colors.redAccent;
    if (record.method == 'remote') return Colors.purple;
    if (record.status == 'late') return Colors.orange;
    return Colors.green;
  }

  String _labelForRecord(AttendanceRecord record) {
    if (!record.present || record.status == 'absent') return 'Absent';
    if (record.method == 'remote') return 'Remote present';
    if (record.status == 'late') {
      return '${record.minutesLate ?? 0} min late';
    }
    return 'On time';
  }
}

class _WeekdayLabel extends StatelessWidget {
  const _WeekdayLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}
