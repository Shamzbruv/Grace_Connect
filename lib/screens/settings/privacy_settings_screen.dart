import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../widgets/ui/app_scaffold.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/user_profile.dart';
import '../../services/moderation_service.dart';
import '../../services/user_service.dart';

class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  bool _isProfilePrivate = false;
  bool _allowMessages = true;
  bool _showContactInfo = true;
  String _contactInfoVisibility = 'church';
  bool _showFamilyTree = true;
  bool _showFamilyRelationshipTypes = true;
  bool _allowFamilyLinkRequests = true;
  String _familyTreeVisibility = 'church';
  bool _isLoading = true;
  bool _isSaving = false;
  final ModerationService _moderationService = ModerationService();
  final UserService _userService = UserService();

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
            _showContactInfo = doc['showContactInfo'] ?? true;
            _contactInfoVisibility = doc['contactInfoVisibility'] ??
                (doc['showContactInfo'] == false ? 'private' : 'church');
            _showFamilyTree = doc['showFamilyTree'] ?? true;
            _showFamilyRelationshipTypes =
                doc['showFamilyRelationshipTypes'] ?? true;
            _allowFamilyLinkRequests = doc['allowFamilyLinkRequests'] ?? true;
            _familyTreeVisibility = doc['familyTreeVisibility'] ?? 'church';
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
    bool? showContactInfo,
    String? contactInfoVisibility,
    bool? showFamilyTree,
    bool? showFamilyRelationshipTypes,
    bool? allowFamilyLinkRequests,
    String? familyTreeVisibility,
  }) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    setState(() {
      _isSaving = true;
      if (isProfilePrivate != null) _isProfilePrivate = isProfilePrivate;
      if (allowMessages != null) _allowMessages = allowMessages;
      if (showContactInfo != null) _showContactInfo = showContactInfo;
      if (contactInfoVisibility != null) {
        _contactInfoVisibility = contactInfoVisibility;
      }
      if (showFamilyTree != null) _showFamilyTree = showFamilyTree;
      if (showFamilyRelationshipTypes != null) {
        _showFamilyRelationshipTypes = showFamilyRelationshipTypes;
      }
      if (allowFamilyLinkRequests != null) {
        _allowFamilyLinkRequests = allowFamilyLinkRequests;
      }
      if (familyTreeVisibility != null) {
        _familyTreeVisibility = familyTreeVisibility;
      }
    });

    try {
      await Supabase.instance.client.from('users').update({
        'isProfilePrivate': _isProfilePrivate,
        'allowMessages': _allowMessages,
        'showContactInfo': _showContactInfo,
        'contactInfoVisibility': _contactInfoVisibility,
        'showFamilyTree': _showFamilyTree,
        'showFamilyRelationshipTypes': _showFamilyRelationshipTypes,
        'allowFamilyLinkRequests': _allowFamilyLinkRequests,
        'familyTreeVisibility': _familyTreeVisibility,
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

  Future<void> _showBlockedUsers() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      final blockedIds = await _moderationService.blockedUserIds();
      final blockedUsers = <UserProfile>[];
      for (final blockedId in blockedIds) {
        final profile = await _userService.getUserProfile(blockedId);
        if (profile != null) blockedUsers.add(profile);
      }

      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        builder: (sheetContext) {
          var users = blockedUsers;
          return StatefulBuilder(
            builder: (context, setSheetState) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Blocked Users',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 12),
                    if (users.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('No users blocked.'),
                      )
                    else
                      ...users.map(
                        (user) {
                          final displayName = user.fullName.isNotEmpty
                              ? user.fullName
                              : (user.email.isNotEmpty ? user.email : 'Member');
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundImage: user.photoUrl.isNotEmpty
                                  ? NetworkImage(user.photoUrl)
                                  : null,
                              child: user.photoUrl.isNotEmpty
                                  ? null
                                  : Text(displayName.characters.first
                                      .toUpperCase()),
                            ),
                            title: Text(displayName),
                            trailing: TextButton(
                              onPressed: () async {
                                await _moderationService.unblockUser(user.uid);
                                setSheetState(
                                  () => users = users
                                      .where((item) => item.uid != user.uid)
                                      .toList(),
                                );
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '$displayName unblocked.',
                                    ),
                                  ),
                                );
                              },
                              child: const Text('Unblock'),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => navigator.pop(),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not load blocked users: $error')),
      );
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
                _buildSectionHeader(
                  context,
                  'Profile Visibility',
                  'Control your member profile, contact details, and direct messages.',
                ),
                _buildSwitchTile(
                  title: 'Private Profile',
                  subtitle:
                      'Hide contact details and sensitive profile information from other members.',
                  value: _isProfilePrivate,
                  onChanged: (value) => _saveSettings(isProfilePrivate: value),
                ),
                _buildSwitchTile(
                  title: 'Show Contact Info',
                  subtitle:
                      'Allow members to see your email and phone number on your profile.',
                  value: _showContactInfo,
                  onChanged: _isProfilePrivate
                      ? null
                      : (value) => _saveSettings(
                            showContactInfo: value,
                            contactInfoVisibility: value
                                ? (_contactInfoVisibility == 'private'
                                    ? 'church'
                                    : _contactInfoVisibility)
                                : 'private',
                          ),
                ),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _contactInfoVisibility,
                  items: const [
                    DropdownMenuItem(
                      value: 'church',
                      child: Text('My church only'),
                    ),
                    DropdownMenuItem(
                      value: 'everyone',
                      child: Text('Any Grace Connect member'),
                    ),
                    DropdownMenuItem(
                      value: 'private',
                      child: Text('Only me'),
                    ),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Contact Info Audience',
                    prefixIcon: Icon(Icons.contact_mail_outlined),
                  ),
                  onChanged: _isSaving || _isProfilePrivate
                      ? null
                      : (value) {
                          if (value == null) return;
                          _saveSettings(
                            showContactInfo: value != 'private',
                            contactInfoVisibility: value,
                          );
                        },
                ),
                const SizedBox(height: 8),
                Text(
                  _contactInfoVisibilityDescription,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                _buildSwitchTile(
                  title: 'Allow Member Messages',
                  subtitle:
                      'Let church members start a secure message from your profile.',
                  value: _allowMessages,
                  onChanged: _isProfilePrivate
                      ? null
                      : (value) => _saveSettings(allowMessages: value),
                ),
                const Divider(height: 40),
                _buildSectionHeader(
                  context,
                  'Family Tree Privacy',
                  'Decide how your family connections appear across Grace Connect.',
                ),
                _buildSwitchTile(
                  title: 'Show Family Tree',
                  subtitle:
                      'Display approved family connections on your profile.',
                  value: _showFamilyTree,
                  onChanged: (value) => _saveSettings(showFamilyTree: value),
                ),
                _buildSwitchTile(
                  title: 'Show Relationship Types',
                  subtitle:
                      'Show exact labels like mother-in-law, stepfather, cousin, or spiritual mentor.',
                  value: _showFamilyRelationshipTypes,
                  onChanged: !_showFamilyTree
                      ? null
                      : (value) => _saveSettings(
                            showFamilyRelationshipTypes: value,
                          ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  // ignore: deprecated_member_use
                  value: _familyTreeVisibility,
                  items: const [
                    DropdownMenuItem(
                      value: 'church',
                      child: Text('Church members'),
                    ),
                    DropdownMenuItem(
                      value: 'family',
                      child: Text('Approved family only'),
                    ),
                    DropdownMenuItem(
                      value: 'private',
                      child: Text('Only me'),
                    ),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Family Tree Audience',
                    prefixIcon: Icon(Icons.visibility_outlined),
                  ),
                  onChanged: _isSaving || !_showFamilyTree
                      ? null
                      : (value) {
                          if (value == null) return;
                          _saveSettings(familyTreeVisibility: value);
                        },
                ),
                const SizedBox(height: 8),
                Text(
                  _familyTreeVisibilityDescription,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 8),
                _buildSwitchTile(
                  title: 'Allow Family Link Requests',
                  subtitle:
                      'Let members request an official family connection with you.',
                  value: _allowFamilyLinkRequests,
                  onChanged: (value) =>
                      _saveSettings(allowFamilyLinkRequests: value),
                ),
                const Divider(height: 48),
                _buildSectionHeader(
                  context,
                  'Blocked Users',
                  'Blocked members cannot message you or interact with your content.',
                ),
                const SizedBox(height: 16),
                ListTile(
                  tileColor: Theme.of(context).cardTheme.color,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  leading: Icon(Icons.block,
                      color: Theme.of(context).colorScheme.error),
                  title: const Text('Manage Blocked Users'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showBlockedUsers,
                ),
              ],
            ),
    );
  }

  String get _familyTreeVisibilityDescription {
    return switch (_familyTreeVisibility) {
      'family' =>
        'Only people with an approved family link to you can see your family tree.',
      'private' => 'Your family tree is kept private and only visible to you.',
      _ =>
        'Members in your church can see approved family links on your profile.',
    };
  }

  String get _contactInfoVisibilityDescription {
    if (_isProfilePrivate || !_showContactInfo) {
      return 'Your email and phone number are hidden from other members.';
    }
    return switch (_contactInfoVisibility) {
      'everyone' =>
        'Any signed-in Grace Connect member can see your email and phone number.',
      'private' => 'Your email and phone number are visible only to you.',
      _ => 'Only members from your church can see your email and phone number.',
    };
  }

  Widget _buildSectionHeader(
    BuildContext context,
    String title,
    String subtitle,
  ) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return SwitchListTile(
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle),
      value: value,
      onChanged: _isSaving ? null : onChanged,
      contentPadding: EdgeInsets.zero,
    );
  }
}
