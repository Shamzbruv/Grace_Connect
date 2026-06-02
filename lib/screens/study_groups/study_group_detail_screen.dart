import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../providers/user_role_provider.dart';
import '../../services/study_group_service.dart';
import '../../models/study_group_model.dart';
import '../../models/group_message_model.dart';
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
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _currentUid = Supabase.instance.client.auth.currentUser?.id ?? '';
    _isMember = _group.memberIds.contains(_currentUid);
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
        await _service.joinGroup(_group.id, _currentUid);
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
    } else if (!updatedMembers.contains(_currentUid)) {
      updatedMembers.add(_currentUid);
    }

    setState(() {
      _isMember = !_isMember;
      _group = _group.copyWith(memberIds: updatedMembers);
    });
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
              onPressed: _toggleMembership,
              child: Text('JOIN',
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
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isMe
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16).copyWith(
            bottomRight: isMe ? const Radius.circular(0) : null,
            bottomLeft: !isMe ? const Radius.circular(0) : null,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMe) ...[
              Text(msg.senderName,
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 2),
            ],
            Text(msg.text,
                style: TextStyle(
                    color: isMe
                        ? Theme.of(context).colorScheme.onPrimary
                        : Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 2),
            Text(DateFormat('h:mm a').format(msg.timestamp),
                style: TextStyle(
                    fontSize: 8,
                    color: isMe
                        ? Theme.of(context)
                            .colorScheme
                            .onPrimary
                            .withValues(alpha: 0.7)
                        : Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  void _showGroupInfo() {
    showModalBottomSheet(
        context: context,
        builder: (context) {
          return Container(
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
                Text('${_group.memberIds.length} members'),
                const SizedBox(height: 24),
                if (_isMember)
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
                  )
              ],
            ),
          );
        });
  }
}
