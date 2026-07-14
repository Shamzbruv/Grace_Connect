import 'package:flutter/material.dart';

import '../../models/study_group_model.dart';
import '../../models/study_reading_assignment.dart';
import '../../models/study_reading_plan.dart';
import '../../services/study_group_access_service.dart';
import '../../services/study_group_service.dart';
import '../../widgets/ui/app_card.dart';
import 'study_group_reading_plan_editor.dart';

class StudyGroupReadTab extends StatefulWidget {
  final StudyGroup group;
  final StudyGroupAccess access;
  final StudyGroupService service;

  const StudyGroupReadTab({
    super.key,
    required this.group,
    required this.access,
    required this.service,
  });

  @override
  State<StudyGroupReadTab> createState() => _StudyGroupReadTabState();
}

class _StudyGroupReadTabState extends State<StudyGroupReadTab> {
  int _refreshKey = 0;

  Future<void> _openPlanEditor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudyGroupReadingPlanEditor(group: widget.group),
      ),
    );
    if (mounted) setState(() => _refreshKey++);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StudyReadingPlan>>(
      key: ValueKey(_refreshKey),
      future: widget.service.fetchReadingPlans(widget.group.id),
      builder: (context, snapshot) {
        final plans = snapshot.data ?? const [];
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (plans.isEmpty) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 40, 20, 110),
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'This group does not have a reading plan yet.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              if (widget.access.canEditGroup) ...[
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _openPlanEditor,
                  icon: const Icon(Icons.add),
                  label: const Text('Create Reading Plan'),
                ),
              ],
            ],
          );
        }

        final plan = plans.first;
        return FutureBuilder<List<StudyReadingAssignment>>(
          future: widget.service.fetchReadingAssignments(plan.id),
          builder: (context, assignmentSnapshot) {
            final assignments = assignmentSnapshot.data ?? const [];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.title,
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      if (plan.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(plan.description),
                      ],
                      const SizedBox(height: 10),
                      Text('Translation: ${plan.translation}'),
                    ],
                  ),
                ),
                if (assignments.isEmpty)
                  AppCard(
                    child: Text(
                      widget.access.canEditGroup
                          ? 'Add readings from the reading plan editor.'
                          : 'Your leader has not added readings yet.',
                    ),
                  )
                else
                  ...assignments.map(
                    (assignment) => AppCard(
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.auto_stories_outlined),
                        title: Text(
                          assignment.title.isEmpty
                              ? assignment.passageLabel
                              : assignment.title,
                        ),
                        subtitle: Text(assignment.reflectionPrompt.isEmpty
                            ? assignment.passageLabel
                            : assignment.reflectionPrompt),
                        trailing: FilledButton(
                          onPressed: () async {
                            await widget.service.markAssignmentComplete(
                              assignment.id,
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Marked as read.')),
                            );
                          },
                          child: const Text('Read'),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
