import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/theme_provider.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui/app_scaffold.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({super.key});

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  bool _dataSaver = false;
  bool _haptics = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _dataSaver = prefs.getBool('data_saver') ?? false;
      _haptics = prefs.getBool('haptics_enabled') ?? true;
      _isLoading = false;
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return AppScaffold(
      title: 'Devices & App',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        Icon(Icons.perm_device_information,
                            size: 60, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('Grace Connect App',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        Text('Version 1.0.0 (Build 1)',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.phone_iphone),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                  selected: {themeProvider.themeMode},
                  onSelectionChanged: (selection) {
                    themeProvider.setThemeMode(selection.first);
                  },
                ),
                const SizedBox(height: 16),
                _buildSwitchTile(
                  context,
                  'Data Saver',
                  'Reduce background media loading where supported.',
                  Icons.data_saver_on_outlined,
                  _dataSaver,
                  (value) {
                    setState(() => _dataSaver = value);
                    _saveBool('data_saver', value);
                  },
                ),
                _buildSwitchTile(
                  context,
                  'Haptic Feedback',
                  'Allow gentle vibration feedback on supported devices.',
                  Icons.vibration_outlined,
                  _haptics,
                  (value) {
                    setState(() => _haptics = value);
                    _saveBool('haptics_enabled', value);
                  },
                ),
                _buildActionTile(
                    context, 'Check for Updates', Icons.system_update, () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('You are on the latest version.')),
                  );
                }),
                _buildActionTile(
                    context, 'Terms of Service', Icons.description_outlined,
                    () {
                  Navigator.pushNamed(context, '/settings/terms');
                }),
                _buildActionTile(
                    context, 'Privacy Policy', Icons.privacy_tip_outlined, () {
                  Navigator.pushNamed(context, '/settings/privacy_policy');
                }),
                _buildActionTile(context, 'Open Source Licenses', Icons.code,
                    () {
                  showLicensePage(context: context);
                }),
              ],
            ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        secondary:
            Icon(icon, color: isDarkMode ? Colors.white : AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            )),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildActionTile(
      BuildContext context, String title, IconData icon, VoidCallback onTap) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading:
            Icon(icon, color: isDarkMode ? Colors.white : AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
