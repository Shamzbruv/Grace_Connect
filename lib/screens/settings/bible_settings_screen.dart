import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/bible_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui/app_scaffold.dart';

class BibleSettingsScreen extends StatefulWidget {
  const BibleSettingsScreen({super.key});

  @override
  State<BibleSettingsScreen> createState() => _BibleSettingsScreenState();
}

class _BibleSettingsScreenState extends State<BibleSettingsScreen> {
  String _translation = 'web';
  double _fontSize = 18;
  bool _showVerseNumbers = true;
  bool _dailyReminder = true;
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
      _translation = prefs.getString('bible_translation') ?? 'web';
      _fontSize = prefs.getDouble('bible_font_size') ?? 18;
      _showVerseNumbers = prefs.getBool('bible_show_verse_numbers') ?? true;
      _dailyReminder = prefs.getBool('notify_devotionals') ?? true;
      _isLoading = false;
    });
  }

  Future<void> _saveSetting(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    switch (value) {
      case String stringValue:
        await prefs.setString(key, stringValue);
      case double doubleValue:
        await prefs.setDouble(key, doubleValue);
      case bool boolValue:
        await prefs.setBool(key, boolValue);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bible settings saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Bible & Study',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  value: _translation,
                  decoration: const InputDecoration(
                    labelText: 'Preferred Translation',
                    border: OutlineInputBorder(),
                  ),
                  items: BibleService.translations.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _translation = value);
                    _saveSetting('bible_translation', value);
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'Reader Text Size',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Slider(
                  min: 14,
                  max: 26,
                  divisions: 6,
                  label: _fontSize.round().toString(),
                  activeColor: AppColors.primary,
                  value: _fontSize,
                  onChanged: (value) => setState(() => _fontSize = value),
                  onChangeEnd: (value) =>
                      _saveSetting('bible_font_size', value),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Show Verse Numbers'),
                  subtitle: const Text('Display verse numbers while reading.'),
                  value: _showVerseNumbers,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) {
                    setState(() => _showVerseNumbers = value);
                    _saveSetting('bible_show_verse_numbers', value);
                  },
                ),
                SwitchListTile(
                  title: const Text('Daily Study Reminders'),
                  subtitle:
                      const Text('Use notification settings for devotionals.'),
                  value: _dailyReminder,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (value) {
                    setState(() => _dailyReminder = value);
                    _saveSetting('notify_devotionals', value);
                  },
                ),
                const Divider(height: 36),
                ListTile(
                  leading: const Icon(Icons.menu_book_outlined),
                  title: const Text('Open Bible Reader'),
                  subtitle:
                      const Text('Your translation and reader size apply now.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.pushNamed(context, '/bible'),
                ),
              ],
            ),
    );
  }
}
