import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../providers/user_role_provider.dart';
import '../../services/study_group_service.dart';
import '../../models/study_group_model.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_loader.dart';
import '../../widgets/ui/app_text_field.dart';
import 'study_group_detail_screen.dart';

class StudyGroupListScreen extends StatefulWidget {
  const StudyGroupListScreen({super.key});

  @override
  State<StudyGroupListScreen> createState() => _StudyGroupListScreenState();
}

class _StudyGroupListScreenState extends State<StudyGroupListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final StudyGroupService _service = StudyGroupService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  void _showCreateDialog() {
    final nameController = TextEditingController();
    final topicController = TextEditingController();
    final schedController = TextEditingController();
    final descController = TextEditingController();
    var requireApproval = true;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create Study Group'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppTextField(controller: nameController, label: 'Group Name'),
                const SizedBox(height: 8),
                AppTextField(
                    controller: topicController, label: 'Topic (e.g. Romans)'),
                const SizedBox(height: 8),
                AppTextField(
                    controller: schedController,
                    label: 'Schedule (e.g. Tue 7pm)'),
                const SizedBox(height: 8),
                AppTextField(
                    controller: descController,
                    label: 'Description',
                    maxLines: 2),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Require admin approval'),
                  value: requireApproval,
                  onChanged: (value) {
                    setDialogState(() => requireApproval = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final user = Supabase.instance.client.auth.currentUser;
                final profile =
                    Provider.of<UserRoleProvider>(context, listen: false)
                        .userProfile;
                if (user != null && nameController.text.isNotEmpty) {
                  final group = StudyGroup(
                    id: const Uuid().v4(),
                    name: nameController.text,
                    topic: topicController.text,
                    description: descController.text,
                    leaderId: user.id,
                    leaderName: profile?.fullName ?? 'Unknown',
                    adminIds: [user.id],
                    memberIds: [user.id], // Leader is member
                    pendingMemberIds: const [],
                    schedule: schedController.text,
                    churchId: profile?.placeId ?? '',
                    createdAt: DateTime.now(),
                    requireJoinApproval: requireApproval,
                  );
                  await _service.createGroup(group);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                }
              },
              child: const Text('Create'),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<UserRoleProvider>(context).userProfile;
    final churchId = profile?.placeId;

    return AppScaffold(
      title: 'Study Groups',
      showBottomMenu: true,
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateDialog,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: Icon(Icons.add, color: Theme.of(context).colorScheme.onPrimary),
      ),
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Theme.of(context).unselectedWidgetColor,
            indicatorColor: Theme.of(context).colorScheme.primary,
            tabs: const [
              Tab(text: 'My Groups'),
              Tab(text: 'Browse Church Groups'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGroupList(_service.getMyGroups(profile?.uid ?? ''), true),
                _buildGroupList(
                    _service.getGroupsForChurch(churchId ?? ''), false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupList(Stream<List<StudyGroup>> stream, bool isMyGroups) {
    return StreamBuilder<List<StudyGroup>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: AppPageLoader()); // Or skeleton
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
              child: Text(isMyGroups
                  ? 'You haven\'t joined any groups yet.'
                  : 'No groups found.'));
        }

        final groups = snapshot.data!;
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            final uid = Supabase.instance.client.auth.currentUser?.id ?? '';
            final isMember = group.memberIds.contains(uid) ||
                group.adminIds.contains(uid) ||
                group.leaderId == uid;
            final isPending = group.pendingMemberIds.contains(uid);
            return AppCard(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      Theme.of(context).colorScheme.primaryContainer,
                  child: Icon(Icons.group,
                      color: Theme.of(context).colorScheme.onPrimaryContainer),
                ),
                title: Text(group.name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('${group.topic} • ${group.schedule}'),
                trailing: isMember
                    ? const Icon(Icons.chevron_right)
                    : isPending
                        ? const Chip(
                            label: Text('Requested'),
                            visualDensity: VisualDensity.compact,
                          )
                        : const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) =>
                              StudyGroupDetailScreen(group: group)));
                },
              ),
            );
          },
        );
      },
    );
  }
}
