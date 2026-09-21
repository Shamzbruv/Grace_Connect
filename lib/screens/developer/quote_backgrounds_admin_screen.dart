import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../services/haptic_service.dart';
import '../../services/quote_background_admin_service.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/app_scaffold.dart';

/// Developer control over the share-card background catalogue.
///
/// Adding a background used to mean an app release, then an upload plus a
/// hand-edited manifest. Here it is: pick an image, name it, save. Members
/// see it the next time they open the share customiser -- no release, no
/// deploy.
class QuoteBackgroundsAdminScreen extends StatefulWidget {
  const QuoteBackgroundsAdminScreen({super.key});

  @override
  State<QuoteBackgroundsAdminScreen> createState() =>
      _QuoteBackgroundsAdminScreenState();
}

class _QuoteBackgroundsAdminScreenState
    extends State<QuoteBackgroundsAdminScreen> {
  final QuoteBackgroundAdminService _service = QuoteBackgroundAdminService();
  late Future<List<QuoteBackgroundRecord>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = _service.list();
  }

  void _reload() => setState(() => _future = _service.list());

  Future<void> _guard(Future<void> Function() action, String success) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      HapticService.success();
      AppFeedback.show(context, success, type: AppFeedbackType.success);
      _reload();
    } catch (error) {
      if (!mounted) return;
      HapticService.warning();
      AppFeedback.show(context, '$error', type: AppFeedbackType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addBackground() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Backgrounds are shown at 1080x1080 on the card; anything larger is
      // bandwidth every member pays for on every share.
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 92,
    );
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    if (!mounted) return;

    final details = await showModalBottomSheet<_BackgroundDetails>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BackgroundDetailsSheet(
        title: 'New background',
        previewBytes: bytes,
      ),
    );
    if (details == null) return;

    await _guard(
      () => _service.add(
        bytes: bytes,
        fileName: picked.name,
        title: details.title,
        category: details.category,
        recommendedTextColor: details.textColor,
        safeTextArea: details.safeArea,
      ),
      'Background added. Members will see it on their next share.',
    );
  }

  Future<void> _edit(QuoteBackgroundRecord record) async {
    final details = await showModalBottomSheet<_BackgroundDetails>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BackgroundDetailsSheet(
        title: 'Edit background',
        imageUrl: record.imageUrl,
        initialTitle: record.title,
        initialCategory: record.category,
        initialTextColor: record.recommendedTextColor,
        initialSafeArea: record.safeTextArea,
      ),
    );
    if (details == null) return;

    await _guard(
      () => _service.update(
        record.id,
        title: details.title,
        category: details.category,
        recommendedTextColor: details.textColor,
        safeTextArea: details.safeArea,
      ),
      'Background updated.',
    );
  }

  Future<void> _confirmRemove(QuoteBackgroundRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this background?'),
        content: Text(
          '"${record.title}" will disappear from the share customiser for '
          'every member, and the image file will be deleted. Cards already '
          'shared are unaffected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _guard(() => _service.remove(record), 'Background removed.');
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Quote Backgrounds',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _busy ? null : _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _addBackground,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Add background'),
      ),
      body: FutureBuilder<List<QuoteBackgroundRecord>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(
              message: '${snapshot.error}',
              onRetry: _reload,
            );
          }
          final records = snapshot.data ?? const <QuoteBackgroundRecord>[];
          if (records.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'No backgrounds yet. Add one and it goes live immediately.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final activeCount = records.where((r) => r.isActive).length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Text(
                '$activeCount of ${records.length} showing to members',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Turning one off hides it from the share customiser without '
                'deleting the image.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              for (final record in records) ...[
                _BackgroundRow(
                  record: record,
                  busy: _busy,
                  onEdit: () => _edit(record),
                  onRemove: () => _confirmRemove(record),
                  onToggle: (value) => _guard(
                    () => _service.update(record.id, isActive: value),
                    value ? 'Background shown to members.' : 'Background hidden.',
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _BackgroundRow extends StatelessWidget {
  const _BackgroundRow({
    required this.record,
    required this.busy,
    required this.onEdit,
    required this.onRemove,
    required this.onToggle,
  });

  final QuoteBackgroundRecord record;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 76,
                height: 76,
                child: CachedNetworkImage(
                  imageUrl: record.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: (context, url, error) => ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined, size: 18),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (record.category.isNotEmpty)
                    Text(
                      record.category,
                      style: theme.textTheme.bodySmall,
                    ),
                  Text(
                    'Text ${record.recommendedTextColor} · ${record.safeTextArea}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: busy ? null : onEdit,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit'),
                      ),
                      TextButton.icon(
                        onPressed: busy ? null : onRemove,
                        icon: const Icon(Icons.delete_outline, size: 16),
                        label: const Text('Remove'),
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Switch(
              value: record.isActive,
              onChanged: busy ? null : onToggle,
            ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundDetails {
  const _BackgroundDetails({
    required this.title,
    required this.category,
    required this.textColor,
    required this.safeArea,
  });

  final String title;
  final String category;
  final String textColor;
  final String safeArea;
}

class _BackgroundDetailsSheet extends StatefulWidget {
  const _BackgroundDetailsSheet({
    required this.title,
    this.previewBytes,
    this.imageUrl,
    this.initialTitle,
    this.initialCategory,
    this.initialTextColor,
    this.initialSafeArea,
  });

  final String title;
  final Uint8List? previewBytes;
  final String? imageUrl;
  final String? initialTitle;
  final String? initialCategory;
  final String? initialTextColor;
  final String? initialSafeArea;

  @override
  State<_BackgroundDetailsSheet> createState() =>
      _BackgroundDetailsSheetState();
}

class _BackgroundDetailsSheetState extends State<_BackgroundDetailsSheet> {
  late final TextEditingController _titleController =
      TextEditingController(text: widget.initialTitle ?? '');
  late final TextEditingController _categoryController =
      TextEditingController(text: widget.initialCategory ?? '');
  late String _textColor = widget.initialTextColor ?? 'white';
  late String _safeArea = widget.initialSafeArea ?? 'center';

  /// Matches the database's safe_text_area constraint exactly, so an
  /// unsupported value cannot be chosen and then rejected on save.
  static const List<String> _safeAreas = [
    'center',
    'upper-center',
    'left-center',
    'center-right',
  ];

  static const Map<String, String> _textColours = {
    'white': 'White',
    '#10141C': 'Dark navy',
    '#FFBF00': 'Gold',
  };

  @override
  void dispose() {
    _titleController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 18,
        right: 18,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 18,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            if (widget.previewBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  widget.previewBytes!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              )
            else if (widget.imageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrl!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _titleController,
              maxLength: 120,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Midnight Grace',
              ),
            ),
            TextField(
              controller: _categoryController,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Category',
                hintText: 'Dark / Prayer',
              ),
            ),
            const SizedBox(height: 12),
            Text('Recommended text colour', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final entry in _textColours.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: _textColor == entry.key,
                    onSelected: (_) => setState(() => _textColor = entry.key),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text('Safe text area', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final area in _safeAreas)
                  ChoiceChip(
                    label: Text(area),
                    selected: _safeArea == area,
                    onSelected: (_) => setState(() => _safeArea = area),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                final title = _titleController.text.trim();
                if (title.isEmpty) {
                  AppFeedback.show(
                    context,
                    'Give the background a title.',
                    type: AppFeedbackType.error,
                  );
                  return;
                }
                Navigator.pop(
                  context,
                  _BackgroundDetails(
                    title: title,
                    category: _categoryController.text.trim(),
                    textColor: _textColor,
                    safeArea: _safeArea,
                  ),
                );
              },
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
