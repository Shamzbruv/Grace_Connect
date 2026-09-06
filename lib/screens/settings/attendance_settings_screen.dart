import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_feedback.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/attendance_service.dart';
import '../../services/notification_service.dart';

class AttendanceSettingsScreen extends StatefulWidget {
  const AttendanceSettingsScreen({super.key});

  @override
  State<AttendanceSettingsScreen> createState() =>
      _AttendanceSettingsScreenState();
}

class _AttendanceSettingsScreenState extends State<AttendanceSettingsScreen>
    with WidgetsBindingObserver {
  bool _autoCheckIn = false;
  bool _isLoading = true;
  bool? _batteryOptimizationIgnored;
  Future<AttendanceSetupStatus>? _diagnostics;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
    if (_isAndroid) _loadBatteryOptimizationStatus();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _autoCheckIn = prefs.getBool('auto_check_in') ?? false;
      _isLoading = false;
      _diagnostics = AttendanceService().getSetupStatus(
          context.read<UserRoleProvider>().userProfile?.placeId ?? '');
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadSettings();
      if (_isAndroid) _loadBatteryOptimizationStatus();
    }
  }

  Future<void> _loadBatteryOptimizationStatus() async {
    final ignored =
        await NotificationService().isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() => _batteryOptimizationIgnored = ignored);
  }

  Future<void> _openBatterySettings() async {
    await NotificationService().openBatteryOptimizationSettings();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (mounted) await _loadBatteryOptimizationStatus();
  }

  Future<void> _toggleAutoCheckIn(bool value) async {
    if (value && !kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      final accepted = await _showBackgroundLocationDisclosure();
      if (!accepted) return;
      final granted =
          await AttendanceService().requestAutoAttendancePermissions();
      if (!granted) {
        if (!mounted) return;
        setState(() => _autoCheckIn = false);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('auto_check_in', false);
        if (!mounted) return;
        AppFeedback.show(
          context,
          'Auto-attendance stays off until Location is set to “Allow all the time” in Android settings.',
          type: AppFeedbackType.warning,
        );
        return;
      }
    }

    setState(() => _autoCheckIn = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_check_in', value);
    if (value) {
      await AttendanceService().initialize();
      if (_isAndroid) await _loadBatteryOptimizationStatus();
    } else {
      AttendanceService().stopMonitoring();
    }
    if (mounted) await _loadSettings();
  }

  Future<bool> _showBackgroundLocationDisclosure() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Background location for auto-attendance'),
        content: const Text(
          'When you turn on Auto-Attendance, Grace Connect uses your precise location in the background—even when the app is closed—to detect when you enter and remain inside your church’s saved geofence during a scheduled service. '
          'It does not store or share a trail of where you travel. Only the attendance check-in result is saved. Turning Auto-Attendance off removes the Android geofence.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showManualCheckIn() {
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Service Code Check-In',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Use this when a leader displays a 6-digit service code. It only checks you in while a service is active.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    letterSpacing: 8,
                    fontWeight: FontWeight.bold,
                  ),
              decoration: const InputDecoration(
                hintText: "000000",
                counterText: "",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final code = codeController.text.trim();
              if (code.length != 6) {
                AppFeedback.show(
                  context,
                  'Enter the 6-digit service code first.',
                  type: AppFeedbackType.warning,
                );
                return;
              }

              final user = Supabase.instance.client.auth.currentUser;
              if (user == null) return;

              final profile = await Supabase.instance.client
                  .from('users')
                  .select('placeId')
                  .eq('uid', user.id)
                  .maybeSingle();
              final churchId = profile?['placeId'] as String?;

              if (churchId == null || churchId.isEmpty) {
                if (!context.mounted) return;
                AppFeedback.show(
                  context,
                  'No church profile found.',
                  type: AppFeedbackType.error,
                );
                return;
              }

              try {
                await AttendanceService().markRemotePresent(
                  userId: user.id,
                  churchId: churchId,
                  reason: 'Manual code check-in',
                  engagementAnswer: 'Code $code',
                );
                if (!context.mounted) return;
                Navigator.pop(context);
                AppFeedback.show(
                  context,
                  'Successfully checked in. Welcome to service.',
                  type: AppFeedbackType.success,
                );
              } catch (e) {
                if (!context.mounted) return;
                AppFeedback.show(
                  context,
                  'Could not check in: $e',
                  type: AppFeedbackType.error,
                );
              }
            },
            child: const Text('Check In'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AppScaffold(
      title: 'Attendance Settings',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Automatic Assessment',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Grace Connect can automatically mark you "Present" when you turn this on and are at church during a service for more than 10 minutes.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto-Register Attendance',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(_autoCheckIn
                        ? (AttendanceService().isMonitoring
                            ? 'Monitoring enabled'
                            : 'Enabled — setup needs attention')
                        : 'Disabled'),
                    value: _autoCheckIn,
                    onChanged: _toggleAutoCheckIn,
                  ),
                  if (_autoCheckIn) ...[
                    const SizedBox(height: 16),
                    FutureBuilder<AttendanceSetupStatus>(
                      future: _diagnostics,
                      builder: (context, snapshot) {
                        final status = snapshot.data;
                        if (snapshot.hasError) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                  'Could not check setup. Check your connection and tap Recheck.'),
                              TextButton(
                                onPressed: _loadSettings,
                                child: const Text('Recheck'),
                              ),
                            ],
                          );
                        }
                        if (status == null) {
                          return const LinearProgressIndicator();
                        }
                        final ready = status.blockers.isEmpty &&
                            AttendanceService().isMonitoring;
                        return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  ready
                                      ? 'Ready for the next scheduled service'
                                      : 'Auto-attendance needs attention',
                                  style: theme.textTheme.titleMedium),
                              for (final blocker in status.blockers)
                                Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(blocker)),
                              const SizedBox(height: 8),
                              Text(status.activeServiceName == null
                                  ? 'No service is open for attendance right now.'
                                  : 'Current service: ${status.activeServiceName}'),
                              if (status.radiusMeters != null &&
                                  status.radiusMeters! < 100)
                                const Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: Text(
                                        'The church radius is smaller than 100 metres. Background detection can be unreliable at this size. Ask your church administrator to check that the saved pin and radius cover the church grounds.')),
                              if (status.lastNativeEvent != null)
                                Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                        'Last background detection: ${status.lastNativeEvent}')),
                              const SizedBox(height: 8),
                              Text(AttendanceService().lastDebugStatus),
                              Wrap(spacing: 8, children: [
                                TextButton(
                                    onPressed: () async {
                                      await AttendanceService().initialize();
                                      if (mounted) await _loadSettings();
                                    },
                                    child: const Text('Recheck')),
                                TextButton(
                                    onPressed: Geolocator.openAppSettings,
                                    child: const Text('Location permissions')),
                                TextButton(
                                    onPressed: Geolocator.openLocationSettings,
                                    child: const Text('Device location')),
                              ]),
                            ]);
                      },
                    ),
                    if (_isAndroid && _batteryOptimizationIgnored == false) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.3))),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.battery_alert, color: Colors.orange),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Battery optimization is still restricting this app',
                                    style: TextStyle(
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Some phones stop background location checks to '
                              'save battery, which can keep auto-attendance '
                              'from marking you present without opening the '
                              'app. Allow Grace Connect to run in the '
                              'background to make this reliable.',
                              style: TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton(
                                onPressed: _openBatterySettings,
                                child: const Text('Allow background activity'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                  const Divider(height: 48),
                  Text(
                    'Service Code Check-In',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'For services where a leader shares a code on screen, enter it here to record your attendance during the active service window.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _showManualCheckIn,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Enter Service Code'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          backgroundColor: colorScheme.primary,
                          foregroundColor: colorScheme.onPrimary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  )
                ],
              ),
            ),
    );
  }
}
