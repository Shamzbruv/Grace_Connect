import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../models/reel.dart';

/// Comments, loaded only when opened.
///
/// The feed carries a count and nothing else -- pulling comment bodies with
/// every reel would multiply the feed payload for content most viewers never
/// open. Paging is keyset on created_at so a busy thread does not shift rows
/// under the reader, and there is no realtime subscription.
Future<void> showReelComments(BuildContext context, Reel reel) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ReelCommentsSheet(reel: reel),
  );
}

class _ReelCommentsSheet extends StatefulWidget {
  const _ReelCommentsSheet({required this.reel});

  final Reel reel;

  @override
  State<_ReelCommentsSheet> createState() => _ReelCommentsSheetState();
}

class _ReelCommentsSheetState extends State<_ReelCommentsSheet> {
  final SupabaseClient _client = Supabase.instance.client;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();

  final List<Map<String, dynamic>> _comments = [];
  DateTime? _cursor;
  bool _loading = true;
  bool _sending = false;
  bool _exhausted = false;
  String? _replyToId;
  String? _replyToName;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_exhausted || _sending) return;
    try {
      var query = _client
          .from('reel_comments')
          .select('id, reel_id, author_id, body, parent_comment_id, created_at')
          .eq('reel_id', widget.reel.id)
          .eq('status', 'active');
      if (_cursor != null) {
        query = query.lt('created_at', _cursor!.toIso8601String());
      }
      final rows = await query.order('created_at', ascending: false).limit(20);
      if (!mounted) return;
      final fetched = List<Map<String, dynamic>>.from(rows);
      setState(() {
        _comments.addAll(fetched);
        _loading = false;
        _exhausted = fetched.length < 20;
        if (fetched.isNotEmpty) {
          _cursor = DateTime.tryParse(fetched.last['created_at'].toString());
        }
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final inserted = await _client
          .from('reel_comments')
          .insert({
            'reel_id': widget.reel.id,
            'body': body,
            if (_replyToId != null) 'parent_comment_id': _replyToId,
          })
          .select('id, reel_id, author_id, body, parent_comment_id, created_at')
          .single();
      if (!mounted) return;
      setState(() {
        _comments.insert(0, Map<String, dynamic>.from(inserted));
        _input.clear();
        _replyToId = null;
        _replyToName = null;
        _sending = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That comment could not be posted.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewerId = _client.auth.currentUser?.id;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, controller) => Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                widget.reel.commentCount > 0
                    ? '${widget.reel.commentCount} comments'
                    : 'Comments',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _comments.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('No comments yet. Be the first.',
                                style: theme.textTheme.bodyMedium),
                          ),
                        )
                      : ListView.builder(
                          controller: controller,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _comments.length,
                          itemBuilder: (context, index) {
                            final comment = _comments[index];
                            final isReply = comment['parent_comment_id'] != null;
                            final mine = comment['author_id'] == viewerId;
                            final created = DateTime.tryParse(
                                comment['created_at']?.toString() ?? '');
                            return Padding(
                              padding: EdgeInsets.fromLTRB(
                                  isReply ? 30 : 0, 6, 0, 6),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(mine ? 'You' : 'Member',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700)),
                                      const SizedBox(width: 8),
                                      if (created != null)
                                        Text(timeago.format(created),
                                            style: theme.textTheme.bodySmall),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(comment['body']?.toString() ?? ''),
                                  if (!isReply)
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        padding: EdgeInsets.zero,
                                        minimumSize: const Size(0, 28),
                                        tapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                      ),
                                      onPressed: () => setState(() {
                                        _replyToId = comment['id']?.toString();
                                        _replyToName = mine ? 'your comment' : 'a comment';
                                      }),
                                      child: const Text('Reply'),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
            ),
            if (_replyToName != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(child: Text('Replying to $_replyToName',
                        style: theme.textTheme.bodySmall)),
                    TextButton(
                      onPressed: () => setState(() {
                        _replyToId = null;
                        _replyToName = null;
                      }),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        maxLength: 1000,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: 'Add a comment',
                          counterText: '',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
