import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../models/reel.dart';
import '../../providers/user_role_provider.dart';
import '../../services/reel_analytics_service.dart';
import '../../services/reel_upload_service.dart';
import '../../widgets/ui/app_scaffold.dart';

const List<({String value, String label})> _reelCategories = [
  (value: 'testimony', label: 'Testimony'),
  (value: 'worship', label: 'Worship'),
  (value: 'word', label: 'Word'),
  (value: 'encouragement', label: 'Encouragement'),
  (value: 'bible_study', label: 'Bible Study'),
  (value: 'youth', label: 'Youth'),
  (value: 'church_moment', label: 'Church Moment'),
  (value: 'ministry', label: 'Ministry'),
  (value: 'relationships', label: 'Relationships'),
  (value: 'motivation', label: 'Motivation'),
  (value: 'other', label: 'Other'),
];

class ReelCreateScreen extends StatefulWidget {
  const ReelCreateScreen({super.key});

  @override
  State<ReelCreateScreen> createState() => _ReelCreateScreenState();
}

class _ReelCreateScreenState extends State<ReelCreateScreen> {
  final ReelUploadService _uploads = ReelUploadService();
  final TextEditingController _caption = TextEditingController();

  ReelSource? _source;
  String _category = 'testimony';
  ReelVisibility? _visibility;
  ReelUploadProgress? _progress;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  bool get _hasChurch =>
      (context.read<UserRoleProvider>().userProfile?.churchId ?? '')
          .trim()
          .isNotEmpty;

  /// Deliberately not Public. A reel is a video of someone's face and voice;
  /// the default should be the smallest audience that still makes sense --
  /// their church if they have one, otherwise the people who chose to follow
  /// them. Reaching everyone is a decision the member makes on purpose.
  ReelVisibility get _defaultVisibility =>
      _hasChurch ? ReelVisibility.church : ReelVisibility.followers;

  Future<void> _pick(ImageSource source) async {
    setState(() => _error = null);
    try {
      final picked = await ImagePicker().pickVideo(
        source: source,
        // Constrains capture up front so the common path is already inside
        // the reel format rather than being rejected after recording.
        maxDuration: ReelUploadLimits.maxDuration,
      );
      if (picked == null) return;
      setState(() => _busy = true);
      final prepared = await _uploads.prepare(File(picked.path));
      if (!mounted) return;
      setState(() {
        _source = prepared;
        _visibility ??= _defaultVisibility;
        _busy = false;
      });
    } on ReelUploadException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'That video could not be prepared.';
      });
    }
  }

  Future<void> _post() async {
    final source = _source;
    if (source == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = const ReelUploadProgress(stage: ReelUploadStage.preparing);
    });
    ReelAnalytics.uploadStarted();
    try {
      await _uploads.publish(
        source: source,
        caption: _caption.text.trim(),
        category: _category,
        visibility: _visibility ?? _defaultVisibility,
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      ReelAnalytics.uploadCompleted(
        bytes: source.videoBytes,
        durationMs: source.durationMs,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ReelUploadException catch (error) {
      ReelAnalytics.uploadFailed(_progress?.stage.name ?? 'unknown');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        // An abandoned upload is not a leak: the session expires and the
        // scheduled sweep removes whatever reached R2.
        _error = error.message;
      });
    }
  }

  void _cancelUpload() {
    _uploads.cancel();
    setState(() {
      _busy = false;
      _progress = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = _source;
    final progress = _progress;

    return AppScaffold(
      title: 'New Reel',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
        children: [
          if (source == null) ...[
            Text('Share a short vertical video',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('Up to 60 seconds, under 25MB.',
                style: theme.textTheme.bodySmall),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.videocam_outlined),
                    label: const Text('Record'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.video_library_outlined),
                    label: const Text('Choose'),
                  ),
                ),
              ],
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(Icons.movie_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${source.readableDuration} · ${source.readableSize}',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (!_busy)
                    TextButton(
                      onPressed: () => setState(() => _source = null),
                      child: const Text('Change'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _caption,
              enabled: !_busy,
              minLines: 2,
              maxLines: 5,
              maxLength: 2200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Caption',
                hintText: 'Say a little about this moment',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text('Category', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in _reelCategories)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: _category == option.value,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() => _category = option.value),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Who can see this?', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            _VisibilityPicker(
              value: _visibility ?? _defaultVisibility,
              hasChurch: _hasChurch,
              enabled: !_busy,
              onChanged: (value) => setState(() => _visibility = value),
            ),
            const SizedBox(height: 22),
            if (progress != null) ...[
              LinearProgressIndicator(value: progress.fraction),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${progress.message ?? 'Working'} · ${(progress.fraction * 100).round()}%',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  TextButton(
                    onPressed: _cancelUpload,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: _busy ? null : _post,
              icon: const Icon(Icons.send_outlined),
              label: Text(_busy ? 'Posting…' : 'Post reel'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_error!,
                        style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Spells out the audience in plain words. "Followers" and "Church" mean
/// nothing on their own to someone deciding whether to post a video of
/// themselves, so each option says who will actually be able to watch it.
class _VisibilityPicker extends StatelessWidget {
  const _VisibilityPicker({
    required this.value,
    required this.hasChurch,
    required this.enabled,
    required this.onChanged,
  });

  final ReelVisibility value;
  final bool hasChurch;
  final bool enabled;
  final ValueChanged<ReelVisibility> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = <({ReelVisibility visibility, IconData icon, String detail})>[
      (
        visibility: ReelVisibility.church,
        icon: Icons.church_outlined,
        detail: hasChurch
            ? 'Only members of your church can watch this.'
            : 'Join a church to use this option.',
      ),
      (
        visibility: ReelVisibility.followers,
        icon: Icons.group_outlined,
        detail: 'Only people who follow you can watch this.',
      ),
      (
        visibility: ReelVisibility.public,
        icon: Icons.public_outlined,
        detail: 'Anyone on Grace Connect can watch this, including people '
            'you have never met.',
      ),
    ];

    return Column(
      children: [
        for (final option in options)
          Opacity(
            opacity: option.visibility == ReelVisibility.church && !hasChurch
                ? 0.5
                : 1,
            child: RadioListTile<ReelVisibility>(
              contentPadding: EdgeInsets.zero,
              value: option.visibility,
              groupValue: value,
              onChanged: !enabled ||
                      (option.visibility == ReelVisibility.church && !hasChurch)
                  ? null
                  : (selected) {
                      if (selected != null) onChanged(selected);
                    },
              title: Row(
                children: [
                  Icon(option.icon, size: 18),
                  const SizedBox(width: 8),
                  Text(option.visibility.label,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              subtitle: Text(option.detail, style: theme.textTheme.bodySmall),
            ),
          ),
      ],
    );
  }
}
