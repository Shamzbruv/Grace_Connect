import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/haptic_service.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/theme_provider.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../tutorial/tutorial_controller.dart';
import '../../tutorial/tutorial_anchor.dart';
import '../../experience/app_experience_controller.dart';
import '../../experience/app_experience_host.dart';

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
    try {
      final prefs = await SharedPreferences.getInstance();
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) {
        return;
      }
      setState(() {
        _dataSaver = prefs.getBool('data_saver') ?? false;
        _haptics = prefs.getBool('haptics_enabled') ?? true;
        _versionLabel =
            'Version ${packageInfo.version} (Build ${packageInfo.buildNumber})';
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _versionLabel = 'Grace Connect';
        });
      }
    }
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
    final tutorials = context.watch<TutorialController?>();
    final experience = context.watch<AppExperienceController?>();

    return AppScaffold(
      title: 'Devices & App',
      tutorialId: 'devices_app',
      tutorialReady: !_isLoading,
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
                    // Apply now rather than at next launch, and confirm the
                    // change with the very feedback being switched on.
                    HapticService.setEnabled(value);
                    if (value) HapticService.success();
                  },
                ),
                if (experience?.initialized == true)
                  ListTile(
                    leading: const Icon(Icons.star_outline),
                    title: const Text('Rate Grace Connect'),
                    subtitle: Text(experience!.storeUrl == null
                        ? 'Available when the store listing is published.'
                        : 'Share honest feedback on ${experience.storeName}.'),
                    onTap: experience.storeUrl == null
                        ? null
                        : () async {
                            final opened =
                                await openExperienceStore(experience);
                            if (!opened && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'The store could not be opened. Please try again.')));
                            }
                          },
                  ),
                if (tutorials != null) ...[
                  const Padding(
                      padding: EdgeInsets.fromLTRB(4, 20, 4, 8),
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text('GUIDANCE'))),
                  SwitchListTile(
                    secondary: const Icon(Icons.school_outlined),
                    title: const Text('Guided Tutorials'),
                    subtitle: const Text(
                        'Show quick tips when you open a screen for the first time.'),
                    value: tutorials.enabled,
                    onChanged: !tutorials.initialized
                        ? null
                        : (value) async {
                            await tutorials.setEnabled(value);
                            if (value && context.mounted) {
                              _showTutorialRestarted(context);
                            }
                          },
                  ).tutorial('devices_app.tools'),
                  ListTile(
                    leading: const Icon(Icons.replay_outlined),
                    title: const Text('Restart All Tutorials'),
                    subtitle:
                        const Text('Start fresh as you visit each screen.'),
                    enabled: tutorials.initialized,
                    onTap: !tutorials.initialized
                        ? null
                        : () async {
                            final restart = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                      title:
                                          const Text('Restart all tutorials?'),
                                      content: const Text(
                                          'Grace Connect will treat each tutorial-enabled screen as new the next time you visit it.'),
                                      actions: [
                                        TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('Cancel')),
                                        FilledButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('Restart'))
                                      ],
                                    ));
                            if (restart != true) {
                              return;
                            }
                            await tutorials.restartAll();
                            if (context.mounted) {
                              _showTutorialRestarted(context);
                            }
                          },
                  ),
                  const SizedBox(height: 20),
                ],
                // "Is this even working?" is otherwise unanswerable: a
                // selection buzz is 12ms and easy to miss, and Android
                // silently drops haptics entirely when its own touch
                // vibration setting is off. This fires an unmistakable
                // double pulse and says plainly when the device cannot.
                _buildActionTile(
                  context,
                  HapticService.isSupported
                      ? 'Test vibration'
                      : 'Test vibration (no motor detected)',
                  Icons.play_circle_outline,
                  () async {
                    if (!_haptics) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Turn Haptic Feedback on first, then test it.',
                          ),
                        ),
                      );
                      return;
                    }
                    await HapticService.test();
                    if (!context.mounted) {
                      return;
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          HapticService.isSupported
                              ? 'Sent a double buzz. If you felt nothing, check '
                                  'your phone\'s own vibration settings.'
                              : 'This device reports no vibration motor.',
                        ),
                      ),
                    );
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

  void _showTutorialRestarted(BuildContext context) =>
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Tutorials restarted. You’ll see a short guide as you visit each screen.')));

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
