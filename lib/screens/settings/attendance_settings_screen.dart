import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/attendance_service.dart';

class AttendanceSettingsScreen extends StatefulWidget {
  const AttendanceSettingsScreen({super.key});

  @override
  State<AttendanceSettingsScreen> createState() =>
      _AttendanceSettingsScreenState();
}

class _AttendanceSettingsScreenState extends State<AttendanceSettingsScreen> {
  bool _autoCheckIn = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoCheckIn = prefs.getBool('auto_check_in') ?? true;
      _isLoading = false;
    });
  }

  Future<void> _toggleAutoCheckIn(bool value) async {
    setState(() => _autoCheckIn = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_check_in', value);
    if (value) {
      await AttendanceService().initialize();
    } else {
      AttendanceService().stopMonitoring();
    }
  }

  void _showManualCheckIn() {
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).cardTheme.color,
        title: Text('Manual Check-In',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Enter the 6-digit code provided on the screen at church.'),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold),
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
              if (code.length != 6) return;

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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No church profile found.')),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                        Text('Successfully checked in! Welcome to service.'),
                    backgroundColor: Colors.green,
                  ),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not check in: $e')),
                );
              }
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Check In'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
                    style: GoogleFonts.outfit(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Grace Connect can automatically mark you "Present" when you are at church during a service for more than 10 minutes. This helps the church understand detailed attendance trends.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
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
                    activeColor: AppColors.primary,
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
                  Center(
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _showManualCheckIn,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Manual Check In'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
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
