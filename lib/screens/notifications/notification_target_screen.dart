import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/direct_conversation.dart';
import '../../services/direct_message_service.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../grace_rooms/grace_room_chat_screen.dart';
import '../messages/message_thread_screen.dart';

/// Resolves entity ids with the signed-in client's RLS before opening a parent.
class NotificationTargetScreen extends StatefulWidget {
  const NotificationTargetScreen(
      {super.key, required this.table, required this.id});
  final String table;
  final String id;

  @override
  State<NotificationTargetScreen> createState() =>
      _NotificationTargetScreenState();
}

class _NotificationTargetScreenState extends State<NotificationTargetScreen> {
  late Future<Widget?> _destination;

  @override
  void initState() {
    super.initState();
    _destination = _load();
  }

  Future<Widget?> _load() async {
    if (!const {
          'direct_messages',
          'direct_conversations',
          'grace_room_messages',
          'events',
          'announcements',
          'notifications'
        }.contains(widget.table) ||
        widget.id.isEmpty) {
      return null;
    }
    final client = Supabase.instance.client;
    final row = await client
        .from(widget.table)
        .select()
        .eq('id', widget.id)
        .maybeSingle();
    if (row == null) return null;
    if (widget.table == 'grace_room_messages') {
      return GraceRoomChatScreen(roomId: row['room_id'].toString());
    }
    if (widget.table == 'direct_messages' ||
        widget.table == 'direct_conversations') {
      final conversationRow = widget.table == 'direct_conversations'
          ? row
          : await client
              .from('direct_conversations')
              .select()
              .eq('id', row['conversation_id'])
              .maybeSingle();
      if (conversationRow == null) return null;
      final conversation = DirectConversation.fromMap(conversationRow);
      final userId = client.auth.currentUser?.id;
      if (userId == null || conversation.isHiddenFor(userId)) return null;
      final peer = await DirectMessageService()
          .getConversationPeer(conversation, userId);
      if (peer == null) return null;
      return MessageThreadScreen(conversation: conversation, otherUser: peer);
    }
    return _NotificationContent(table: widget.table, row: row);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Widget?>(
        future: _destination,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppScaffold(
                title: 'Opening notification',
                body: Center(child: CircularProgressIndicator()));
          }
          if (snapshot.hasError) {
            return AppScaffold(
                title: 'Notification',
                body: Center(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                        'Unable to load this notification. Please try again.'),
                    TextButton(
                        onPressed: () => setState(() => _destination = _load()),
                        child: const Text('Retry')),
                  ],
                )));
          }
          return snapshot.data ??
              const AppScaffold(
                  title: 'Notification',
                  body: Center(
                    child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                            'This content is no longer available, or you no longer have access to it.')),
                  ));
        },
      );
}

class _NotificationContent extends StatelessWidget {
  const _NotificationContent({required this.table, required this.row});
  final String table;
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date =
        DateTime.tryParse((row['date'] ?? row['created_at'] ?? '').toString());
    final location = (row['location'] ?? row['location_name'] ?? '').toString();
    final link =
        Uri.tryParse((row['event_url'] ?? row['link_url'] ?? '').toString());
    return AppScaffold(
      title: table == 'events'
          ? 'Event'
          : table == 'announcements'
              ? 'Announcement'
              : 'Notification',
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Text(row['title']?.toString() ?? 'Notification',
            style: theme.textTheme.headlineSmall),
        if (date != null) ...[
          const SizedBox(height: 12),
          Text(DateFormat.yMMMd().add_jm().format(date.toLocal()),
              style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 20),
        SelectableText((row['body'] ?? row['description'] ?? '').toString(),
            style: theme.textTheme.bodyLarge),
        if (location.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(location),
        ],
        if (link != null && const {'http', 'https'}.contains(link.scheme)) ...[
          const SizedBox(height: 20),
          OutlinedButton.icon(
              onPressed: () async {
                final opened =
                    await launchUrl(link, mode: LaunchMode.externalApplication);
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('This link could not be opened.')),
                  );
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open link')),
        ],
      ]),
    );
  }
}
