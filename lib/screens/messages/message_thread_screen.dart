import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/direct_conversation.dart';
import '../../models/direct_message.dart';
import '../../models/user_profile.dart';
import '../../services/direct_message_service.dart';
import '../../services/moderation_service.dart';
import '../../widgets/ui/app_loader.dart';
import '../../widgets/ui/app_scaffold.dart';

class MessageThreadScreen extends StatefulWidget {
  const MessageThreadScreen({
    super.key,
    required this.conversation,
    required this.otherUser,
  });

  final DirectConversation conversation;
  final UserProfile otherUser;

  @override
  State<MessageThreadScreen> createState() => _MessageThreadScreenState();
}

class _MessageThreadScreenState extends State<MessageThreadScreen> {
  final DirectMessageService _messageService = DirectMessageService();
  final ModerationService _moderationService = ModerationService();
  final TextEditingController _messageController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _isSending = false;
  Uint8List? _pendingMediaBytes;
  String? _pendingMediaName;
  String? _pendingMediaType;
  String? _pendingMimeType;
  int? _pendingDurationSeconds;

  String get _currentUid => Supabase.instance.client.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_messageService.cleanupVanishingContent());
    unawaited(_messageService.markConversationRead(widget.conversation.id));
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if ((text.isEmpty && _pendingMediaBytes == null) || _isSending) return;

    setState(() => _isSending = true);
    try {
      String? mediaUrl;
      String? mediaPath;
      final mediaType = _pendingMediaType ?? 'text';
      if (_pendingMediaBytes != null) {
        final path = _chatMediaPath(mediaType);
        mediaPath = path;
        mediaUrl = await _messageService.uploadChatMediaBytes(
          _pendingMediaBytes!,
          path,
          contentType: _pendingMimeType,
        );
      }
      await _messageService.sendMessage(
        conversationId: widget.conversation.id,
        text: text,
        mediaUrl: mediaUrl,
        mediaPath: mediaPath,
        mediaType: mediaType,
        durationSeconds: _pendingDurationSeconds,
      );
      _messageController.clear();
      _clearPendingMedia();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send message: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _pickImage() async {
    final image = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (image == null) return;
    final bytes = await image.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pendingMediaBytes = bytes;
      _pendingMediaName = image.name;
      _pendingMediaType = 'image';
      _pendingMimeType = image.mimeType ?? 'image/jpeg';
      _pendingDurationSeconds = null;
    });
  }

  Future<void> _pickVideo() async {
    final video = await _imagePicker.pickVideo(source: ImageSource.gallery);
    if (video == null) return;
    final size = await video.length();
    if (size > 52428800) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video file size must be less than 50MB')),
      );
      return;
    }
    final bytes = await video.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pendingMediaBytes = bytes;
      _pendingMediaName = video.name;
      _pendingMediaType = 'video';
      _pendingMimeType = video.mimeType ?? 'video/mp4';
      _pendingDurationSeconds = null;
    });
  }

  Future<void> _pickVoiceNote() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    const maxVoiceBytes = 6 * 1024 * 1024;
    if (file.size > maxVoiceBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice notes are capped at about 2 minutes.'),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _pendingMediaBytes = bytes;
      _pendingMediaName = file.name;
      _pendingMediaType = 'voice';
      _pendingMimeType = _mimeForExtension(file.extension, 'audio/aac');
      _pendingDurationSeconds = 120;
    });
  }

  void _clearPendingMedia() {
    if (!mounted) return;
    setState(() {
      _pendingMediaBytes = null;
      _pendingMediaName = null;
      _pendingMediaType = null;
      _pendingMimeType = null;
      _pendingDurationSeconds = null;
    });
  }

  String _chatMediaPath(String mediaType) {
    final extension = _extensionForPendingMedia(mediaType);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return '${widget.conversation.churchId}/direct/${widget.conversation.id}/${timestamp}_$_currentUid.$extension';
  }

  String _extensionForPendingMedia(String mediaType) {
    final name = _pendingMediaName ?? '';
    if (name.contains('.')) {
      final extension = name.split('.').last.toLowerCase();
      if (extension.length <= 5) return extension;
    }
    return switch (mediaType) {
      'image' => 'jpg',
      'video' => 'mp4',
      'voice' => 'aac',
      _ => 'bin',
    };
  }

  String _mimeForExtension(String? extension, String fallback) {
    return switch (extension?.toLowerCase()) {
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/m4a',
      'mp4' => 'audio/mp4',
      'wav' => 'audio/wav',
      'webm' => 'audio/webm',
      _ => fallback,
    };
  }

  Future<void> _showMessageActions(DirectMessage message) async {
    final isMe = message.senderId == _currentUid;
    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete for me'),
              onTap: () => Navigator.pop(context, 'delete_me'),
            ),
            if (isMe)
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined),
                title: const Text('Delete for everyone'),
                onTap: () => Navigator.pop(context, 'delete_everyone'),
              ),
            if (!isMe) ...[
              ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: const Text('Report message'),
                onTap: () => Navigator.pop(context, 'report'),
              ),
              ListTile(
                leading: const Icon(Icons.block, color: Colors.red),
                title: Text('Block ${widget.otherUser.fullName}'),
                onTap: () => Navigator.pop(context, 'block'),
              ),
            ],
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    if (action == 'delete_me') {
      await _messageService.deleteMessageForMe(message);
    } else if (action == 'delete_everyone') {
      await _messageService.deleteMessageForEveryone(message);
    } else if (action == 'report') {
      await _showReportMessageSheet(message);
    } else if (action == 'block') {
      await _confirmBlockSender();
    }
  }

  Future<void> _showReportMessageSheet(DirectMessage message) async {
    String selectedReason = ModerationService.reportReasons.first;
    final descriptionController = TextEditingController();
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Report Message',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: selectedReason,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    items: [
                      for (final reason in ModerationService.reportReasons)
                        DropdownMenuItem(value: reason, child: Text(reason)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setSheetState(() => selectedReason = value);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Additional context',
                      hintText: 'Optional',
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('Submit Report'),
                      onPressed: () async {
                        await _moderationService.reportContent(
                          churchId: widget.conversation.churchId,
                          contentType: 'chat_message',
                          contentId: message.id,
                          reportedUserId: message.senderId,
                          reason: selectedReason,
                          description: descriptionController.text,
                          metadata: {'preview': message.text},
                        );
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext, true);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    descriptionController.dispose();
    if (!mounted || submitted != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Thank you. This report has been submitted for review.'),
      ),
    );
  }

  Future<void> _confirmBlockSender() async {
    final displayName = widget.otherUser.fullName.isNotEmpty
        ? widget.otherUser.fullName
        : widget.otherUser.email;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Block $displayName?'),
        content: const Text(
          'They will no longer be able to message you or interact with your content. This is private and they will not be notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _moderationService.blockUser(
      churchId: widget.conversation.churchId,
      blockedUserId: widget.otherUser.uid,
      reason: 'Blocked from chat',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$displayName has been blocked.')),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.otherUser.fullName.isNotEmpty
        ? widget.otherUser.fullName
        : widget.otherUser.email;

    return AppScaffold(
      title: displayName,
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<DirectMessage>>(
              stream: _messageService.watchMessages(widget.conversation.id),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Could not load messages: ${snapshot.error}'),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: AppLoader());
                }

                final messages = snapshot.data!;
                if (messages.isNotEmpty) {
                  unawaited(
                    _messageService.markConversationRead(
                      widget.conversation.id,
                    ),
                  );
                }

                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      'Start the conversation',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    return _MessageBubble(
                      message: messages[index],
                      isMe: messages[index].senderId == _currentUid,
                      onLongPress: () => _showMessageActions(messages[index]),
                    );
                  },
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
                  top: BorderSide(
                    color:
                        Theme.of(context).dividerColor.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_pendingMediaBytes != null)
                          _PendingAttachmentPreview(
                            mediaType: _pendingMediaType ?? 'attachment',
                            fileName: _pendingMediaName ?? 'Attachment',
                            bytes: _pendingMediaBytes,
                            onClear: _clearPendingMedia,
                          ),
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Voice note',
                              onPressed: _isSending ? null : _pickVoiceNote,
                              icon: const Icon(Icons.mic_none_outlined),
                            ),
                            IconButton(
                              tooltip: 'Image',
                              onPressed: _isSending ? null : _pickImage,
                              icon: const Icon(Icons.image_outlined),
                            ),
                            IconButton(
                              tooltip: 'Video',
                              onPressed: _isSending ? null : _pickVideo,
                              icon: const Icon(Icons.videocam_outlined),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _messageController,
                                minLines: 1,
                                maxLines: 4,
                                textInputAction: TextInputAction.newline,
                                decoration: const InputDecoration(
                                  hintText: 'Message',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      disabledBackgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      disabledForegroundColor: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.38),
                    ),
                    tooltip: 'Send',
                    onPressed: _isSending ? null : _send,
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
      ),
    );
  }
}

