import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_feedback.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/attendance_service.dart';

class AttendanceSettingsScreen extends StatefulWidget {
  const AttendanceSettingsScreen({super.key});

  @override
  State<AttendanceSettingsScreen> createState() =>
      _AttendanceSettingsScreenState();
}

class _AttendanceSettingsScreenState extends State<AttendanceSettingsScreen> {
  bool _autoCheckIn = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoCheckIn = prefs.getBool('auto_check_in') ?? false;
      _isLoading = false;
    });
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
    } else {
      AttendanceService().stopMonitoring();
    }
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
                        ? 'Active (Monitoring location)'
                        : 'Disabled'),
                    value: _autoCheckIn,
                    onChanged: _toggleAutoCheckIn,
                  ),
                  if (_autoCheckIn) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Colors.green.withValues(alpha: 0.3))),
                      child: Row(
                        children: const [
                          Icon(Icons.check_circle, color: Colors.green),
                          SizedBox(width: 10),
                          Expanded(
                              child: Text(
                                  'You are all set. We will notify you when you are marked present.',
                                  style: TextStyle(color: Colors.green))),
                        ],
                      ),
                    ),
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
