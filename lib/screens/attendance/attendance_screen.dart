import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/attendance_service.dart';
import '../../models/attendance_record.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui/app_card.dart';

import '../../widgets/ui/app_loader.dart';
import 'remote_attendance_screen.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  String _filter = 'All'; // All, Weekly, Monthly, Yearly
  bool _autoCheckIn = true;
  bool _showDiagnostics = false;
  bool _isSetupLoading = false;
  bool _isSavingLocation = false;
  bool _isPromptLoading = false;
  bool _isMarkingPresent = false;
  String? _loadedChurchId;
  AttendanceSetupStatus? _setupStatus;
  AttendanceCheckInPrompt? _checkInPrompt;

  @override
  void initState() {
    super.initState();
    _loadAutoCheckInPreference();
  }

  Future<void> _loadAutoCheckInPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('auto_check_in') ?? true;
    if (!mounted) return;
    setState(() => _autoCheckIn = enabled);
    if (enabled) {
      await _attendanceService.initialize();
    }
  }

  Future<void> _toggleAutoCheckIn(bool value) async {
    setState(() => _autoCheckIn = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_check_in', value);

    if (value) {
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
      if (!mounted) return;
      setState(() {
        _checkInPrompt = AttendanceCheckInPrompt(
          hasActiveService: false,
          canMarkPresent: false,
          isInsideGeofence: false,
          alreadyMarked: false,
          message: 'Could not check active service: $e',
        );
      });
    } finally {
      if (mounted) setState(() => _isPromptLoading = false);
    }
  }

  Future<void> _markPresentForActiveService(String churchId) async {
    setState(() => _isMarkingPresent = true);
    try {
      await _attendanceService.markCurrentServicePresent(churchId);
      await _refreshCheckInPrompt(churchId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance marked present.')),
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

  Future<void> _saveChurchLocation(String churchId) async {
    setState(() => _isSavingLocation = true);
    try {
      await _attendanceService.saveChurchLocationFromCurrentPosition(churchId);
      await _refreshSetupStatus(churchId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Church location saved for check-ins.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save church location: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSavingLocation = false);
    }
  }

  bool _canManageAttendanceSetup(UserProfile user) {
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
        stream: _attendanceService.getAttendanceHistory(user.uid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoader();
          }

          if (snapshot.hasError) {
            return Center(
                child: Text('Error loading attendance: ${snapshot.error}'));
          }

          final records = snapshot.data ?? [];
          final filteredRecords = _filterRecords(records);
          final stats = _calculateStats(filteredRecords);

          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // GPS Status Card
                _buildGpsStatusCard(context, user),
                const SizedBox(height: 16),
                _buildActiveServiceCard(context, user),
                const SizedBox(height: 16),

                // Stats Row
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
                const SizedBox(height: 24),

                // Filters
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All', 'This Month', 'This Year'].map((filter) {
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
                          selectedColor: AppColors.primary,
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

                // List
                Expanded(
                  child: filteredRecords.isEmpty
                      ? Center(
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
                                  style:
                                      Theme.of(context).textTheme.bodyMedium),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredRecords.length,
                          itemBuilder: (context, index) {
                            final record = filteredRecords[index];
                            return _buildRecordCard(context, record);
                          },
                        ),
                ),
              ],
            ),
          );
        },
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
                        onPressed: _isSavingLocation
                            ? null
                            : () => _saveChurchLocation(user.churchId),
                        icon: _isSavingLocation
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location),
                        label: const Text('Set Location'),
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
    final canMark = prompt?.canMarkPresent == true && !_isMarkingPresent;
    final hasActive = prompt?.hasActiveService == true;
    final isVerified = prompt?.alreadyMarked == true;
    final isInside = prompt?.isInsideGeofence == true;

    return AppCard(
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
                    fontSize: 16,
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
            prompt?.message ?? 'Checking active service and church location...',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (prompt != null && hasActive) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              minHeight: 6,
              value: prompt.requiredDwellMinutes == 0
                  ? 1
                  : (prompt.currentDwellMinutes / prompt.requiredDwellMinutes)
                      .clamp(0, 1)
                      .toDouble(),
              backgroundColor:
                  theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isVerified
                  ? 'Present recorded for today.'
                  : isInside
                      ? '${prompt.currentDwellMinutes}/${prompt.requiredDwellMinutes} minutes verified on property.'
                      : 'Geofence verification required before check-in.',
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
                  label: Text(isVerified ? 'Already Present' : 'Mark Present'),
                ),
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
        title:
            Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
    if (_filter == 'This Month') {
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
}