class _PendingAttachmentPreview extends StatelessWidget {
  const _PendingAttachmentPreview({
    required this.mediaType,
    required this.fileName,
    required this.bytes,
    required this.onClear,
  });

  final String mediaType;
  final String fileName;
  final Uint8List? bytes;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (mediaType == 'image' && bytes != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(
                bytes!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                mediaType == 'video'
                    ? Icons.play_circle_outline
                    : mediaType == 'voice'
                        ? Icons.mic_none_outlined
                        : Icons.attach_file,
                color: theme.colorScheme.primary,
              ),
            ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              fileName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: 'Remove attachment',
            onPressed: onClear,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.onLongPress,
  });

  final DirectMessage message;
  final bool isMe;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bubbleColor = isMe
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHighest;
    final textColor =
        isMe ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: GestureDetector(
          onLongPress: onLongPress,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(16).copyWith(
                bottomRight: isMe ? const Radius.circular(4) : null,
                bottomLeft: isMe ? null : const Radius.circular(4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.hasMedia) ...[
                  _MessageMediaPreview(message: message, textColor: textColor),
                  if (message.text.isNotEmpty) const SizedBox(height: 8),
                ],
                if (message.text.isNotEmpty)
                  Text(
                    message.text,
                    style: TextStyle(color: textColor, height: 1.35),
                  ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('h:mm a').format(message.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: textColor.withValues(alpha: 0.72),
                        fontSize: 10,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      _MessageStatusTicks(message: message),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageMediaPreview extends StatelessWidget {
  const _MessageMediaPreview({
    required this.message,
    required this.textColor,
  });

  final DirectMessage message;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final type = message.mediaType;

    if (type == 'image' && message.mediaUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: message.mediaUrl!,
          width: 220,
          height: 180,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            width: 220,
            height: 180,
            color: Colors.black12,
            child: const Center(child: CircularProgressIndicator()),
          ),
          errorWidget: (_, __, ___) => const SizedBox(
            width: 220,
            height: 120,
            child: Center(child: Icon(Icons.broken_image_outlined)),
          ),
        ),
      );
    }

    final icon = switch (type) {
      'video' => Icons.play_circle_outline,
      'voice' || 'audio' => Icons.mic_none_outlined,
      _ => Icons.attach_file,
    };
    final label = switch (type) {
      'video' => 'Video',
      'voice' || 'audio' => 'Voice message',
      _ => 'Attachment',
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: textColor, size: 22),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(color: textColor)),
      ],
    );
  }
}

class _MessageStatusTicks extends StatelessWidget {
  const _MessageStatusTicks({required this.message});

  final DirectMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.isSeen) {
      return const Icon(Icons.done_all, size: 14, color: Colors.greenAccent);
    }
    if (message.isDelivered) {
      return const Icon(Icons.done_all, size: 14, color: Colors.white70);
    }
    return const Icon(Icons.done, size: 14, color: Colors.white70);
  }
}
