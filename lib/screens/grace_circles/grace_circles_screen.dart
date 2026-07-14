import 'package:flutter/material.dart';

import '../../services/grace_circles_service.dart';
import '../../widgets/ui/app_scaffold.dart';

class GraceCirclesScreen extends StatefulWidget {
  const GraceCirclesScreen({super.key});

  @override
  State<GraceCirclesScreen> createState() => _GraceCirclesScreenState();
}

class _GraceCirclesScreenState extends State<GraceCirclesScreen> {
  final GraceCirclesService _service = GraceCirclesService();
  late Future<List<GraceCircle>> _circlesFuture;

  @override
  void initState() {
    super.initState();
    _circlesFuture = _service.fetchCircles();
  }

  void _refresh() {
    setState(() => _circlesFuture = _service.fetchCircles());
  }

  void _showGraceCirclesInfo() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.diversity_3_outlined,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'What is a Grace Circle?',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Grace Circles are small, church-connected spaces for encouragement, discipleship, accountability, and shared spiritual growth. They help members walk together around a focused need, season, topic, or ministry interest.',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'Unlike Grace Rooms, which are anonymous support rooms, Grace Circles are ongoing groups where members can join, participate, and grow with people from their church community.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Got it'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCreateCircleSheet() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    var isCreating = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'New Grace Circle',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.diversity_3_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isCreating
                        ? null
                        : () async {
                            final name = nameController.text.trim();
                            if (name.isEmpty) return;
                            final rootNavigator = Navigator.of(this.context);
                            setSheetState(() => isCreating = true);
                            final circle = await _service.createCircle(
                              name: name,
                              description: descriptionController.text.trim(),
                            );
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                            if (!mounted) return;
                            _refresh();
                            if (circle != null) {
                              rootNavigator.pushNamed(
                                '/grace_circles/circle?id=${Uri.encodeComponent(circle.id)}',
                              );
                            }
                          },
                    icon: isCreating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: const Text('Create'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    nameController.dispose();
    descriptionController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Grace Circles',
      showBottomMenu: true,
      actions: [
        IconButton(
          tooltip: 'About Grace Circles',
          icon: const Icon(Icons.info_outline),
          onPressed: _showGraceCirclesInfo,
        ),
        IconButton(
          tooltip: 'Create Circle',
          icon: const Icon(Icons.add_circle_outline),
          onPressed: _showCreateCircleSheet,
        ),
      ],
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateCircleSheet,
        icon: const Icon(Icons.add),
        label: const Text('Circle'),
      ),
      body: FutureBuilder<List<GraceCircle>>(
        future: _circlesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final circles = snapshot.data ?? const [];
          if (circles.isEmpty) {
            return RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: ListView(
                padding: const EdgeInsets.all(32),
                children: [
                  const _GraceCirclesIntroCard(),
                  const SizedBox(height: 72),
                  Icon(
                    Icons.diversity_3_outlined,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  const Center(child: Text('No Grace Circles are open yet.')),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              itemCount: circles.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return const _GraceCirclesIntroCard();
                }

                final circleIndex = index - 1;
                final circle = circles[circleIndex];
                return ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.diversity_3_outlined),
                  ),
                  title: Text(circle.name),
                  subtitle: Text(
                    circle.description.trim().isEmpty
                        ? '${circle.memberCount} members'
                        : circle.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color:
                          Theme.of(context).dividerColor.withValues(alpha: 0.2),
                    ),
                  ),
                  onTap: () => Navigator.of(context).pushNamed(
                    '/grace_circles/circle?id=${Uri.encodeComponent(circle.id)}',
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _GraceCirclesIntroCard extends StatelessWidget {
  const _GraceCirclesIntroCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.diversity_3_outlined,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Grace Circles',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Small church-connected groups for encouragement, discipleship, accountability, and growing together around a shared spiritual focus.',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
