import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/direct_conversation.dart';
import '../../models/direct_message_request.dart';
import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/direct_message_service.dart';
import '../../services/user_service.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_loader.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/message_request_composer.dart';
import 'message_thread_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    this.initialTab = 0,
  }) : assert(initialTab == 0 || initialTab == 1);

  final int initialTab;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final DirectMessageService _messageService = DirectMessageService();

  @override
  void initState() {
    super.initState();
    unawaited(_messageService.cleanupVanishingContent());
  }

  Future<void> _openMemberPicker() async {
    final currentUser = context.read<UserRoleProvider>().userProfile;
    if (currentUser == null) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MemberMessagePicker(
        currentUser: currentUser,
        onSelected: (member) async {
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);

          try {
            final conversation = await _messageService.getOrCreateConversation(
              currentUser: currentUser,
              otherUser: member,
            );
            if (!mounted) return;
            navigator.pop();
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MessageThreadScreen(
                  conversation: conversation,
                  otherUser: member,
                ),
              ),
            );
          } catch (error) {
            if (!mounted) return;
            if (_messageService.isMessageRequestRequiredError(error)) {
              navigator.pop();
              await showMessageRequestComposer(
                context,
                recipient: member,
                messageService: _messageService,
              );
              return;
            }
            messenger.showSnackBar(
              SnackBar(content: Text('Could not start message: $error')),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = context.watch<UserRoleProvider>().userProfile;

    return AppScaffold(
      title: 'Inbox',
      actions: [
        IconButton(
          tooltip: 'New message',
          icon: const Icon(Icons.edit_square),
          onPressed: _openMemberPicker,
        ),
      ],
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'grace_rooms_fab',
            tooltip: 'Grace Rooms',
            onPressed: () => Navigator.of(context).pushNamed('/grace_rooms'),
            child: const Icon(Icons.forum_outlined),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'new_message_fab',
            tooltip: 'New message',
            onPressed: _openMemberPicker,
            child: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: currentUser == null
          ? const Center(child: AppLoader())
          : DefaultTabController(
              length: 2,
              initialIndex: widget.initialTab,
              child: Column(
                children: [
                  StreamBuilder<int>(
                    stream: _messageService.watchPendingMessageRequestCount(),
                    builder: (context, snapshot) {
                      final pendingCount = snapshot.data ?? 0;
                      return TabBar(
                        tabs: [
                          const Tab(
                            icon: Icon(Icons.chat_bubble_outline),
                            text: 'Messages',
                          ),
                          Tab(
                            icon: Badge(
                              isLabelVisible: pendingCount > 0,
                              label: Text('$pendingCount'),
                              child:
                                  const Icon(Icons.mark_email_unread_outlined),
                            ),
                            text: 'Requests',
                          ),
                        ],
                      );
                    },
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _MessagesPane(
                          currentUser: currentUser,
                          messageService: _messageService,
                          onStartMessage: _openMemberPicker,
                        ),
                        _MessageRequestsPane(
                          messageService: _messageService,
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

class _MessagesPane extends StatelessWidget {
  const _MessagesPane({
    required this.currentUser,
    required this.messageService,
    required this.onStartMessage,
  });

  final UserProfile currentUser;
  final DirectMessageService messageService;
  final VoidCallback onStartMessage;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DirectConversation>>(
      stream: messageService.watchConversations(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Could not load inbox: ${snapshot.error}'),
            ),
          );
        }
        if (!snapshot.hasData) return const Center(child: AppLoader());

        final conversations = snapshot.data!;
        if (conversations.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inbox_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No messages yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onStartMessage,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Start a Message'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/grace_rooms'),
                    icon: const Icon(Icons.forum_outlined),
                    label: const Text('Open Grace Rooms'),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          itemCount: conversations.length,
          itemBuilder: (context, index) => _ConversationTile(
            conversation: conversations[index],
            currentUser: currentUser,
            messageService: messageService,
          ),
        );
      },
    );
  }
}

class _MessageRequestsPane extends StatelessWidget {
  const _MessageRequestsPane({
    required this.messageService,
  });

  final DirectMessageService messageService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DirectMessageRequest>>(
      stream: messageService.watchMessageRequests(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load message requests: ${snapshot.error}',
              ),
            ),
          );
        }
        if (!snapshot.hasData) return const Center(child: AppLoader());
        final requests = snapshot.data!;
        if (requests.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.mark_email_read_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'No message requests',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'People outside your church must ask before starting a private conversation.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
          itemCount: requests.length,
          itemBuilder: (context, index) => _MessageRequestTile(
            request: requests[index],
            messageService: messageService,
          ),
        );
      },
    );
  }
}

