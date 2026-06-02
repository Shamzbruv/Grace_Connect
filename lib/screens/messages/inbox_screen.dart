import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/direct_conversation.dart';
import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/direct_message_service.dart';
import '../../services/user_service.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_loader.dart';
import '../../widgets/ui/app_scaffold.dart';
import 'message_thread_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final DirectMessageService _messageService = DirectMessageService();
  final UserService _userService = UserService();

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
      floatingActionButton: FloatingActionButton(
        onPressed: _openMemberPicker,
        child: const Icon(Icons.edit_outlined),
      ),
      body: currentUser == null
          ? const Center(child: AppLoader())
          : StreamBuilder<List<DirectConversation>>(
              stream: _messageService.watchConversations(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Could not load inbox: ${snapshot.error}'),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: AppLoader());
                }

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
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No messages yet',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _openMemberPicker,
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Start a Message'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: conversations.length,
                  itemBuilder: (context, index) {
                    return _ConversationTile(
                      conversation: conversations[index],
                      currentUser: currentUser,
                      userService: _userService,
                      messageService: _messageService,
                    );
                  },
                );
              },
            ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.currentUser,
    required this.userService,
    required this.messageService,
  });

  final DirectConversation conversation;
  final UserProfile currentUser;
  final UserService userService;
  final DirectMessageService messageService;

  @override
  Widget build(BuildContext context) {
    final otherUserId = conversation.otherMemberId(currentUser.uid);

    return FutureBuilder<UserProfile?>(
      future: userService.getUserProfile(otherUserId),
      builder: (context, snapshot) {
        final otherUser = snapshot.data;
        final displayName = otherUser?.fullName.isNotEmpty == true
            ? otherUser!.fullName
            : 'Member';
        final lastMessage = conversation.lastMessage?.trim();
        final timestamp = conversation.lastMessageAt;
        if (conversation.lastSenderId != currentUser.uid) {
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
                        : 'New message',
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
                          : Text(
                              DateFormat.MMMd().format(timestamp),
                              style: Theme.of(context).textTheme.bodySmall,
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
      final results = await _userService.searchMembers(
        cleanQuery,
        widget.currentUser.churchId,
      );
      if (!mounted) return;
      setState(() {
        _results = results
            .where((member) =>
                member.uid != widget.currentUser.uid && member.allowMessages)
            .toList();
      });
    } finally {
      if (mounted) setState(() => _isSearching = false);
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
              hintText: 'Search members',
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
                  subtitle: Text(member.email),
                  onTap: () => widget.onSelected(member),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
