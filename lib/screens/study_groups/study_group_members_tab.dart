import 'package:flutter/material.dart';

import '../../models/study_group_model.dart';
import '../../models/user_profile.dart';
import '../../services/study_group_access_service.dart';
import '../../services/study_group_service.dart';

class StudyGroupMembersTab extends StatefulWidget {
  final StudyGroup group;
  final StudyGroupAccess access;
  final StudyGroupService service;
  final ValueChanged<StudyGroup> onGroupChanged;

  const StudyGroupMembersTab({
    super.key,
    required this.group,
    required this.access,
    required this.service,
    required this.onGroupChanged,
  });

  @override
  State<StudyGroupMembersTab> createState() => _StudyGroupMembersTabState();
}

class _StudyGroupMembersTabState extends State<StudyGroupMembersTab> {
  Future<List<UserProfile>>? _membersFuture;

  @override
  void initState() {
    super.initState();
    _refreshMembers();
  }

  @override
  void didUpdateWidget(covariant StudyGroupMembersTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group != widget.group) _refreshMembers();
  }

  void _refreshMembers() {
    final ids = <String>{
      widget.group.leaderId,
      ...widget.group.adminIds,
      ...widget.group.memberIds,
      ...widget.group.pendingMemberIds,
    }.where((id) => id.trim().isNotEmpty).toList();
    _membersFuture = widget.service.fetchGroupMembers(ids);
  }

  Future<void> _approve(String userId) async {
    try {
      await widget.service.approvePendingMember(widget.group.id, userId);
      final members = [...widget.group.memberIds];
      if (!members.contains(userId)) members.add(userId);
      final pending = [...widget.group.pendingMemberIds]..remove(userId);
      widget.onGroupChanged(
        widget.group.copyWith(memberIds: members, pendingMemberIds: pending),
      );
      if (!mounted) return;
      setState(_refreshMembers);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member approved.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not approve member: $error')),
      );
    }
  }

  Future<void> _setAdmin(String userId, bool makeAdmin) async {
    try {
      await widget.service.setGroupAdmin(
        widget.group.id,
        userId,
        makeAdmin: makeAdmin,
      );
      final admins = [...widget.group.adminIds];
      if (makeAdmin) {
        if (!admins.contains(userId)) admins.add(userId);
      } else {
        admins.remove(userId);
      }
      widget.onGroupChanged(widget.group.copyWith(adminIds: admins));
      if (!mounted) return;
      setState(_refreshMembers);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update group role: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<UserProfile>>(
      future: _membersFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final members = snapshot.data ?? const <UserProfile>[];
        final byId = {for (final member in members) member.uid: member};
        final pendingMembers = widget.group.pendingMemberIds
            .map((id) => byId[id])
            .whereType<UserProfile>()
            .toList();
        final activeMembers = <UserProfile>[
          if (byId[widget.group.leaderId] != null) byId[widget.group.leaderId]!,
          ...widget.group.adminIds
              .where((id) => id != widget.group.leaderId)
              .map((id) => byId[id])
              .whereType<UserProfile>(),
          ...widget.group.memberIds
              .where((id) =>
                  id != widget.group.leaderId &&
                  !widget.group.adminIds.contains(id))
              .map((id) => byId[id])
              .whereType<UserProfile>(),
        ];

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
          children: [
            if (widget.access.canManageMembers &&
                pendingMembers.isNotEmpty) ...[
              _sectionTitle(context, 'Pending Requests'),
              ...pendingMembers.map(
                (member) => _memberTile(
                  member,
                  subtitle: 'Waiting for approval',
                  trailing: FilledButton(
                    onPressed: () => _approve(member.uid),
                    child: const Text('Approve'),
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],
            _sectionTitle(context, 'Members'),
            if (activeMembers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No active members found.'),
              )
            else
              ...activeMembers.map((member) {
                final isLeader = member.uid == widget.group.leaderId;
                final isAdmin = widget.group.adminIds.contains(member.uid);
                return _memberTile(
                  member,
                  subtitle: isLeader
                      ? 'Leader'
                      : isAdmin
                          ? 'Group admin'
                          : 'Member',
                  trailing: widget.access.canManageMembers && !isLeader
                      ? TextButton(
                          onPressed: () => _setAdmin(member.uid, !isAdmin),
                          child: Text(isAdmin ? 'Remove Admin' : 'Make Admin'),
                        )
                      : null,
                );
              }),
          ],
        );
      },
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _memberTile(
    UserProfile member, {
    required String subtitle,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundImage:
            member.photoUrl.isNotEmpty ? NetworkImage(member.photoUrl) : null,
        child: member.photoUrl.isEmpty
            ? Text(member.fullName.trim().isEmpty
                ? '?'
                : member.fullName.trim()[0].toUpperCase())
            : null,
      ),
      title: Text(member.fullName.isEmpty ? member.email : member.fullName),
      subtitle: Text(subtitle),
      trailing: trailing,
    );
  }
}
