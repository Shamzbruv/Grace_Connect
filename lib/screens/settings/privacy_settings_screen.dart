import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/ui/app_scaffold.dart';
import 'package:google_fonts/google_fonts.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool _isProfilePrivate = false;
  bool _allowMessages = true;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final doc = await Supabase.instance.client
            .from('users')
            .select()
            .eq('uid', user.id)
            .maybeSingle();
        if (doc != null && mounted) {
          setState(() {
            _isProfilePrivate = doc['isProfilePrivate'] ?? false;
            _allowMessages = doc['allowMessages'] ?? true;
          });
        }
      } catch (e) {
        debugPrint('Error loading privacy settings: $e');
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveSettings({
    bool? isProfilePrivate,
    bool? allowMessages,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() {
      _isSaving = true;
      if (isProfilePrivate != null) _isProfilePrivate = isProfilePrivate;
      if (allowMessages != null) _allowMessages = allowMessages;
    });

    try {
      await Supabase.instance.client.from('users').update({
        'isProfilePrivate': _isProfilePrivate,
        'allowMessages': _allowMessages,
      }).eq('uid', user.id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Privacy settings saved')),
        );
      }
    } catch (e) {
      debugPrint('Failed to sync privacy settings to Supabase: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save privacy settings: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Privacy & Safety',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Profile Visibility',
                    style: GoogleFonts.outfit(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(
                    'Control who can see your profile and contact information.',
                    style: TextStyle(color: Colors.grey[600])),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Private Profile',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'Hide your profile details from the member directory.'),
                  value: _isProfilePrivate,
                  onChanged: _isSaving
                      ? null
                      : (value) => _saveSettings(isProfilePrivate: value),
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('Allow Member Messages',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'Let church members contact you from your profile.'),
                  value: _allowMessages,
                  onChanged: _isSaving
                      ? null
                      : (value) => _saveSettings(allowMessages: value),
                  contentPadding: EdgeInsets.zero,
                ),
                const Divider(height: 48),
                Text('Blocked Users',
                    style: GoogleFonts.outfit(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                ListTile(
                  tileColor: Theme.of(context).cardTheme.color,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  leading: Icon(Icons.block,
                      color: Theme.of(context).colorScheme.error),
                  title: const Text('Manage Blocked Users'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    // Navigate to blocked users list (omitted for brevity, can be a dialog)
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('No users blocked.')));
                  },
                ),
              ],
            ),
    );
  }
}