class _MessageRequestTile extends StatefulWidget {
  const _MessageRequestTile({
    required this.request,
    required this.messageService,
  });

  final DirectMessageRequest request;
  final DirectMessageService messageService;

  @override
  State<_MessageRequestTile> createState() => _MessageRequestTileState();
}

class _MessageRequestTileState extends State<_MessageRequestTile> {
  bool _saving = false;

  Future<void> _respond(bool accepted) async {
    final responseController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(accepted ? 'Accept request?' : 'Decline request?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              accepted
                  ? 'Their first message will be delivered and a private conversation will open.'
                  : 'They will be notified and cannot request you again for 30 days.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: responseController,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: accepted ? 'Optional response' : 'Optional reason',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(accepted ? 'Accept' : 'Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      responseController.dispose();
      return;
    }

    setState(() => _saving = true);
    try {
      await widget.messageService.respondToMessageRequest(
        request: widget.request,
        accepted: accepted,
        responseMessage: responseController.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accepted
                ? 'Request accepted. Their first message is now in Messages.'
                : 'Request declined. The 30-day wait is now active.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not respond: $error')),
      );
    } finally {
      responseController.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancel() async {
    setState(() => _saving = true);
    try {
      await widget.messageService.cancelMessageRequest(widget.request);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not cancel request: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final authUserId = widget.messageService.currentUserId;
    final incoming = request.isIncomingFor(authUserId);
    final theme = Theme.of(context);
    return FutureBuilder<UserProfile?>(
      future: widget.messageService.getMessageRequestPeer(request),
      builder: (context, snapshot) {
        final peer = snapshot.data;
        final name = peer?.fullName.trim().isNotEmpty == true
            ? peer!.fullName.trim()
            : 'Grace Connect member';
        final statusColor = switch (request.status) {
          'accepted' => Colors.green,
          'denied' => theme.colorScheme.error,
          'cancelled' => theme.colorScheme.outline,
          _ => theme.colorScheme.primary,
        };

        return AppCard(
          margin: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundImage: peer?.photoUrl.isNotEmpty == true
                        ? NetworkImage(peer!.photoUrl)
                        : null,
                    child: peer?.photoUrl.isNotEmpty == true
                        ? null
                        : Text(name.characters.first.toUpperCase()),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          incoming ? name : 'To $name',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          DateFormat('MMM d, yyyy · h:mm a')
                              .format(request.createdAt),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      request.status.toUpperCase(),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Why they want to message',
                  style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(request.reason),
              const SizedBox(height: 12),
              Text('First message', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              Text(request.intendedMessage),
              if (request.responseMessage?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                Text('Response', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(request.responseMessage!),
              ],
              if (!incoming && request.retryAvailableAt != null) ...[
                const SizedBox(height: 10),
                Text(
                  'You can request again after ${DateFormat('MMM d, yyyy · h:mm a').format(request.retryAvailableAt!)}.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (request.isPending) ...[
                const SizedBox(height: 16),
                if (incoming)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : () => _respond(false),
                          child: const Text('Decline'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : () => _respond(true),
                          child: const Text('Accept'),
                        ),
                      ),
                    ],
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _cancel,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('Cancel request'),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.currentUser,
    required this.messageService,
  });

  final DirectConversation conversation;
  final UserProfile currentUser;
  final DirectMessageService messageService;

  @override
  Widget build(BuildContext context) {
    final viewerId = messageService.currentUserId.isNotEmpty
        ? messageService.currentUserId
        : currentUser.uid;
    return FutureBuilder<UserProfile?>(
      future: messageService.getConversationPeer(
        conversation,
        viewerId,
      ),
      builder: (context, snapshot) {
        final fallbackPeerId = conversation.otherMemberId(viewerId);
        final otherUser = snapshot.data ??
            (fallbackPeerId.isEmpty
                ? null
                : UserProfile(
                    uid: fallbackPeerId,
                    email: '',
                    fullName: 'Member',
                    phoneNumber: '',
                    placeId: conversation.churchId,
                    placeName: '',
                    roles: const ['Member'],
                    joinDate: DateTime.now(),
                    allowMessages: true,
                  ));
        final displayName = otherUser?.fullName.isNotEmpty == true
            ? otherUser!.fullName
            : 'Member';
        final lastMessage = conversation.lastMessage?.trim();
        final timestamp = conversation.lastMessageAt;
        if (conversation.lastSenderId != viewerId) {
          messageService.markConversationDelivered(conversation.id);
        }

        return StreamBuilder<int>(
          stream: messageService.watchUnreadCountForConversation(
            conversation.id,
          ),
          builder: (context, unreadSnapshot) {
            final unreadCount = unreadSnapshot.data ?? 0;
            final hasUnread = unreadCount > 0;
            final theme = Theme.of(context);

            return AppCard(
              margin: const EdgeInsets.only(bottom: 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: hasUnread
                      ? theme.colorScheme.primaryContainer
                          .withValues(alpha: 0.28)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: hasUnread
                      ? [
                          BoxShadow(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.16),
                            blurRadius: 22,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      CircleAvatar(
                        backgroundImage: otherUser?.photoUrl.isNotEmpty == true
                            ? NetworkImage(otherUser!.photoUrl)
                            : null,
                        child: otherUser?.photoUrl.isNotEmpty == true
                            ? null
                            : Text(displayName.characters.first.toUpperCase()),
                      ),
                      if (hasUnread)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: theme.colorScheme.surface,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  title: Text(
                    displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: hasUnread ? FontWeight.w900 : FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    lastMessage?.isNotEmpty == true
                        ? lastMessage!
                        : 'No visible messages',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: hasUnread ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasUnread)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            unreadCount > 9 ? '9+' : '$unreadCount',
                            style: TextStyle(
                              color: theme.colorScheme.onPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      timestamp == null
                          ? const Icon(Icons.chevron_right)
                          : ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 88),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    DateFormat('MMM d, yyyy')
                                        .format(timestamp.toLocal()),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                  Text(
                                    DateFormat('h:mm a')
                                        .format(timestamp.toLocal()),
                                    maxLines: 1,
                                    textAlign: TextAlign.right,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                      PopupMenuButton<String>(
                        tooltip: 'Chat options',
                        onSelected: (value) async {
                          if (value == 'delete') {
                            await messageService
                                .deleteConversationForMe(conversation);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline),
                                SizedBox(width: 8),
                                Text('Delete chat'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  onTap: otherUser == null
                      ? null
                      : () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => MessageThreadScreen(
                                conversation: conversation,
                                otherUser: otherUser,
                              ),
                            ),
                          );
                        },
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _MemberMessagePicker extends StatefulWidget {
  const _MemberMessagePicker({
    required this.currentUser,
    required this.onSelected,
  });

  final UserProfile currentUser;
  final Future<void> Function(UserProfile member) onSelected;

  @override
  State<_MemberMessagePicker> createState() => _MemberMessagePickerState();
}

class _MemberMessagePickerState extends State<_MemberMessagePicker> {
  final TextEditingController _searchController = TextEditingController();
  final UserService _userService = UserService();
  List<UserProfile> _results = [];
  bool _isSearching = false;
  String? _startingMemberId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.length < 2) {
      setState(() => _results = []);
      return;
    }

    setState(() => _isSearching = true);
    try {
      final results = await _userService.searchPeople(cleanQuery);
      if (!mounted) return;
      setState(() {
        _results = results.where((member) {
          final sameChurch = widget.currentUser.churchId.trim().isNotEmpty &&
              member.churchId == widget.currentUser.churchId;
          return member.uid != widget.currentUser.uid &&
              (sameChurch || member.allowMessages);
        }).toList()
          ..sort((a, b) {
            final aSameChurch = a.churchId == widget.currentUser.churchId;
            final bSameChurch = b.churchId == widget.currentUser.churchId;
            if (aSameChurch != bSameChurch) return aSameChurch ? -1 : 1;
            return a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase());
          });
      });
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _selectMember(UserProfile member) async {
    if (_startingMemberId != null) return;
    setState(() => _startingMemberId = member.uid);
    try {
      await widget.onSelected(member);
    } finally {
      if (mounted) setState(() => _startingMemberId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'New Message',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search people',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: _search,
          ),
          const SizedBox(height: 12),
          if (_isSearching) const LinearProgressIndicator(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final member = _results[index];
                final isStarting = _startingMemberId == member.uid;
                final displayName =
                    member.fullName.isNotEmpty ? member.fullName : member.email;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: member.photoUrl.isNotEmpty
                        ? NetworkImage(member.photoUrl)
                        : null,
                    child: member.photoUrl.isEmpty
                        ? Text(displayName.characters.first.toUpperCase())
                        : null,
                  ),
                  title: Text(displayName),
                  subtitle: Text(
                    [
                      if (member.placeName.trim().isNotEmpty)
                        member.placeName.trim(),
                      member.email,
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isStarting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  enabled: _startingMemberId == null || isStarting,
                  onTap: isStarting ? null : () => _selectMember(member),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
