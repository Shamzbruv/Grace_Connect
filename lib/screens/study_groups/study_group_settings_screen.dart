import 'package:flutter/material.dart';

import '../../models/study_group_model.dart';
import '../../services/study_group_access_service.dart';
import '../../services/study_group_service.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_text_field.dart';

class StudyGroupSettingsScreen extends StatefulWidget {
  final StudyGroup group;
  final StudyGroupAccess access;

  const StudyGroupSettingsScreen({
    super.key,
    required this.group,
    required this.access,
  });

  @override
  State<StudyGroupSettingsScreen> createState() =>
      _StudyGroupSettingsScreenState();
}

class _StudyGroupSettingsScreenState extends State<StudyGroupSettingsScreen> {
  final StudyGroupService _service = StudyGroupService();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _welcomeController;
  late final TextEditingController _topicController;
  late final TextEditingController _bookController;
  late final TextEditingController _chapterController;
  late final TextEditingController _scheduleController;
  late final TextEditingController _locationController;
  late final TextEditingController _linkController;
  late final TextEditingController _maxMembersController;
  late final TextEditingController _guidelinesController;
  late String _visibility;
  late String _joinMode;
  late String _status;
  late bool _allowMessages;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final group = widget.group;
    _nameController = TextEditingController(text: group.name);
    _descriptionController = TextEditingController(text: group.description);
    _welcomeController = TextEditingController(text: group.welcomeMessage);
    _topicController = TextEditingController(text: group.topic);
    _bookController = TextEditingController(text: group.currentBook);
    _chapterController =
        TextEditingController(text: group.currentChapter?.toString() ?? '');
    _scheduleController = TextEditingController(text: group.schedule);
    _locationController = TextEditingController(text: group.meetingLocation);
    _linkController = TextEditingController(text: group.meetingLink);
    _maxMembersController =
        TextEditingController(text: group.maxMembers?.toString() ?? '');
    _guidelinesController = TextEditingController(text: group.guidelines);
    _visibility = group.visibility;
    _joinMode = group.joinMode;
    _status = group.status;
    _allowMessages = group.allowMemberMessages;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _welcomeController.dispose();
    _topicController.dispose();
    _bookController.dispose();
    _chapterController.dispose();
    _scheduleController.dispose();
    _locationController.dispose();
    _linkController.dispose();
    _maxMembersController.dispose();
    _guidelinesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final updated = widget.group.copyWith(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        welcomeMessage: _welcomeController.text.trim(),
        topic: _topicController.text.trim(),
        currentBook: _bookController.text.trim(),
        currentChapter: int.tryParse(_chapterController.text.trim()),
        schedule: _scheduleController.text.trim(),
        meetingLocation: _locationController.text.trim(),
        meetingLink: _linkController.text.trim(),
        maxMembers: int.tryParse(_maxMembersController.text.trim()),
        guidelines: _guidelinesController.text.trim(),
        visibility: _visibility,
        joinMode: _joinMode,
        status: _status,
        allowMemberMessages: _allowMessages,
        isPrivate: _visibility != 'church',
        requireJoinApproval: _joinMode == 'approval',
        updatedAt: DateTime.now(),
      );
      final saved = await _service.updateGroup(updated);
      if (!mounted) return;
      Navigator.pop(context, saved);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Study group settings saved.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save settings: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _archive() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${widget.group.name}"?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This will archive the group and remove it from members\' active group lists. Messages, reading progress and study records will no longer be accessible to members.',
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: controller,
              label: 'Type the group name',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Archive Group'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.deleteGroup(
        widget.group.id,
        confirmationName: controller.text,
      );
      if (!mounted) return;
      Navigator.pop(context, widget.group.copyWith(status: 'archived'));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group archived successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not archive group: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Group Settings',
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: [
          _section(
            title: 'Group Identity',
            icon: Icons.badge_outlined,
            children: [
              AppTextField(controller: _nameController, label: 'Group name'),
              const SizedBox(height: 12),
              AppTextField(
                controller: _descriptionController,
                label: 'Short description',
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _welcomeController,
                label: 'Welcome message',
                maxLines: 3,
              ),
            ],
          ),
          _section(
            title: 'Study Details',
            icon: Icons.menu_book_outlined,
            children: [
              AppTextField(controller: _topicController, label: 'Study topic'),
              const SizedBox(height: 12),
              AppTextField(controller: _bookController, label: 'Bible book'),
              const SizedBox(height: 12),
              AppTextField(
                controller: _chapterController,
                label: 'Current chapter',
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          _section(
            title: 'Meetings',
            icon: Icons.event_available_outlined,
            children: [
              AppTextField(
                controller: _scheduleController,
                label: 'Meeting day and time',
              ),
              const SizedBox(height: 12),
              AppTextField(controller: _locationController, label: 'Location'),
              const SizedBox(height: 12),
              AppTextField(
                controller: _linkController,
                label: 'Online meeting link',
              ),
            ],
          ),
          _section(
            title: 'Privacy and Joining',
            icon: Icons.lock_outline,
            children: [
              DropdownButtonFormField<String>(
                value: _visibility,
                decoration: const InputDecoration(labelText: 'Visibility'),
                items: const [
                  DropdownMenuItem(
                    value: 'church',
                    child: Text('Public to Church'),
                  ),
                  DropdownMenuItem(value: 'private', child: Text('Private')),
                  DropdownMenuItem(
                    value: 'invitation_only',
                    child: Text('Invitation Only'),
                  ),
                ],
                onChanged: widget.access.canEditGroup
                    ? (value) => setState(() => _visibility = value ?? 'church')
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _joinMode,
                decoration: const InputDecoration(labelText: 'Join mode'),
                items: const [
                  DropdownMenuItem(value: 'open', child: Text('Open')),
                  DropdownMenuItem(
                    value: 'approval',
                    child: Text('Approval required'),
                  ),
                  DropdownMenuItem(
                    value: 'invitation_only',
                    child: Text('Invitation only'),
                  ),
                  DropdownMenuItem(value: 'closed', child: Text('Closed')),
                ],
                onChanged: widget.access.canEditGroup
                    ? (value) => setState(() => _joinMode = value ?? 'approval')
                    : null,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _maxMembersController,
                label: 'Maximum members',
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          _section(
            title: 'Conversation',
            icon: Icons.forum_outlined,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Everyone can send messages'),
                value: _allowMessages,
                onChanged: widget.access.canEditGroup
                    ? (value) => setState(() => _allowMessages = value)
                    : null,
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _guidelinesController,
                label: 'Group guidelines',
                maxLines: 4,
              ),
            ],
          ),
          _section(
            title: 'Safety and Administration',
            icon: Icons.admin_panel_settings_outlined,
            children: [
              DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(labelText: 'Group status'),
                items: const [
                  DropdownMenuItem(value: 'draft', child: Text('Draft')),
                  DropdownMenuItem(value: 'active', child: Text('Active')),
                  DropdownMenuItem(value: 'paused', child: Text('Paused')),
                  DropdownMenuItem(
                      value: 'completed', child: Text('Completed')),
                ],
                onChanged: widget.access.canEditGroup
                    ? (value) => setState(() => _status = value ?? 'active')
                    : null,
              ),
              if (widget.access.canDeleteGroup) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: _isSaving ? null : _archive,
                    icon: const Icon(Icons.archive_outlined),
                    label: const Text('Archive Group'),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : _save,
        icon: _isSaving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.save_outlined),
        label: const Text('Save'),
      ),
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}
