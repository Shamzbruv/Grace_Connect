import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../models/study_group_model.dart';
import '../../providers/user_role_provider.dart';
import '../../services/study_group_service.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_text_field.dart';

class CreateStudyGroupScreen extends StatefulWidget {
  const CreateStudyGroupScreen({super.key});

  @override
  State<CreateStudyGroupScreen> createState() => _CreateStudyGroupScreenState();
}

class _CreateStudyGroupScreenState extends State<CreateStudyGroupScreen> {
  final StudyGroupService _service = StudyGroupService();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _welcomeController = TextEditingController();
  final _topicController = TextEditingController();
  final _bookController = TextEditingController();
  final _chapterController = TextEditingController();
  final _scheduleController = TextEditingController();
  final _locationController = TextEditingController();
  final _linkController = TextEditingController();
  final _maxMembersController = TextEditingController();
  final _guidelinesController = TextEditingController();

  int _step = 0;
  String _visibility = 'church';
  String _joinMode = 'approval';
  bool _allowMemberMessages = true;
  bool _isSaving = false;

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

  Future<void> _save({required bool draft}) async {
    final user = Supabase.instance.client.auth.currentUser;
    final profile =
        Provider.of<UserRoleProvider>(context, listen: false).userProfile;
    if (user == null || profile == null) return;
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group name is required.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final group = StudyGroup(
        id: const Uuid().v4(),
        name: _nameController.text.trim(),
        topic: _topicController.text.trim(),
        description: _descriptionController.text.trim(),
        leaderId: user.id,
        leaderName: profile.fullName.isEmpty ? 'Unknown' : profile.fullName,
        adminIds: [user.id],
        memberIds: [user.id],
        schedule: _scheduleController.text.trim(),
        churchId: profile.placeId,
        createdAt: DateTime.now(),
        allowMemberMessages: _allowMemberMessages,
        isPrivate: _visibility != 'church',
        requireJoinApproval: _joinMode == 'approval',
        visibility: _visibility,
        joinMode: _joinMode,
        status: draft ? 'draft' : 'active',
        welcomeMessage: _welcomeController.text.trim(),
        guidelines: _guidelinesController.text.trim(),
        currentBook: _bookController.text.trim(),
        currentChapter: int.tryParse(_chapterController.text.trim()),
        meetingLocation: _locationController.text.trim(),
        meetingLink: _linkController.text.trim(),
        maxMembers: int.tryParse(_maxMembersController.text.trim()),
      );
      final created = await _service.createGroup(group);
      if (!mounted) return;
      Navigator.pop(context, created);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(draft ? 'Draft saved.' : 'Bible Study Group created.'),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create group: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Create Study Group',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: _StepPills(currentStep: _step),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: _buildStep(context),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  if (_step > 0)
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _isSaving ? null : () => setState(() => _step--),
                        child: const Text('Back'),
                      ),
                    ),
                  if (_step > 0) const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isSaving
                          ? null
                          : _step < 4
                              ? () => setState(() => _step++)
                              : () => _save(draft: false),
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_step < 4 ? 'Next' : 'Create Group'),
                    ),
                  ),
                  if (_step == 4) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextButton(
                        onPressed: _isSaving ? null : () => _save(draft: true),
                        child: const Text('Save Draft'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    return switch (_step) {
      0 => _section(
          title: 'Group Identity',
          icon: Icons.groups_2_outlined,
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
      1 => _section(
          title: 'Bible Study',
          icon: Icons.menu_book_outlined,
          children: [
            AppTextField(
              controller: _topicController,
              label: 'Study topic',
              hint: 'Romans, Prayer, New Believers',
            ),
            const SizedBox(height: 12),
            AppTextField(controller: _bookController, label: 'Bible book'),
            const SizedBox(height: 12),
            AppTextField(
              controller: _chapterController,
              label: 'Starting chapter',
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      2 => _section(
          title: 'Membership',
          icon: Icons.how_to_reg_outlined,
          children: [
            DropdownButtonFormField<String>(
              value: _visibility,
              decoration: const InputDecoration(labelText: 'Visibility'),
              items: const [
                DropdownMenuItem(
                    value: 'church', child: Text('Public to Church')),
                DropdownMenuItem(value: 'private', child: Text('Private')),
                DropdownMenuItem(
                  value: 'invitation_only',
                  child: Text('Invitation Only'),
                ),
              ],
              onChanged: (value) =>
                  setState(() => _visibility = value ?? 'church'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _joinMode,
              decoration: const InputDecoration(labelText: 'Join mode'),
              items: const [
                DropdownMenuItem(value: 'open', child: Text('Open')),
                DropdownMenuItem(
                    value: 'approval', child: Text('Approval required')),
                DropdownMenuItem(
                  value: 'invitation_only',
                  child: Text('Invitation only'),
                ),
                DropdownMenuItem(value: 'closed', child: Text('Closed')),
              ],
              onChanged: (value) =>
                  setState(() => _joinMode = value ?? 'approval'),
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _maxMembersController,
              label: 'Maximum members',
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      3 => _section(
          title: 'Communication',
          icon: Icons.forum_outlined,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Everyone can post'),
              subtitle: const Text('Turn off for leader-only announcements.'),
              value: _allowMemberMessages,
              onChanged: (value) =>
                  setState(() => _allowMemberMessages = value),
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _guidelinesController,
              label: 'Group guidelines',
              maxLines: 4,
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: _scheduleController,
              label: 'Meeting day and time',
              hint: 'Fridays 7:00 PM',
            ),
            const SizedBox(height: 12),
            AppTextField(controller: _locationController, label: 'Location'),
            const SizedBox(height: 12),
            AppTextField(
                controller: _linkController, label: 'Online meeting link'),
          ],
        ),
      _ => _section(
          title: 'Review',
          icon: Icons.fact_check_outlined,
          children: [
            _ReviewRow(label: 'Name', value: _nameController.text.trim()),
            _ReviewRow(
                label: 'Study',
                value: _bookController.text.trim().isEmpty
                    ? _topicController.text.trim()
                    : _bookController.text.trim()),
            _ReviewRow(
                label: 'Schedule', value: _scheduleController.text.trim()),
            _ReviewRow(label: 'Visibility', value: _visibility),
            _ReviewRow(label: 'Join mode', value: _joinMode),
          ],
        ),
    };
  }

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return AppCard(
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
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _StepPills extends StatelessWidget {
  final int currentStep;
  const _StepPills({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(5, (index) {
        final active = index <= currentStep;
        return Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 5,
            margin: EdgeInsets.only(right: index == 4 ? 0 : 6),
            decoration: BoxDecoration(
              color: active
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).dividerColor,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        );
      }),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReviewRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final displayValue = value.trim().isEmpty ? 'Not set' : value.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(child: Text(displayValue)),
        ],
      ),
    );
  }
}
