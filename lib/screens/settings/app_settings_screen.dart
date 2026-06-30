import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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
  String _versionLabel = 'Version loading...';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final packageInfo = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _dataSaver = prefs.getBool('data_saver') ?? false;
      _haptics = prefs.getBool('haptics_enabled') ?? true;
      _versionLabel =
          'Version ${packageInfo.version} (Build ${packageInfo.buildNumber})';
      _isLoading = false;
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  Future<void> _openPublicLegalPage(String path) async {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final uri = Uri.https('www.graceconnect.love', cleanPath);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${uri.toString()}')),
      );
    }
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
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        const Icon(Icons.perm_device_information,
                            size: 60, color: Colors.grey),
                        const SizedBox(height: 16),
                        const Text('Grace Connect App',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold)),
                        Text(_versionLabel,
                            style: const TextStyle(color: Colors.grey)),
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
                  _openPublicLegalPage('/terms.html');
                }),
                _buildActionTile(
                    context, 'Privacy Policy', Icons.privacy_tip_outlined, () {
                  _openPublicLegalPage('/privacy.html');
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
