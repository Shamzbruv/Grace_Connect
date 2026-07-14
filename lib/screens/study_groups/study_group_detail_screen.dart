import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/study_group_model.dart';
import '../../providers/user_role_provider.dart';
import '../../services/study_group_access_service.dart';
import '../../services/study_group_service.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_scaffold.dart';
import 'study_group_discussion_tab.dart';
import 'study_group_invitation_screen.dart';
import 'study_group_members_tab.dart';
import 'study_group_overview_tab.dart';
import 'study_group_read_tab.dart';
import 'study_group_resources_screen.dart';
import 'study_group_settings_screen.dart';

class StudyGroupDetailScreen extends StatefulWidget {
  final StudyGroup group;
  const StudyGroupDetailScreen({super.key, required this.group});

  @override
  State<StudyGroupDetailScreen> createState() => _StudyGroupDetailScreenState();
}

class _StudyGroupDetailScreenState extends State<StudyGroupDetailScreen> {
  final StudyGroupService _service = StudyGroupService();
  late StudyGroup _group;
  late String _currentUid;
  bool _isMember = false;
  bool _isPending = false;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _currentUid = Supabase.instance.client.auth.currentUser?.id ?? '';
    _syncMembershipState();
  }

  void _syncMembershipState() {
    _isMember = StudyGroupAccessService.isMemberOf(_group, _currentUid);
    _isPending = StudyGroupAccessService.isPendingIn(_group, _currentUid);
  }

  Future<void> _toggleMembership() async {
    try {
      if (_isMember) {
        await _service.leaveGroup(_group.id, _currentUid);
        final members = [..._group.memberIds]..remove(_currentUid);
        final admins = [..._group.adminIds]..remove(_currentUid);
        setState(() {
          _group = _group.copyWith(memberIds: members, adminIds: admins);
          _syncMembershipState();
        });
        return;
      }

      final status = await _service.joinGroup(_group.id, _currentUid);
      if (!mounted) return;
      if (status == 'pending') {
        final pending = [..._group.pendingMemberIds];
        if (!pending.contains(_currentUid)) pending.add(_currentUid);
        setState(() {
          _group = _group.copyWith(pendingMemberIds: pending);
          _syncMembershipState();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Your request was sent.')),
        );
        return;
      }

      final members = [..._group.memberIds];
      if (!members.contains(_currentUid)) members.add(_currentUid);
      setState(() {
        _group = _group.copyWith(
          memberIds: members,
          pendingMemberIds: [..._group.pendingMemberIds]..remove(_currentUid),
        );
        _syncMembershipState();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update membership: $error')),
      );
    }
  }

  Future<void> _openSettings(StudyGroupAccess access) async {
    final result = await Navigator.push<StudyGroup>(
      context,
      MaterialPageRoute(
        builder: (_) => StudyGroupSettingsScreen(
          group: _group,
          access: access,
        ),
      ),
    );
    if (result == null || !mounted) return;
    if (result.isArchived) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _group = result;
      _syncMembershipState();
    });
  }

  void _setGroup(StudyGroup group) {
    setState(() {
      _group = group;
      _syncMembershipState();
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<UserRoleProvider>(context).userProfile;
    final access = StudyGroupAccessService.forGroup(
      group: _group,
      currentUserId: _currentUid,
      profile: profile,
    );

    return DefaultTabController(
      length: 5,
      child: AppScaffold(
        title: _group.name,
        actions: [
          if (access.canOpenSettings)
            IconButton(
              tooltip: 'Group settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => _openSettings(access),
            ),
          if (!_isMember)
            TextButton(
              onPressed: _isPending ? null : _toggleMembership,
              child: Text(_isPending ? 'REQUESTED' : 'JOIN'),
            ),
        ],
        body: Column(
          children: [
            _GroupHeader(group: _group, isPending: _isPending),
            TabBar(
              isScrollable: true,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'Read'),
                Tab(text: 'Discuss'),
                Tab(text: 'Members'),
                Tab(text: 'More'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  StudyGroupOverviewTab(group: _group, service: _service),
                  StudyGroupReadTab(
                    group: _group,
                    access: access,
                    service: _service,
                  ),
                  StudyGroupDiscussionTab(
                    group: _group,
                    access: access,
                    isMember: _isMember,
                    currentUserId: _currentUid,
                    service: _service,
                  ),
                  StudyGroupMembersTab(
                    group: _group,
                    access: access,
                    service: _service,
                    onGroupChanged: _setGroup,
                  ),
                  _MoreTab(
                    group: _group,
                    access: access,
                    isMember: _isMember,
                    onLeave: _toggleMembership,
                    onSettings: () => _openSettings(access),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final StudyGroup group;
  final bool isPending;

  const _GroupHeader({
    required this.group,
    required this.isPending,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: AppCard(
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundImage: group.profilePhotoUrl.isNotEmpty
                  ? NetworkImage(group.profilePhotoUrl)
                  : null,
              child: group.profilePhotoUrl.isEmpty
                  ? const Icon(Icons.groups_2_outlined)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.displayStudy,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    group.schedule.isEmpty ? 'Meeting not set' : group.schedule,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _HeaderChip(label: group.privacyLabel),
                      _HeaderChip(label: group.joinModeLabel),
                      if (isPending)
                        const _HeaderChip(label: 'Request Pending'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final String label;
  const _HeaderChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .primaryContainer
            .withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _MoreTab extends StatelessWidget {
  final StudyGroup group;
  final StudyGroupAccess access;
  final bool isMember;
  final VoidCallback onLeave;
  final VoidCallback onSettings;

  const _MoreTab({
    required this.group,
    required this.access,
    required this.isMember,
    required this.onLeave,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Guidelines',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                group.guidelines.trim().isEmpty
                    ? 'No guidelines have been added yet.'
                    : group.guidelines,
              ),
            ],
          ),
        ),
        AppCard(
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.attach_file_outlined),
                title: const Text('Resources'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudyGroupResourcesScreen(group: group),
                  ),
                ),
              ),
              if (access.canManageMembers)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_add_alt_outlined),
                  title: const Text('Invitations'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StudyGroupInvitationScreen(group: group),
                    ),
                  ),
                ),
              if (access.canOpenSettings)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Group settings'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: onSettings,
                ),
            ],
          ),
        ),
        if (isMember &&
            group.leaderId != Supabase.instance.client.auth.currentUser?.id)
          OutlinedButton.icon(
            onPressed: onLeave,
            icon: const Icon(Icons.logout_outlined),
            label: const Text('Leave Group'),
          ),
      ],
    );
  }
}
