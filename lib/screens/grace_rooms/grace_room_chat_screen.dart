import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/bible_service.dart';
import '../../services/grace_rooms_service.dart';
import '../../widgets/ui/app_scaffold.dart';

class GraceRoomChatScreen extends StatefulWidget {
  const GraceRoomChatScreen({
    super.key,
    required this.roomId,
  });

  final String roomId;

  @override
  State<GraceRoomChatScreen> createState() => _GraceRoomChatScreenState();
}

class _GraceRoomChatScreenState extends State<GraceRoomChatScreen>
    with WidgetsBindingObserver {
  static const _heartbeatInterval = Duration(seconds: 45);
  final GraceRoomsService _service = GraceRoomsService();
  final TextEditingController _messageController = TextEditingController();
  late Future<GraceRoom?> _roomFuture;
  List<GraceRoomMessage> _fallbackMessages = const [];
  Timer? _presenceTimer;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _roomFuture = _service.fetchRoom(widget.roomId);
    _joinAndPrime();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    unawaited(_service.leaveRoom(widget.roomId));
    _messageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_touchPresence());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _presenceTimer?.cancel();
      unawaited(_service.leaveRoom(widget.roomId));
    }
  }

  Future<void> _joinAndPrime() async {
    await _touchPresence();
    final messages = await _service.fetchMessages(widget.roomId);
    if (mounted) setState(() => _fallbackMessages = messages);
  }

  Future<void> _touchPresence() async {
    await _sendPresenceHeartbeat();
    if (!mounted) return;
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(
      _heartbeatInterval,
      (_) => unawaited(_sendPresenceHeartbeat()),
    );
  }

  Future<void> _sendPresenceHeartbeat() async {
    try {
      await _service.heartbeatRoom(widget.roomId);
    } catch (error) {
      debugPrint('Could not refresh Grace Room presence: $error');
    }
  }

  Future<void> _sendMessage() async {
    if (_sending) return;
    final body = _messageController.text.trim();
    if (body.isEmpty) return;

    setState(() => _sending = true);
    try {
      await _service.sendMessage(roomId: widget.roomId, body: body);
      _messageController.clear();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send message: $error')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<GraceRoom?>(
      future: _roomFuture,
      builder: (context, roomSnapshot) {
        final room = roomSnapshot.data;
        return AppScaffold(
          title: room?.title ?? 'Grace Room',
          body: Column(
            children: [
              if (room != null)
                StreamBuilder<GraceRoom?>(
                  stream: _service.watchRoom(widget.roomId),
                  initialData: room,
                  builder: (context, snapshot) =>
                      _RoomHeader(room: snapshot.data ?? room),
                ),
              Expanded(
                child: StreamBuilder<List<GraceRoomMessage>>(
                  stream: _service.watchMessages(widget.roomId),
                  initialData: _fallbackMessages,
                  builder: (context, snapshot) {
                    final messages = snapshot.data ?? _fallbackMessages;
                    final currentUserId =
                        Supabase.instance.client.auth.currentUser?.id;
                    final notice = snapshot.hasError && messages.isEmpty
                        ? 'Room messages are not available yet.'
                        : messages.isEmpty
                            ? 'No messages yet.'
                            : null;
                    final includeScripture = room != null;
                    final itemCount = messages.length +
                        (includeScripture ? 1 : 0) +
                        (notice == null ? 0 : 1);
                    return ListView.builder(
                      reverse: false,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                      itemCount: itemCount,
                      itemBuilder: (context, index) {
                        if (includeScripture && index == 0) {
                          return _ScriptureGreeting(
                            key: ValueKey('scripture-${room.id}'),
                            room: room,
                          );
                        }

                        final noticeIndex = includeScripture ? 1 : 0;
                        if (notice != null && index == noticeIndex) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 34),
                            child: Center(
                              child: Text(
                                notice,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          );
                        }

                        final messageIndex = index -
                            (includeScripture ? 1 : 0) -
                            (notice == null ? 0 : 1);
                        final message = messages[messageIndex];
                        final isMine = message.authorId == currentUserId;
                        return Align(
                          alignment: isMine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 420),
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: isMine
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      message.anonymousName,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(message.body),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.newline,
                          decoration: const InputDecoration(
                            hintText: 'Message anonymously',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Send',
                        onPressed: _sending ? null : _sendMessage,
                        icon: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.send_outlined),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({required this.room});

  final GraceRoom room;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.16)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            room.subtitle.isEmpty ? room.description : room.subtitle,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (room.purpose.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              room.purpose.trim(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            room.liveParticipantCount == 1
                ? '1 person live now'
                : '${room.liveParticipantCount} people live now',
            style: theme.textTheme.labelMedium?.copyWith(
              color: room.liveParticipantCount > 0 ? Colors.green : null,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Messages vanish after 24 hours.',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScriptureGreeting extends StatefulWidget {
  const _ScriptureGreeting({
    super.key,
    required this.room,
  });

  final GraceRoom room;

  @override
  State<_ScriptureGreeting> createState() => _ScriptureGreetingState();
}

class _ScriptureGreetingState extends State<_ScriptureGreeting> {
  late Future<_RoomScripture?> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadScripture();
  }

  @override
  void didUpdateWidget(covariant _ScriptureGreeting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      _future = _loadScripture();
    }
  }

  Future<_RoomScripture?> _loadScripture() async {
    final refs = widget.room.scriptureRefs;
    if (refs.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    final key = 'grace_room_last_scripture_${widget.room.id}';
    final lastRef = prefs.getString(key);
    final candidates = refs.length <= 1
        ? refs
        : refs.where((ref) => ref != lastRef).toList(growable: false);
    final selectedRef = candidates[Random().nextInt(candidates.length)];
    await prefs.setString(key, selectedRef);

    final data = await BibleService().getPassage(selectedRef);
    final text = data['text']?.toString().trim() ?? '';
    final translation = data['translation_name']?.toString() ?? 'Bible';
    return _RoomScripture(
      reference: data['reference']?.toString() ?? selectedRef,
      text: text.replaceAll(RegExp(r'\s+'), ' '),
      translation: translation,
      message: _messageForRoom(widget.room),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<_RoomScripture?>(
      future: _future,
      builder: (context, snapshot) {
        final scripture = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _ScriptureCardShell(
            child: Row(
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(
                  'Opening Scripture',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          );
        }

        if (scripture == null || scripture.text.isEmpty) {
          return _ScriptureCardShell(
            child: Text(
              _messageForRoom(widget.room),
              style: theme.textTheme.bodyMedium,
            ),
          );
        }

        return _ScriptureCardShell(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      scripture.reference,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                scripture.text,
                maxLines: 8,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(height: 1.36),
              ),
              const SizedBox(height: 12),
              Text(
                scripture.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                scripture.translation,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ScriptureCardShell extends StatelessWidget {
  const _ScriptureCardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: child,
    );
  }
}

class _RoomScripture {
  const _RoomScripture({
    required this.reference,
    required this.text,
    required this.translation,
    required this.message,
  });

  final String reference;
  final String text;
  final String translation;
  final String message;
}

String _messageForRoom(GraceRoom room) {
  return switch (room.title) {
    'The Heavy Heart' =>
      'You can move slowly here. God is near to the brokenhearted.',
    'Peace in the Storm' =>
      'Let this room begin with breath, prayer, and peace.',
    'Grief and Goodbye' => 'Your tears are not rushed here.',
    'Not Alone' => 'You are seen, and you do not have to carry this alone.',
    'Faith Under Pressure' =>
      'Honest questions can still sit in the presence of God.',
    'Wounded by Church' => 'Healing can be gentle, truthful, and protected.',
    'Marriage and Relationships' => 'Speak with patience; listen with grace.',
    'Family Matters' => 'Peace can begin with one softened answer.',
    'Freedom Journey' => 'One faithful step still matters.',
    'Grace After Failure' => 'Mercy has room for another beginning.',
    _ => 'Grace is welcome in this conversation.',
  };
}
