import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Added
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../theme/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/notification_service.dart'; // Added
import '../../providers/user_role_provider.dart'; // Added

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _churchAnnouncements = false;
  bool _serviceReminders = false;
  bool _communityPosts = false;
  bool _prayerRequests = false;
  bool _dailyDevotionals = false;
  bool _dailyQuiz = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _churchAnnouncements =
          prefs.getBool(NotificationService.churchWidePrefKey) ?? false;
      _serviceReminders = prefs.getBool('notify_service') ?? false;
      _communityPosts = prefs.getBool('notify_community') ?? false;
      _prayerRequests = prefs.getBool('notify_prayer') ?? false;
      _dailyDevotionals = prefs.getBool('notify_devotionals') ?? false;
      _dailyQuiz = prefs.getBool('notify_daily_quiz') ?? false;
      _isLoading = false;
    });
  }

  Future<void> _toggleSetting(String key, bool value) async {
    if (value) {
      final allowed = await NotificationService().ensurePushPermission();
      if (!allowed) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notifications were not enabled on this device.'),
          ),
        );
        return;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    setState(() {
      if (key == NotificationService.churchWidePrefKey) {
        _churchAnnouncements = value;
      }
      if (key == 'notify_service') _serviceReminders = value;
      if (key == 'notify_community') _communityPosts = value;
      if (key == 'notify_prayer') _prayerRequests = value;
      if (key == 'notify_devotionals') _dailyDevotionals = value;
      if (key == 'notify_daily_quiz') _dailyQuiz = value;
    });

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final column = switch (key) {
        'notify_service' => 'notifyAttendance',
        'notify_devotionals' => 'notifyDailyMotivation',
        'notify_daily_quiz' => 'notifyDailyQuiz',
        _ => null,
      };
      if (column != null) {
        await Supabase.instance.client
            .from('users')
            .update({column: value}).eq('uid', user.id);
      }
    }

    // Refresh subscriptions based on new settings
    // We need the churchId from the provider
    if (mounted) {
      final userProvider =
          Provider.of<UserRoleProvider>(context, listen: false);
      final profile = userProvider.userProfile;
      if (profile?.churchId != null) {
        await NotificationService().syncSubscriptions(
          profile!.churchId,
          roles: profile.roles,
          privileges: profile.appPrivileges,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Notifications',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionHeader('Church Activities'),
                ListTile(
                  leading: const Icon(Icons.inbox_outlined),
                  title: const Text('Notification Inbox'),
                  subtitle:
                      const Text('View likes, comments, and family requests'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/notifications'),
                ),
                const SizedBox(height: 12),
                _buildSwitchTile(
                  'Church Announcements',
                  'Official church-wide updates and live alerts',
                  _churchAnnouncements,
                  (val) => _toggleSetting(
                    NotificationService.churchWidePrefKey,
                    val,
                  ),
                ),
                _buildSwitchTile(
                  'Service Reminders',
                  'Get notified 30 mins before service starts',
                  _serviceReminders,
                  (val) => _toggleSetting('notify_service', val),
                ),
                _buildSwitchTile(
                  'Prayer Requests',
                  'When urgent prayer is needed',
                  _prayerRequests,
                  (val) => _toggleSetting('notify_prayer', val),
                ),
                _buildSwitchTile(
                  'Daily Devotionals',
                  'Daily Word at 5:00 AM',
                  _dailyDevotionals,
                  (val) => _toggleSetting('notify_devotionals', val),
                ),
                _buildSwitchTile(
                  'Daily Bible Quiz',
                  'New 5-question challenge each morning',
                  _dailyQuiz,
                  (val) => _toggleSetting('notify_daily_quiz', val),
                ),
                const Divider(height: 32),
                _buildSectionHeader('Community'),
                _buildSwitchTile(
                  'Community Posts',
                  'New posts and announcements',
                  _communityPosts,
                  (val) => _toggleSetting('notify_community', val),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: isDarkMode ? Colors.white : AppColors.primary,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _buildSwitchTile(
      String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ]),
      child: SwitchListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            )),
        value: value,
        onChanged: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
