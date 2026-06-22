import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
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
  final AudioRecorder _voiceRecorder = AudioRecorder();
  final AudioPlayer _voicePreviewPlayer = AudioPlayer();
  bool _isSending = false;
  bool _isRecordingVoice = false;
  bool _isStoppingVoice = false;
  bool _isPlayingVoicePreview = false;
  Duration _voiceRecordingElapsed = Duration.zero;
  DateTime? _voiceRecordingStartedAt;
  Timer? _voiceRecordingTimer;
  StreamSubscription<Uint8List>? _voiceRecordingSubscription;
  StreamSubscription<void>? _voicePreviewCompleteSubscription;
  final List<int> _voicePcmBytes = [];
  Uint8List? _pendingMediaBytes;
  String? _pendingMediaName;
  String? _pendingMediaType;
  String? _pendingMimeType;
  int? _pendingDurationSeconds;

  static const Duration _maxVoiceDuration = Duration(minutes: 2);
  static const int _voiceSampleRate = 16000;
  static const int _voiceChannels = 1;

  String get _currentUid => Supabase.instance.client.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_messageService.cleanupVanishingContent());
    unawaited(_messageService.markConversationRead(widget.conversation.id));
  }

  @override
  void dispose() {
    _voiceRecordingTimer?.cancel();
    unawaited(_voiceRecordingSubscription?.cancel());
    unawaited(_voicePreviewCompleteSubscription?.cancel());
    unawaited(_voiceRecorder.dispose());
    unawaited(_voicePreviewPlayer.dispose());
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

  Future<void> _startVoiceRecording() async {
    if (_isSending || _isRecordingVoice || _isStoppingVoice) return;

    final hasPermission = await _voiceRecorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone permission is needed for voice notes.'),
        ),
      );
      return;
    }

    await _voicePreviewPlayer.stop();
    await _voicePreviewCompleteSubscription?.cancel();
    _voicePcmBytes.clear();

    final stream = await _voiceRecorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _voiceSampleRate,
        numChannels: _voiceChannels,
        echoCancel: true,
        noiseSuppress: true,
      ),
    );

    _voiceRecordingSubscription = stream.listen(_voicePcmBytes.addAll);
    _voiceRecordingStartedAt = DateTime.now();
    _voiceRecordingTimer?.cancel();
    _voiceRecordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final startedAt = _voiceRecordingStartedAt;
      if (startedAt == null || !mounted) return;
      final elapsed = DateTime.now().difference(startedAt);
      setState(() => _voiceRecordingElapsed = elapsed);
      if (elapsed >= _maxVoiceDuration) {
        unawaited(_finishVoiceRecording(autoStopped: true));
      }
    });

    if (!mounted) return;
    setState(() {
      _clearPendingMediaStateOnly();
      _isRecordingVoice = true;
      _isPlayingVoicePreview = false;
      _voiceRecordingElapsed = Duration.zero;
    });
  }

  Future<void> _finishVoiceRecording({bool autoStopped = false}) async {
    if (!_isRecordingVoice || _isStoppingVoice) return;
    _isStoppingVoice = true;

    final startedAt = _voiceRecordingStartedAt;
    final duration = startedAt == null
        ? _voiceRecordingElapsed
        : DateTime.now().difference(startedAt);

    _voiceRecordingTimer?.cancel();
    await _voiceRecorder.stop();
    await _voiceRecordingSubscription?.cancel();

    if (!mounted) return;
    setState(() {
      _isRecordingVoice = false;
      _isStoppingVoice = false;
      _voiceRecordingStartedAt = null;
      _voiceRecordingElapsed = duration;
    });

    if (_voicePcmBytes.length < 1600 || duration.inMilliseconds < 700) {
      _voicePcmBytes.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hold a little longer to record.')),
      );
      return;
    }

    final cappedDuration =
        duration > _maxVoiceDuration ? _maxVoiceDuration : duration;
    final wavBytes = _buildWavFile(Uint8List.fromList(_voicePcmBytes));
    _voicePcmBytes.clear();

    setState(() {
      _pendingMediaBytes = wavBytes;
      _pendingMediaName = 'Voice note ${_formatDuration(cappedDuration)}.wav';
      _pendingMediaType = 'voice';
      _pendingMimeType = 'audio/wav';
      _pendingDurationSeconds = cappedDuration.inSeconds.clamp(1, 120).toInt();
    });

    if (autoStopped) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice note capped at 2 minutes.')),
      );
    }
  }

  Future<void> _cancelVoiceRecording() async {
    if (!_isRecordingVoice) return;
    _voiceRecordingTimer?.cancel();
    await _voiceRecorder.cancel();
    await _voiceRecordingSubscription?.cancel();
    _voicePcmBytes.clear();
    if (!mounted) return;
    setState(() {
      _isRecordingVoice = false;
      _isStoppingVoice = false;
      _voiceRecordingStartedAt = null;
      _voiceRecordingElapsed = Duration.zero;
    });
  }

  Future<void> _toggleVoicePreview() async {
    final bytes = _pendingMediaBytes;
    if (_pendingMediaType != 'voice' || bytes == null) return;

    if (_isPlayingVoicePreview) {
      await _voicePreviewPlayer.stop();
      if (mounted) setState(() => _isPlayingVoicePreview = false);
      return;
    }

    await _voicePreviewCompleteSubscription?.cancel();
    setState(() => _isPlayingVoicePreview = true);
    _voicePreviewCompleteSubscription =
        _voicePreviewPlayer.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlayingVoicePreview = false);
    });
    await _voicePreviewPlayer.play(
      BytesSource(bytes, mimeType: _pendingMimeType),
    );
  }

  void _clearPendingMediaStateOnly() {
    _pendingMediaBytes = null;
    _pendingMediaName = null;
    _pendingMediaType = null;
    _pendingMimeType = null;
    _pendingDurationSeconds = null;
  }

  void _clearPendingMedia() {
    unawaited(_voicePreviewPlayer.stop());
    if (!mounted) return;
    setState(() {
      _isPlayingVoicePreview = false;
      _clearPendingMediaStateOnly();
    });
  }

  Uint8List _buildWavFile(Uint8List pcmData) {
    const int bitsPerSample = 16;
    final byteRate = _voiceSampleRate * _voiceChannels * bitsPerSample ~/ 8;
    final blockAlign = _voiceChannels * bitsPerSample ~/ 8;
    final dataLength = pcmData.length;
    final fileLength = 44 + dataLength;
    final output = Uint8List(fileLength);
    final data = ByteData.view(output.buffer);

    void writeAscii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        output[offset + i] = value.codeUnitAt(i);
      }
    }

    writeAscii(0, 'RIFF');
    data.setUint32(4, fileLength - 8, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, _voiceChannels, Endian.little);
    data.setUint32(24, _voiceSampleRate, Endian.little);
    data.setUint32(28, byteRate, Endian.little);
    data.setUint16(32, blockAlign, Endian.little);
    data.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    data.setUint32(40, dataLength, Endian.little);
    output.setRange(44, fileLength, pcmData);
    return output;
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
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

  Widget _buildVoiceRecordButton() {
    final theme = Theme.of(context);
    final isDisabled = _isSending || _isStoppingVoice;
    return Tooltip(
      message: _isRecordingVoice
          ? 'Release to finish recording'
          : 'Hold to record voice note',
      child: GestureDetector(
        onLongPressStart:
            isDisabled ? null : (_) => unawaited(_startVoiceRecording()),
        onLongPressEnd:
            isDisabled ? null : (_) => unawaited(_finishVoiceRecording()),
        onLongPressCancel:
            isDisabled ? null : () => unawaited(_cancelVoiceRecording()),
        onTap: isDisabled
            ? null
            : () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Hold the mic to record a voice note.'),
                  ),
                );
              },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _isRecordingVoice
                ? theme.colorScheme.errorContainer
                : theme.colorScheme.surfaceContainerHighest,
          ),
          child: Icon(
            _isRecordingVoice ? Icons.mic : Icons.mic_none_outlined,
            color: _isRecordingVoice
                ? theme.colorScheme.onErrorContainer
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
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
                      onOpenReplyContext: _openReplyContext,
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
                            isPlaying: _isPlayingVoicePreview,
                            durationSeconds: _pendingDurationSeconds,
                            onPlay: _pendingMediaType == 'voice'
                                ? () => unawaited(_toggleVoicePreview())
                                : null,
                            onClear: _clearPendingMedia,
                          ),
                        if (_isRecordingVoice)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.fiber_manual_record,
                                  color: Theme.of(context).colorScheme.error,
                                  size: 14,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Recording ${_formatDuration(_voiceRecordingElapsed)} / 2:00',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const Spacer(),
                                Text(
                                  'release to preview',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        Row(
                          children: [
                            _buildVoiceRecordButton(),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Image',
                              style: IconButton.styleFrom(
                                foregroundColor:
                                    Theme.of(context).colorScheme.onSurface,
                              ),
                              onPressed: _isSending ? null : _pickImage,
                              icon: const Icon(Icons.image_outlined),
                            ),
                            IconButton(
                              tooltip: 'Video',
                              style: IconButton.styleFrom(
                                foregroundColor:
                                    Theme.of(context).colorScheme.onSurface,
                              ),
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

  void _openReplyContext(Map<String, dynamic> replyContext) {
    if (replyContext['type'] != 'community_story') return;
    final mediaUrl = replyContext['media_url']?.toString();
    final mediaType = replyContext['media_type']?.toString();
    final caption = replyContext['caption']?.toString().trim() ?? '';
    final author = replyContext['author_name']?.toString().trim() ?? 'Status';

    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (context) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (mediaType == 'image' && mediaUrl?.isNotEmpty == true)
                CachedNetworkImage(
                  imageUrl: mediaUrl!,
                  fit: BoxFit.contain,
                  errorWidget: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: Colors.white70, size: 48),
                  ),
                )
              else
                const Center(
                  child: Icon(Icons.auto_stories_outlined,
                      color: Colors.white70, size: 58),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black87,
                      Colors.transparent,
                      Colors.black87
                    ],
                    stops: [0, 0.45, 1],
                  ),
                ),
              ),
              Positioned(
                left: 18,
                right: 70,
                top: MediaQuery.of(context).padding.top + 12,
                child: Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ),
              Positioned(
                top: MediaQuery.of(context).padding.top + 2,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              if (caption.isNotEmpty)
                Positioned(
                  left: 24,
                  right: 24,
                  bottom: MediaQuery.of(context).padding.bottom + 32,
                  child: Text(
                    caption,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
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

class _PendingAttachmentPreview extends StatelessWidget {
  const _PendingAttachmentPreview({
    required this.mediaType,
    required this.fileName,
    required this.bytes,
    required this.onClear,
    this.onPlay,
    this.isPlaying = false,
    this.durationSeconds,
  });

  final String mediaType;
  final String fileName;
  final Uint8List? bytes;
  final VoidCallback onClear;
  final VoidCallback? onPlay;
  final bool isPlaying;
  final int? durationSeconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVoice = mediaType == 'voice';

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isVoice ? 'Voice note ready' : fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (isVoice && durationSeconds != null)
                  Text(
                    '${durationSeconds!.clamp(1, 120)} seconds',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (isVoice && onPlay != null)
            IconButton(
              tooltip: isPlaying ? 'Stop preview' : 'Play preview',
              onPressed: onPlay,
              icon: Icon(
                isPlaying ? Icons.stop_circle_outlined : Icons.play_circle,
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
    required this.onOpenReplyContext,
  });

  final DirectMessage message;
  final bool isMe;
  final VoidCallback onLongPress;
  final ValueChanged<Map<String, dynamic>> onOpenReplyContext;

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
                if (message.replyContext.isNotEmpty) ...[
                  _ReplyContextPreview(
                    replyContext: message.replyContext,
                    isMe: isMe,
                    textColor: textColor,
                    onTap: () => onOpenReplyContext(message.replyContext),
                  ),
                  const SizedBox(height: 8),
                ],
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

class _ReplyContextPreview extends StatelessWidget {
  const _ReplyContextPreview({
    required this.replyContext,
    required this.isMe,
    required this.textColor,
    required this.onTap,
  });

  final Map<String, dynamic> replyContext;
  final bool isMe;
  final Color textColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final author = replyContext['author_name']?.toString().trim() ?? 'Status';
    final caption = replyContext['caption']?.toString().trim() ?? '';
    final mediaUrl = replyContext['media_url']?.toString();
    final mediaType = replyContext['media_type']?.toString();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isMe
              ? Colors.white.withValues(alpha: 0.16)
              : theme.colorScheme.surface.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              color: isMe
                  ? Colors.white.withValues(alpha: 0.7)
                  : theme.colorScheme.primary,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 42,
                height: 52,
                child: mediaType == 'image' && mediaUrl?.isNotEmpty == true
                    ? CachedNetworkImage(
                        imageUrl: mediaUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Icon(
                          Icons.broken_image_outlined,
                          color: textColor.withValues(alpha: 0.75),
                        ),
                      )
                    : ColoredBox(
                        color: textColor.withValues(alpha: 0.12),
                        child: Icon(
                          Icons.auto_stories_outlined,
                          color: textColor.withValues(alpha: 0.75),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$author status',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    caption.isEmpty ? 'Tap to view status' : caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.82),
                      fontSize: 12,
                      height: 1.25,
                    ),
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

    if ((type == 'voice' || type == 'audio') && message.mediaUrl != null) {
      return _VoiceMessagePlayer(
        mediaUrl: message.mediaUrl!,
        textColor: textColor,
        durationSeconds: message.durationSeconds,
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

class _VoiceMessagePlayer extends StatefulWidget {
  const _VoiceMessagePlayer({
    required this.mediaUrl,
    required this.textColor,
    this.durationSeconds,
  });

  final String mediaUrl;
  final Color textColor;
  final int? durationSeconds;

  @override
  State<_VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<_VoiceMessagePlayer> {
  late final AudioPlayer _player = AudioPlayer();
  StreamSubscription<void>? _completeSubscription;
  bool _isPlaying = false;

  @override
  void dispose() {
    unawaited(_completeSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _player.stop();
      if (mounted) setState(() => _isPlaying = false);
      return;
    }

    await _completeSubscription?.cancel();
    _completeSubscription = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
    setState(() => _isPlaying = true);
    await _player.play(UrlSource(widget.mediaUrl));
  }

  @override
  Widget build(BuildContext context) {
    final seconds = widget.durationSeconds;
    final durationText = seconds == null
        ? 'Voice message'
        : 'Voice message - ${_formatSeconds(seconds)}';

    return InkWell(
      onTap: () => unawaited(_togglePlayback()),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isPlaying ? Icons.stop_circle_outlined : Icons.play_circle,
              color: widget.textColor,
              size: 26,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                durationText,
                style: TextStyle(
                  color: widget.textColor,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSeconds(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
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
