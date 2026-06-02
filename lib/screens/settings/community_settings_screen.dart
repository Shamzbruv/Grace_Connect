import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_colors.dart';
import '../../widgets/ui/app_scaffold.dart';

class CommunitySettingsScreen extends StatefulWidget {
  const CommunitySettingsScreen({super.key});

  @override
  State<CommunitySettingsScreen> createState() =>
      _CommunitySettingsScreenState();
}

class _CommunitySettingsScreenState extends State<CommunitySettingsScreen> {
  bool _showMediaPreviews = true;
  bool _confirmBeforePosting = false;
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
      _showMediaPreviews = prefs.getBool('community_show_media') ?? true;
      _confirmBeforePosting =
          prefs.getBool('community_confirm_before_posting') ?? false;
      _isLoading = false;
    });
  }

  Future<void> _saveBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Community settings saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Community Settings',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSwitchTile(
                  context,
                  title: 'Show Media Previews',
                  subtitle: 'Display images and video previews in the feed.',
                  icon: Icons.image_outlined,
                  value: _showMediaPreviews,
                  onChanged: (value) {
                    setState(() => _showMediaPreviews = value);
                    _saveBool('community_show_media', value);
                  },
                ),
                const SizedBox(height: 12),
                _buildSwitchTile(
                  context,
                  title: 'Confirm Before Posting',
                  subtitle: 'Ask for confirmation before a post is published.',
                  icon: Icons.fact_check_outlined,
                  value: _confirmBeforePosting,
                  onChanged: (value) {
                    setState(() => _confirmBeforePosting = value);
                    _saveBool('community_confirm_before_posting', value);
                  },
                ),
                const SizedBox(height: 12),
                _buildInfoTile(
                  context,
                  icon: Icons.rule,
                  title: 'Community Guidelines',
                  subtitle: 'Read our community standards.',
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Community Guidelines'),
                        content: const Text(
                          'Be respectful, kind, and supportive. Posts should strengthen church community life. Harmful, harassing, or misleading content may be removed by leaders.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          )
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        secondary:
            Icon(icon, color: isDarkMode ? Colors.white : AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildInfoTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading:
            Icon(icon, color: isDarkMode ? Colors.white : AppColors.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
