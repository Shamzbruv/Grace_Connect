import 'package:flutter/material.dart';

import '../../models/study_group_model.dart';
import '../../services/study_reading_plan_service.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_text_field.dart';

class StudyGroupReadingPlanEditor extends StatefulWidget {
  final StudyGroup group;
  const StudyGroupReadingPlanEditor({super.key, required this.group});

  @override
  State<StudyGroupReadingPlanEditor> createState() =>
      _StudyGroupReadingPlanEditorState();
}

class _StudyGroupReadingPlanEditorState
    extends State<StudyGroupReadingPlanEditor> {
  final StudyReadingPlanService _service = StudyReadingPlanService();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _translationController = TextEditingController(text: 'KJV');
  bool _isSaving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _translationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plan title is required.')),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _service.createPlan(
        groupId: widget.group.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        translation: _translationController.text.trim().isEmpty
            ? 'KJV'
            : _translationController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reading plan created.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not create reading plan: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Reading Plan',
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.group.name,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 16),
                AppTextField(controller: _titleController, label: 'Plan title'),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _descriptionController,
                  label: 'Description',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _translationController,
                  label: 'Translation',
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _save,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: const Text('Create Plan'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
