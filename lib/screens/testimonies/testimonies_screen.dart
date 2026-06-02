import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../models/testimony.dart';
import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/testimony_service.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_loader.dart';
import '../../widgets/ui/app_scaffold.dart';

class TestimoniesScreen extends StatefulWidget {
  const TestimoniesScreen({super.key});

  @override
  State<TestimoniesScreen> createState() => _TestimoniesScreenState();
}

class _TestimoniesScreenState extends State<TestimoniesScreen> {
  final TestimonyService _service = TestimonyService();
  static const List<String> _reactionOptions = ['🙏', '❤️', '🙌', '🔥', '😊'];

  Future<void> _showAddDialog(UserProfile user) async {
    final controller = TextEditingController();
    var isAnonymous = false;
    var isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Add Testimony'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    minLines: 4,
                    maxLines: 8,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Share what God has done',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: isAnonymous,
                    onChanged: isSaving
                        ? null
                        : (value) {
                            setDialogState(() {
                              isAnonymous = value ?? false;
                            });
                          },
                    title: const Text('Share anonymously'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: isSaving
                    ? null
                    : () async {
                        final text = controller.text.trim();
                        if (text.isEmpty) return;

                        setDialogState(() => isSaving = true);
                        try {
                          await _service.addTestimony(
                            author: user,
                            content: text,
                            isAnonymous: isAnonymous,
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                        } catch (error) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              content: Text('Could not add testimony: $error'),
                            ),
                          );
                        } finally {
                          if (dialogContext.mounted) {
                            setDialogState(() => isSaving = false);
                          }
                        }
                      },
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_outlined),
                label: const Text('Share'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserRoleProvider>().userProfile;
    final churchId = user?.churchId ?? '';

    return AppScaffold(
      title: 'Testimonies',
      showBottomMenu: true,
      floatingActionButton: user == null
          ? null
          : FloatingActionButton(
              onPressed: () => _showAddDialog(user),
              child: const Icon(Icons.add),
            ),
      body: user == null || churchId.isEmpty
          ? const Center(child: AppLoader())
          : StreamBuilder<List<Testimony>>(
              stream: _service.watchTestimonies(churchId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child:
                          Text('Could not load testimonies: ${snapshot.error}'),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: AppLoader());
                }

                final testimonies = snapshot.data!;
                if (testimonies.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_outlined,
                            size: 58,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No testimonies yet',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => _showAddDialog(user),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Testimony'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                  itemCount: testimonies.length,
                  itemBuilder: (context, index) {
                    return _TestimonyCard(
                      testimony: testimonies[index],
                      currentUserId: user.uid,
                      reactions: _reactionOptions,
                      onReact: (emoji) =>
                          _service.toggleReaction(testimonies[index].id, emoji),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _TestimonyCard extends StatelessWidget {
  const _TestimonyCard({
    required this.testimony,
    required this.currentUserId,
    required this.reactions,
    required this.onReact,
  });

  final Testimony testimony;
  final String currentUserId;
  final List<String> reactions;
  final Future<void> Function(String emoji) onReact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.14),
                child: Icon(
                  testimony.isAnonymous
                      ? Icons.visibility_off_outlined
                      : Icons.person_outline,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      testimony.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      timeago.format(testimony.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(testimony.content, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: reactions.map((emoji) {
              final selected = testimony.reactedWith(emoji, currentUserId);
              final count = testimony.reactionCount(emoji);
              return ActionChip(
                avatar: Text(emoji),
                label: Text('$count'),
                side: BorderSide(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.dividerColor.withValues(alpha: 0.4),
                ),
                backgroundColor: selected
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surface,
                onPressed: () => onReact(emoji),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
