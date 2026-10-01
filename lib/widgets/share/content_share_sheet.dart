import 'package:flutter/material.dart';
import '../../models/post.dart';
import '../../models/reel.dart';
import '../../models/direct_conversation.dart';
import '../../models/user_profile.dart';
import '../../services/content_share_service.dart';
import '../../services/direct_message_service.dart';
import '../../services/user_service.dart';

Future<void> showContentShareSheet(BuildContext context,
        {Reel? reel, Post? post}) =>
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _ContentShareSheet(reel: reel, post: post));

class _ContentShareSheet extends StatefulWidget {
  const _ContentShareSheet({this.reel, this.post});
  final Reel? reel;
  final Post? post;
  @override
  State<_ContentShareSheet> createState() => _ContentShareSheetState();
}

class _ContentShareSheetState extends State<_ContentShareSheet> {
  final _messages = DirectMessageService();
  late Future<List<DirectConversation>> _conversations =
      _messages.fetchConversations();
  final Map<String, Future<UserProfile?>> _profiles = {};
  bool _sending = false;
  String? _error;

  Future<void> _send(DirectConversation conversation) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _messages.sendMessage(
        conversationId: conversation.id,
        recipientUserId: conversation.otherMemberId(_messages.currentUserId),
        text: widget.reel != null ? 'Shared a reel' : 'Shared a post',
        sharedContent: {
          'kind': widget.reel != null ? 'reel' : 'post',
          'id': widget.reel?.id ?? widget.post!.id
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sent to your conversation.')));
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Could not send. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canExport = widget.reel != null
        ? widget.reel!.visibility == ReelVisibility.public
        : widget.post!.visibleToAllChurches ||
            ['global', 'public', 'discover'].contains(widget.post!.scope);
    return SafeArea(
        child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .65,
            child: Column(children: [
              Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('Share ${widget.reel != null ? 'reel' : 'post'}',
                      style: Theme.of(context).textTheme.titleLarge)),
              if (_sending) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.all(12), child: Text(_error!)),
              if (canExport)
                ListTile(
                    leading: const Icon(Icons.ios_share),
                    title: const Text('Share to another app'),
                    subtitle: const Text(
                        'Send the original format • videos include a watermark'),
                    onTap: _sending
                        ? null
                        : () async {
                            setState(() => _sending = true);
                            await ContentShareService.shareExternal(context,
                                reel: widget.reel, post: widget.post);
                            if (mounted) setState(() => _sending = false);
                          }),
              const Divider(),
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text('Send in Grace Connect')),
              Expanded(
                  child: FutureBuilder<List<DirectConversation>>(
                      future: _conversations,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                              child: TextButton(
                                  onPressed: () => setState(() =>
                                      _conversations =
                                          _messages.fetchConversations()),
                                  child: const Text('Retry conversations')));
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final conversations = snapshot.data!;
                        if (conversations.isEmpty) {
                          return const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                  'Your conversations will appear here. Open someone’s profile to start a conversation.'));
                        }
                        return ListView.builder(
                            itemCount: conversations.length,
                            itemBuilder: (context, index) {
                              final conversation = conversations[index];
                              final peer = conversation
                                  .otherMemberId(_messages.currentUserId);
                              return FutureBuilder<UserProfile?>(
                                  future: _profiles.putIfAbsent(peer,
                                      () => UserService().getUserProfile(peer)),
                                  builder: (context, snapshot) => ListTile(
                                        leading: const CircleAvatar(
                                            child: Icon(Icons.person_outline)),
                                        title: Text(snapshot.data?.fullName ??
                                            'Conversation'),
                                        subtitle: Text(
                                            conversation.lastMessage ??
                                                'Send to this conversation',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                        trailing: IconButton(
                                            tooltip: 'Send',
                                            onPressed:
                                                _sending || !snapshot.hasData
                                                    ? null
                                                    : () => _send(conversation),
                                            icon:
                                                const Icon(Icons.send_rounded)),
                                      ));
                            });
                      })),
            ])));
  }
}
