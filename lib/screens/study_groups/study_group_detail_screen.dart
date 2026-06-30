import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../providers/user_role_provider.dart';
import '../../services/study_group_service.dart';
import '../../models/study_group_model.dart';
import '../../models/group_message_model.dart';
import '../../models/user_profile.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_text_field.dart';

class StudyGroupDetailScreen extends StatefulWidget {
  final StudyGroup group;
  const StudyGroupDetailScreen({super.key, required this.group});

  @override
  State<StudyGroupDetailScreen> createState() => _StudyGroupDetailScreenState();
}

class _StudyGroupDetailScreenState extends State<StudyGroupDetailScreen> {
  final StudyGroupService _service = StudyGroupService();
  final TextEditingController _msgController = TextEditingController();
  late String _currentUid;
  late Stream<List<GroupMessage>> _messagesStream;
  late StudyGroup _group;
  bool _isMember = false;
  bool _isPending = false;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _currentUid = Supabase.instance.client.auth.currentUser?.id ?? '';
    _isMember = _group.memberIds.contains(_currentUid) ||
        _group.adminIds.contains(_currentUid) ||
        _group.leaderId == _currentUid;
    _isPending = _group.pendingMemberIds.contains(_currentUid);
    _messagesStream = _service.getMessages(_group.id);
  }

  bool get _isAdmin =>
      _group.leaderId == _currentUid || _group.adminIds.contains(_currentUid);

  bool get _canSendMessages =>
      _isMember && (_group.allowMemberMessages || _isAdmin);

  Future<void> _sendMessage() async {
    if (_msgController.text.trim().isEmpty || !_canSendMessages || _isSending) {
      return;
    }
    final user = Supabase.instance.client.auth.currentUser;
    final profile =
        Provider.of<UserRoleProvider>(context, listen: false).userProfile;

    setState(() => _isSending = true);
    try {
      await _service.sendMessage(
        _group.id,
        user!.id,
        profile?.fullName.isNotEmpty == true
            ? profile!.fullName
            : user.userMetadata?['full_name'] ?? 'Member',
        _msgController.text.trim(),
        senderPhotoUrl: profile?.photoUrl ?? '',
      );
      _msgController.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send message: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _toggleMembership() async {
    try {
      if (_isMember) {
        await _service.leaveGroup(_group.id, _currentUid);
      } else {
        final status = await _service.joinGroup(_group.id, _currentUid);
        if (!mounted) return;
        if (status == 'pending') {
          final updatedPending = [..._group.pendingMemberIds];
          if (!updatedPending.contains(_currentUid)) {
            updatedPending.add(_currentUid);
          }
          setState(() {
            _isPending = true;
            _group = _group.copyWith(pendingMemberIds: updatedPending);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your request was sent to the group admins.'),
            ),
          );
          return;
        }
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update group membership: $error')),
      );
      return;
    }
    if (!mounted) return;

    final updatedMembers = [..._group.memberIds];
    if (_isMember) {
      updatedMembers.remove(_currentUid);
      final updatedAdmins = [..._group.adminIds]..remove(_currentUid);
      final updatedPending = [..._group.pendingMemberIds]..remove(_currentUid);
      setState(() {
        _isMember = false;
        _isPending = false;
        _group = _group.copyWith(
          memberIds: updatedMembers,
          adminIds: updatedAdmins,
          pendingMemberIds: updatedPending,
        );
      });
      return;
    } else if (!updatedMembers.contains(_currentUid)) {
      updatedMembers.add(_currentUid);
    }

    setState(() {
      _isMember = !_isMember;
      _isPending = false;
      _group = _group.copyWith(
        memberIds: updatedMembers,
        pendingMemberIds: [..._group.pendingMemberIds]..remove(_currentUid),
      );
    });
  }

  Future<void> _approveMember(String userId) async {
    try {
      await _service.approvePendingMember(_group.id, userId);
      if (!mounted) return;
      final members = [..._group.memberIds];
      if (!members.contains(userId)) members.add(userId);
      final pending = [..._group.pendingMemberIds]..remove(userId);
      setState(() {
        _group = _group.copyWith(
          memberIds: members,
          pendingMemberIds: pending,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group member approved.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not approve member: $error')),
      );
    }
  }

  Future<void> _setGroupAdmin(String userId, bool makeAdmin) async {
    try {
      await _service.setGroupAdmin(_group.id, userId, makeAdmin: makeAdmin);
      if (!mounted) return;
      final admins = [..._group.adminIds];
      if (makeAdmin) {
        if (!admins.contains(userId)) admins.add(userId);
      } else {
        admins.remove(userId);
      }
      setState(() => _group = _group.copyWith(adminIds: admins));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(makeAdmin ? 'Group admin added.' : 'Group admin removed.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update admin access: $error')),
      );
    }
  }

  Future<void> _showGroupSettings() async {
    final nameController = TextEditingController(text: _group.name);
    final topicController = TextEditingController(text: _group.topic);
    final scheduleController = TextEditingController(text: _group.schedule);
    final descriptionController =
        TextEditingController(text: _group.description);
    var allowMessages = _group.allowMemberMessages;
    var isPrivate = _group.isPrivate;
    var requireApproval = _group.requireJoinApproval;
    var isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Group Settings',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AppTextField(controller: nameController, label: 'Name'),
                  const SizedBox(height: 10),
                  AppTextField(controller: topicController, label: 'Topic'),
                  const SizedBox(height: 10),
                  AppTextField(
                      controller: scheduleController, label: 'Schedule'),
                  const SizedBox(height: 10),
                  AppTextField(
                    controller: descriptionController,
                    label: 'Description',
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Members can send messages'),
                    value: allowMessages,
                    onChanged: isSaving
                        ? null
                        : (value) {
                            setSheetState(() => allowMessages = value);
                          },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hide from browse list'),
                    value: isPrivate,
                    onChanged: isSaving
                        ? null
                        : (value) {
                            setSheetState(() => isPrivate = value);
                          },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Require approval to join'),
                    value: requireApproval,
                    onChanged: isSaving
                        ? null
                        : (value) {
                            setSheetState(() => requireApproval = value);
                          },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: isSaving
                          ? null
                          : () async {
                              setSheetState(() => isSaving = true);
                              final updatedGroup = _group.copyWith(
                                name: nameController.text.trim(),
                                topic: topicController.text.trim(),
                                schedule: scheduleController.text.trim(),
                                description: descriptionController.text.trim(),
                                allowMemberMessages: allowMessages,
                                isPrivate: isPrivate,
                                requireJoinApproval: requireApproval,
                              );
                              try {
                                await _service.updateGroup(updatedGroup);
                                if (!mounted) return;
                                setState(() => _group = updatedGroup);
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                              } catch (error) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(this.context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Could not save settings: $error',
                                    ),
                                  ),
                                );
                              } finally {
                                if (sheetContext.mounted) {
                                  setSheetState(() => isSaving = false);
                                }
                              }
                            },
                      icon: isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: const Text('Save Settings'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: _group.name,
      actions: [
        if (_isAdmin)
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: _showGroupSettings,
          ),
        if (_isMember)
          IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () => _showGroupInfo()),
        if (!_isMember)
          TextButton(
              onPressed: _isPending ? null : _toggleMembership,
              child: Text(_isPending ? 'REQUESTED' : 'JOIN',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.primary))),
      ],
      body: Column(
        children: [
          // Removed 'shape' parameter which caused build error
          AppCard(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  const Icon(Icons.topic, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(_group.topic,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  const Icon(Icons.schedule, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(_group.schedule),
                ],
              ),
            ),
          ),

          // Chat Area
          Expanded(
            child: _isMember
                ? StreamBuilder<List<GroupMessage>>(
                    stream: _messagesStream,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final msgs = snapshot.data!;
                      return ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: msgs.length,
                        itemBuilder: (context, index) {
                          return _buildMessageBubble(msgs[index]);
                        },
                      );
                    },
                  )
                : _isPending
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.hourglass_top_outlined,
                                size: 48,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Your request is waiting for a group admin.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.lock_outline,
                                size: 48, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text(
                                'Join this group to participate in discussions.'),
                            const SizedBox(height: 16),
                            ElevatedButton(
                                onPressed: _toggleMembership,
                                child: const Text('Join Group')),
                          ],
                        ),
                      ),
          ),

          if (_isMember)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                        blurRadius: 2,
                        color: Theme.of(context)
                            .shadowColor
                            .withValues(alpha: 0.1))
                  ]),
              child: Row(
                children: [
                  Expanded(
                    child: _canSendMessages
                        ? AppTextField(
                            controller: _msgController,
                            hint: 'Type a message...',
                          )
                        : const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              'Only group admins can send messages right now.',
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.send,
                            color: Theme.of(context).colorScheme.primary),
                    onPressed: _canSendMessages ? _sendMessage : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(GroupMessage msg) {
    final isMe = msg.senderId == _currentUid;
    final theme = Theme.of(context);
    final bubbleColor = isMe
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor =
        isMe ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    final metaColor = isMe
        ? theme.colorScheme.onPrimary.withValues(alpha: 0.78)
        : theme.colorScheme.onSurfaceVariant;
    final avatar = CircleAvatar(
      radius: 16,
      backgroundImage: msg.senderPhotoUrl.isNotEmpty
          ? NetworkImage(msg.senderPhotoUrl)
          : null,
      child: msg.senderPhotoUrl.isEmpty
          ? Text(_initialFor(msg.senderName),
              style: const TextStyle(fontSize: 12))
          : null,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[avatar, const SizedBox(width: 8)],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomRight: isMe ? const Radius.circular(0) : null,
                  bottomLeft: !isMe ? const Radius.circular(0) : null,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    msg.senderName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: metaColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(msg.text, style: TextStyle(color: textColor)),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MMM d, yyyy, h:mm a').format(msg.timestamp),
                    style: TextStyle(fontSize: 9, color: metaColor),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[const SizedBox(width: 8), avatar],
        ],
      ),
    );
  }

  Future<void> _showGroupMembers() async {
    final userIds = <String>{
      _group.leaderId,
      ..._group.adminIds,
      ..._group.memberIds,
      ..._group.pendingMemberIds,
    }.where((id) => id.trim().isNotEmpty).toList();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return FutureBuilder<List<UserProfile>>(
              future: _service.fetchGroupMembers(userIds),
              builder: (context, snapshot) {
                final members = snapshot.data ?? const <UserProfile>[];
                final byId = {for (final member in members) member.uid: member};
                final pendingMembers = _group.pendingMemberIds
                    .map((id) => byId[id])
                    .whereType<UserProfile>()
                    .toList();
                final activeMembers = _group.memberIds
                    .map((id) => byId[id])
                    .whereType<UserProfile>()
                    .toList();

                return ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Group Members',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      if (pendingMembers.isNotEmpty) ...[
                        _groupSectionTitle(context, 'Pending requests'),
                        ...pendingMembers.map(
                          (member) => _groupMemberTile(
                            member,
                            subtitle: 'Waiting for approval',
                            trailing: FilledButton(
                              onPressed: () => _approveMember(member.uid),
                              child: const Text('Approve'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      _groupSectionTitle(context, 'Active members'),
                      if (activeMembers.isEmpty)
                        const Text('No active members found.')
                      else
                        ...activeMembers.map((member) {
                          final isLeader = member.uid == _group.leaderId;
                          final isAdmin = _group.adminIds.contains(member.uid);
                          return _groupMemberTile(
                            member,
                            subtitle: isLeader
                                ? 'Leader'
                                : isAdmin
                                    ? 'Group admin'
                                    : 'Member',
                            trailing: isLeader
                                ? null
                                : TextButton(
                                    onPressed: () =>
                                        _setGroupAdmin(member.uid, !isAdmin),
                                    child: Text(
                                      isAdmin ? 'Remove Admin' : 'Make Admin',
                                    ),
                                  ),
                          );
                        }),
                    ],
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _groupSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(fontWeight: FontWeight.w900),
      ),
    );
  }

  Widget _groupMemberTile(
    UserProfile member, {
    required String subtitle,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundImage:
            member.photoUrl.isNotEmpty ? NetworkImage(member.photoUrl) : null,
        child:
            member.photoUrl.isEmpty ? Text(_initialFor(member.fullName)) : null,
      ),
      title: Text(member.fullName.isEmpty ? member.email : member.fullName),
      subtitle: Text(subtitle),
      trailing: trailing,
    );
  }

  String _initialFor(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed[0].toUpperCase();
  }

  void _showGroupInfo() {
    showModalBottomSheet(
        context: context,
        builder: (context) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_group.name,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(_group.description),
                const SizedBox(height: 16),
                Text('Leader: ${_group.leaderName}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('${_group.memberIds.length} active members'),
                if (_group.pendingMemberIds.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('${_group.pendingMemberIds.length} pending requests'),
                ],
                const SizedBox(height: 24),
                if (_isAdmin)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showGroupMembers();
                      },
                      icon: const Icon(Icons.manage_accounts_outlined),
                      label: const Text('Manage Members'),
                    ),
                  ),
                if (_isMember && _group.leaderId != _currentUid) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red),
                        onPressed: () {
                          Navigator.pop(context);
                          _toggleMembership();
                        },
                        child: const Text('Leave Group')),
                  ),
                ],
              ],
            ),
          );
        });
  }
}
