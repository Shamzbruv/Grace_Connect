import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../models/daily_motivation.dart';
import '../../services/daily_motivation_service.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/app_loader.dart';

class DailyMotivationAdminScreen extends StatefulWidget {
  const DailyMotivationAdminScreen({super.key});

  @override
  State<DailyMotivationAdminScreen> createState() =>
      _DailyMotivationAdminScreenState();
}

class _DailyMotivationAdminScreenState
    extends State<DailyMotivationAdminScreen> {
  final _service = DailyMotivationService();
  late Future<List<DailyMotivation>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.fetchAdminHistory();
  }

  void _refresh() {
    setState(() => _future = _service.fetchAdminHistory());
  }

  Future<void> _openEditor([DailyMotivation? motivation]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _DailyMotivationEditor(motivation: motivation),
    );
    if (saved == true && mounted) {
      AppFeedback.show(
        context,
        'Daily Word saved.',
        type: AppFeedbackType.success,
      );
      _refresh();
    }
  }

  Future<void> _togglePublished(DailyMotivation motivation) async {
    try {
      await _service.setPublished(motivation.id, !motivation.isPublished);
      if (mounted) {
        AppFeedback.show(
          context,
          motivation.isPublished
              ? 'Daily Word unpublished.'
              : 'Daily Word published.',
          type: AppFeedbackType.success,
        );
        _refresh();
      }
    } catch (error) {
      if (mounted) {
        AppFeedback.show(
          context,
          'Could not update Daily Word: $error',
          type: AppFeedbackType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Daily Word Manager',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Manual Word'),
      ),
      body: FutureBuilder<List<DailyMotivation>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoader();
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Could not load Daily Words: ${snapshot.error}'),
              ),
            );
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return Center(
              child: Text(
                'No Daily Words yet.',
                style: theme.textTheme.titleMedium,
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: ListTile(
                  onTap: () => _openEditor(item),
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${DateFormat.yMMMd().format(item.publishDate)} • ${item.scriptureReference}\n${item.status}${item.notificationSentAt == null ? ' • notification pending' : ' • notification sent'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  leading: CircleAvatar(
                    child: Icon(
                      item.isPublished
                          ? Icons.check_circle_outline
                          : Icons.edit_note,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: item.isPublished ? 'Unpublish' : 'Publish',
                    onPressed: () => _togglePublished(item),
                    icon: Icon(
                      item.isPublished
                          ? Icons.visibility_off_outlined
                          : Icons.publish_outlined,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DailyMotivationEditor extends StatefulWidget {
  const _DailyMotivationEditor({this.motivation});

  final DailyMotivation? motivation;

  @override
  State<_DailyMotivationEditor> createState() => _DailyMotivationEditorState();
}

class _DailyMotivationEditorState extends State<_DailyMotivationEditor> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _messageController = TextEditingController();
  final _scriptureController = TextEditingController();
  final _topicController = TextEditingController();
  late DateTime _publishDate;
  bool _publish = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final item = widget.motivation;
    _publishDate = item?.publishDate ?? DateTime.now();
    _titleController.text = item?.title ?? '';
    _messageController.text = item?.message ?? '';
    _scriptureController.text = item?.scriptureReference ?? '';
    _topicController.text = item?.topic ?? '';
    _publish = item?.isPublished ?? true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    _scriptureController.dispose();
    _topicController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await DailyMotivationService().saveManual(
        id: widget.motivation?.id,
        publishDate: _publishDate,
        title: _titleController.text,
        message: _messageController.text,
        scriptureReference: _scriptureController.text,
        topic: _topicController.text,
        publish: _publish,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        AppFeedback.show(
          context,
          'Could not save Daily Word: $error',
          type: AppFeedbackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + bottomInset),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.motivation == null
                    ? 'Create Daily Word'
                    : 'Edit Daily Word',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Add a title.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _messageController,
                minLines: 4,
                maxLines: 7,
                decoration: const InputDecoration(labelText: 'Message'),
                validator: (value) => value == null || value.trim().length < 20
                    ? 'Add a complete message.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _scriptureController,
                decoration:
                    const InputDecoration(labelText: 'Scripture reference'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Add a scripture reference.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _topicController,
                decoration: const InputDecoration(labelText: 'Topic'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _publish,
                title: const Text('Publish now'),
                onChanged: (value) => setState(() => _publish = value),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save Daily Word'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
