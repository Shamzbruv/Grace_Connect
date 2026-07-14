import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/study_group_model.dart';
import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/study_group_access_service.dart';
import '../../services/study_group_service.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_loader.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_text_field.dart';
import 'create_study_group_screen.dart';
import 'study_group_detail_screen.dart';

class StudyGroupListScreen extends StatefulWidget {
  const StudyGroupListScreen({super.key});

  @override
  State<StudyGroupListScreen> createState() => _StudyGroupListScreenState();
}

class _StudyGroupListScreenState extends State<StudyGroupListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final StudyGroupService _service = StudyGroupService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openCreateStudyGroupFlow() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateStudyGroupScreen()),
    );
  }

  Future<void> _confirmArchiveGroup(StudyGroup group) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete "${group.name}"?'),
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
        group.id,
        confirmationName: controller.text.trim(),
      );
      if (!mounted) return;
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
    final profile = Provider.of<UserRoleProvider>(context).userProfile;
    final currentUid = Supabase.instance.client.auth.currentUser?.id ?? '';
    final churchId = profile?.placeId ?? '';
    final canCreate = StudyGroupAccessService.canCreateStudyGroups(profile);

    return AppScaffold(
      title: 'Bible Study Groups',
      showBottomMenu: true,
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _openCreateStudyGroupFlow,
              icon: const Icon(Icons.add),
              label: const Text('Create Study Group'),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
            child: Text(
              'Read Scripture together, discuss what you learn and grow with your church community.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: const [
              Tab(text: 'My Studies'),
              Tab(text: 'Discover'),
              Tab(text: 'Invitations'),
              Tab(text: 'Managed'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGroupList(
                  stream: _service.getMyGroups(currentUid),
                  emptyTitle: 'You have not joined a Bible Study Group yet.',
                  emptyActionLabel: 'Discover Groups',
                  emptyAction: () => _tabController.animateTo(1),
                  profile: profile,
                  currentUid: currentUid,
                ),
                _buildGroupList(
                  stream: _service.getGroupsForChurch(churchId),
                  emptyTitle:
                      'No Bible Study Groups are currently available to join.',
                  profile: profile,
                  currentUid: currentUid,
                ),
                _buildGroupList(
                  stream: _service.getInvitations(currentUid),
                  emptyTitle:
                      'You do not have any group invitations right now.',
                  profile: profile,
                  currentUid: currentUid,
                ),
                _buildGroupList(
                  stream: _service.getManagedGroups(
                    profile: profile,
                    currentUserId: currentUid,
                  ),
                  emptyTitle:
                      'You are not currently managing any Bible Study Groups.',
                  profile: profile,
                  currentUid: currentUid,
                  managed: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupList({
    required Stream<List<StudyGroup>> stream,
    required String emptyTitle,
    required UserProfile? profile,
    required String currentUid,
    bool managed = false,
    String? emptyActionLabel,
    VoidCallback? emptyAction,
  }) {
    return StreamBuilder<List<StudyGroup>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: AppPageLoader());
        }
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child:
                  Text('Could not load Bible Study Groups: ${snapshot.error}'),
            ),
          );
        }

        final groups = snapshot.data ?? const <StudyGroup>[];
        if (groups.isEmpty) {
          return _EmptyStudyGroups(
            title: emptyTitle,
            actionLabel: emptyActionLabel,
            onAction: emptyAction,
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            final access = StudyGroupAccessService.forGroup(
              group: group,
              currentUserId: currentUid,
              profile: profile,
            );
            return _StudyGroupCard(
              group: group,
              currentUid: currentUid,
              access: access,
              managed: managed,
              onArchive: access.canDeleteGroup
                  ? () => _confirmArchiveGroup(group)
                  : null,
            );
          },
        );
      },
    );
  }
}

class _StudyGroupCard extends StatelessWidget {
  final StudyGroup group;
  final String currentUid;
  final StudyGroupAccess access;
  final bool managed;
  final VoidCallback? onArchive;

  const _StudyGroupCard({
    required this.group,
    required this.currentUid,
    required this.access,
    required this.managed,
    required this.onArchive,
  });

  @override
  Widget build(BuildContext context) {
    final membershipLabel =
        StudyGroupAccessService.membershipLabel(group, currentUid);
    final pendingCount = group.pendingMemberIds.length;

    return AppCard(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => StudyGroupDetailScreen(group: group)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: group.profilePhotoUrl.isNotEmpty
                    ? NetworkImage(group.profilePhotoUrl)
                    : null,
                child: group.profilePhotoUrl.isEmpty
                    ? const Icon(Icons.groups_2_outlined)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 3),
                    Text('Led by ${group.leaderName}'),
                    const SizedBox(height: 10),
                    Text(
                      group.progressLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: group.progressValue,
                        minHeight: 6,
                      ),
                    ),
                  ],
                ),
              ),
              if (onArchive != null)
                PopupMenuButton<String>(
                  tooltip: 'Study group options',
                  onSelected: (value) {
                    if (value == 'archive') onArchive?.call();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'archive',
                      child: Row(
                        children: [
                          Icon(Icons.archive_outlined),
                          SizedBox(width: 8),
                          Text('Archive group'),
                        ],
                      ),
                    ),
                  ],
                )
              else
                const Icon(Icons.chevron_right),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(context, group.privacyLabel),
              _chip(context, group.joinModeLabel),
              if (membershipLabel.isNotEmpty) _chip(context, membershipLabel),
              if (managed && pendingCount > 0)
                _chip(context, '$pendingCount join requests'),
              if (managed && group.progressValue == 0)
                _chip(context, 'Reading plan not set'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.event_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(group.schedule.isEmpty
                    ? 'Meeting not set'
                    : group.schedule),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.people_outline, size: 18),
              const SizedBox(width: 6),
              Text('${group.memberCount}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: Theme.of(context).dividerColor),
    );
  }
}

class _EmptyStudyGroups extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyStudyGroups({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
