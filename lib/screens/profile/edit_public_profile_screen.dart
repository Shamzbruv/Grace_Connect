import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/social_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/social_profile_service.dart';
import '../../widgets/ui/app_scaffold.dart';

class EditPublicProfileScreen extends StatefulWidget {
  const EditPublicProfileScreen({super.key});

  @override
  State<EditPublicProfileScreen> createState() =>
      _EditPublicProfileScreenState();
}

class _EditPublicProfileScreenState extends State<EditPublicProfileScreen> {
  final SocialProfileService _service = SocialProfileService();
  final TextEditingController _displayNameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  late Future<SocialProfile?> _profileFuture;
  bool _searchable = true;
  bool _acceptsMessages = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<SocialProfile?> _loadProfile() async {
    final roleProvider = context.read<UserRoleProvider>();
    final userProfile = roleProvider.userProfile;
    if (userProfile == null) return null;

    final profile = await _service.fetchProfile(userProfile.uid) ??
        await _service.ensureProfile(userProfile);
    if (mounted) {
      _displayNameController.text = profile.displayName;
      _bioController.text = profile.bio;
      setState(() {
        _searchable = profile.searchable;
        _acceptsMessages = profile.acceptsMessages;
      });
    }
    return profile;
  }

  Future<void> _save(SocialProfile profile) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final updated = profile.copyWith(
        displayName: _displayNameController.text.trim().isEmpty
            ? profile.displayName
            : _displayNameController.text.trim(),
        bio: _bioController.text.trim(),
        searchable: _searchable,
        acceptsMessages: _acceptsMessages,
      );
      await _service.updateProfile(updated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Public profile updated.')),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update public profile: $error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Edit Public Profile',
      body: FutureBuilder<SocialProfile?>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final profile = snapshot.data;
          if (profile == null) {
            return const Center(child: Text('Profile could not be loaded.'));
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
            children: [
              TextField(
                controller: _displayNameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _bioController,
                maxLines: 5,
                maxLength: 240,
                decoration: const InputDecoration(
                  labelText: 'Public bio',
                  alignLabelWithHint: true,
                  prefixIcon: Icon(Icons.auto_stories_outlined),
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show in public search'),
                value: _searchable,
                onChanged: (value) => setState(() => _searchable = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Allow message requests'),
                value: _acceptsMessages,
                onChanged: (value) => setState(() => _acceptsMessages = value),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving ? null : () => _save(profile),
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }
}
