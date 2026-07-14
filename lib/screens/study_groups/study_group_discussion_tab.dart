import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/group_message_model.dart';
import '../../models/study_group_model.dart';
import '../../providers/user_role_provider.dart';
import '../../services/study_group_access_service.dart';
import '../../services/study_group_service.dart';
import '../../widgets/ui/app_text_field.dart';

class StudyGroupDiscussionTab extends StatefulWidget {
  final StudyGroup group;
  final StudyGroupAccess access;
  final bool isMember;
  final String currentUserId;
  final StudyGroupService service;

  const StudyGroupDiscussionTab({
    super.key,
    required this.group,
    required this.access,
    required this.isMember,
    required this.currentUserId,
    required this.service,
  });

  @override
  State<StudyGroupDiscussionTab> createState() =>
      _StudyGroupDiscussionTabState();
}

class _StudyGroupDiscussionTabState extends State<StudyGroupDiscussionTab> {
  final TextEditingController _controller = TextEditingController();
  bool _isSending = false;

  bool get _canSend =>
      widget.isMember &&
      (widget.group.allowMemberMessages || widget.access.canEditGroup);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_canSend || _controller.text.trim().isEmpty || _isSending) return;
    final user = Supabase.instance.client.auth.currentUser;
    final profile =
        Provider.of<UserRoleProvider>(context, listen: false).userProfile;
    if (user == null) return;

    setState(() => _isSending = true);
    try {
      await widget.service.sendMessage(
        widget.group.id,
        user.id,
        profile?.fullName.isNotEmpty == true
            ? profile!.fullName
            : user.userMetadata?['full_name'] ?? 'Member',
        _controller.text.trim(),
        senderPhotoUrl: profile?.photoUrl ?? '',
      );
      _controller.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send message: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isMember) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            widget.group.pendingMemberIds.contains(widget.currentUserId)
                ? 'Your request is waiting for a group leader.'
                : 'Join this group to participate in discussions.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<GroupMessage>>(
            stream: widget.service.getMessages(widget.group.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final messages = snapshot.data ?? const <GroupMessage>[];
              if (messages.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      widget.access.canEditGroup
                          ? 'No discussion has started yet. Post the first question.'
                          : 'Your leader has not posted a discussion yet.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              return ListView.builder(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                itemCount: messages.length,
                itemBuilder: (context, index) =>
                    _MessageBubble(message: messages[index]),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _canSend
                      ? AppTextField(
                          controller: _controller,
                          hint: 'Share a reflection...',
                        )
                      : const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('Only group leaders can post right now.'),
                        ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _canSend ? _send : null,
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final GroupMessage message;
  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final currentUid = Supabase.instance.client.auth.currentUser?.id ?? '';
    final isMe = message.senderId == currentUid;
    final theme = Theme.of(context);
    final bubbleColor = isMe
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor =
        isMe ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;
    final metaColor = isMe
        ? theme.colorScheme.onPrimary.withValues(alpha: 0.76)
        : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMe) ...[
            _avatar(),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(16).copyWith(
                  bottomLeft: !isMe ? const Radius.circular(4) : null,
                  bottomRight: isMe ? const Radius.circular(4) : null,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.senderName,
                    style: TextStyle(
                      color: metaColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(message.text, style: TextStyle(color: textColor)),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('MMM d, h:mm a').format(message.timestamp),
                    style: TextStyle(color: metaColor, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            _avatar(),
          ],
        ],
      ),
    );
  }

  Widget _avatar() {
    return CircleAvatar(
      radius: 16,
      backgroundImage: message.senderPhotoUrl.isNotEmpty
          ? NetworkImage(message.senderPhotoUrl)
          : null,
      child: message.senderPhotoUrl.isEmpty
          ? Text(message.senderName.trim().isEmpty
              ? '?'
              : message.senderName.trim()[0].toUpperCase())
          : null,
    );
  }
}
