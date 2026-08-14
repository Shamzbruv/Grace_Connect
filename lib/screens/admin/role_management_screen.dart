import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/rbac_config.dart';
import '../../models/role_system/church_role.dart';
import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/role_service.dart';
import '../../services/user_service.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_loader.dart';
import '../../widgets/ui/app_scaffold.dart';

class RoleManagementScreen extends StatefulWidget {
  const RoleManagementScreen({super.key});

  @override
  State<RoleManagementScreen> createState() => _RoleManagementScreenState();
}

class _RoleManagementScreenState extends State<RoleManagementScreen> {
  final RoleService _roleService = RoleService();
  final UserService _userService = UserService();
  final TextEditingController _searchController = TextEditingController();

  String? _churchId;
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final userData = await Supabase.instance.client
          .from('users')
          .select('placeId')
          .eq('uid', user.id)
          .maybeSingle();
      if (mounted) {
        setState(() => _churchId = userData?['placeId']);
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<bool> _saveRoles(
    UserProfile member,
    Set<String> selectedRoles,
    Set<String> selectedPrivileges,
  ) async {
    final churchId = _churchId;
    if (churchId == null || churchId.isEmpty) return false;

    if (selectedRoles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A member needs at least one role.')),
      );
      return false;
    }

    try {
      final currentRoles = member.roles.toSet();
      final rolesToAdd = selectedRoles.difference(currentRoles);
      final rolesToRemove = currentRoles.difference(selectedRoles);

      for (final role in rolesToAdd) {
        await _roleService.assignRole(member.uid, role, churchId);
      }
      for (final role in rolesToRemove) {
        await _roleService.removeRole(member.uid, role, churchId);
      }
      await _roleService.updatePrivileges(
        member.uid,
        selectedPrivileges,
        churchId,
      );

      if (!mounted) return false;
      await context.read<UserRoleProvider>().refreshProfile();
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Roles updated for ${member.fullName}.')),
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update roles: $e')),
      );
      return false;
    }
  }

  void _toggleInlineEditor(UserProfile member) {
    if (context.read<UserRoleProvider>().userProfile?.canManageRoles != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You do not have permission to assign roles.')),
      );
      return;
    }

    _showRoleEditorSheet(member);
  }

  Future<void> _showRoleEditorSheet(UserProfile member) async {
    final selectedRoles = member.roles.toSet();
    final selectedPrivileges = member.appPrivileges.toSet();
    var isSaving = false;
    var roleSearchQuery = '';
    var privilegesExpanded = selectedPrivileges.isNotEmpty;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final displayName =
                member.fullName.isEmpty ? member.email : member.fullName;

            return SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.86,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(sheetContext)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close),
                          onPressed: isSaving
                              ? null
                              : () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          'Ministry Roles',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          decoration: const InputDecoration(
                            labelText: 'Search roles',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (value) {
                            setSheetState(() {
                              roleSearchQuery = value.trim().toLowerCase();
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        ..._buildRoleCategoryTiles(
                          context: context,
                          roleSearchQuery: roleSearchQuery,
                          selectedRoles: selectedRoles,
                          selectedPrivileges: selectedPrivileges,
                          isSaving: isSaving,
                          setSheetState: setSheetState,
                          onRoleAdded: () {
                            privilegesExpanded = true;
                          },
                        ),
                        const Divider(height: 28),
                        ExpansionTile(
                          initiallyExpanded: privilegesExpanded,
                          leading: const Icon(Icons.admin_panel_settings),
                          title: const Text('App Privileges'),
                          subtitle: const Text(
                            'Grant exact app access separately from ministry titles.',
                          ),
                          onExpansionChanged: (expanded) {
                            privilegesExpanded = expanded;
                          },
                          children: [
                            for (final group in _permissionGroups().entries)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 4,
                                      ),
                                      child: Text(
                                        group.key,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w900,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                      ),
                                    ),
                                    for (final permission in group.value)
                                      CheckboxListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                          horizontal: 16,
                                        ),
                                        title: Text(
                                          _permissionLabel(permission),
                                        ),
                                        subtitle: Text(
                                          _permissionDescription(permission),
                                        ),
                                        value: selectedPrivileges
                                            .contains(permission.name),
                                        onChanged: isSaving
                                            ? null
                                            : (value) {
                                                setSheetState(() {
                                                  if (value == true) {
                                                    selectedPrivileges
                                                        .add(permission.name);
                                                  } else {
                                                    selectedPrivileges.remove(
                                                        permission.name);
                                                  }
                                                });
                                              },
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      10,
                      16,
                      MediaQuery.of(sheetContext).padding.bottom + 16,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: isSaving
                                ? null
                                : () => Navigator.pop(sheetContext),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: isSaving
                                ? null
                                : () async {
                                    setSheetState(() => isSaving = true);
                                    final saved = await _saveRoles(
                                      member,
                                      selectedRoles,
                                      selectedPrivileges,
                                    );
                                    if (sheetContext.mounted) {
                                      if (saved) {
                                        Navigator.pop(sheetContext);
                                      } else {
                                        setSheetState(() => isSaving = false);
                                      }
                                    }
                                  },
                            icon: isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.save_outlined),
                            label: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<Widget> _buildRoleCategoryTiles({
    required BuildContext context,
    required String roleSearchQuery,
    required Set<String> selectedRoles,
    required Set<String> selectedPrivileges,
    required bool isSaving,
    required StateSetter setSheetState,
    required VoidCallback onRoleAdded,
  }) {
    final grouped = <String, List<_RoleOption>>{};
    for (final option in _getAllowedRoleOptions()) {
      final matchesSearch = roleSearchQuery.isEmpty ||
          option.name.toLowerCase().contains(roleSearchQuery) ||
          option.category.toLowerCase().contains(roleSearchQuery) ||
          _roleDescription(option.name).toLowerCase().contains(roleSearchQuery);
      if (!matchesSearch) continue;
      grouped.putIfAbsent(option.category, () => []).add(option);
    }

    if (grouped.isEmpty) {
      return [
        const AppCard(child: Text('No roles match that search.')),
      ];
    }

    return grouped.entries.map((entry) {
      final selectedCount =
          entry.value.where((role) => selectedRoles.contains(role.name)).length;
      return ExpansionTile(
        initiallyExpanded: roleSearchQuery.isNotEmpty || selectedCount > 0,
        title: Text(entry.key),
        subtitle: Text(
          selectedCount == 0
              ? '${entry.value.length} role${entry.value.length == 1 ? '' : 's'}'
              : '$selectedCount selected',
        ),
        children: [
          for (final option in entry.value)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(option.name),
              subtitle: Text(
                _roleDescription(option.name),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              value: selectedRoles.contains(option.name),
              onChanged: isSaving
                  ? null
                  : (value) {
                      setSheetState(() {
                        if (value == true) {
                          selectedRoles.add(option.name);
                          final recommended =
                              _recommendedPrivilegesForRoles({option.name});
                          selectedPrivileges.addAll(recommended);
                          if (recommended.isNotEmpty) onRoleAdded();
                        } else {
                          selectedRoles.remove(option.name);
                        }
                      });
                    },
            ),
        ],
      );
    }).toList();
  }

  List<_RoleOption> _getAllowedRoleOptions() {
    final byName = <String, _RoleOption>{
      for (final role in churchRoleRegistry)
        role.name: _RoleOption(role.name, role.category),
      'Admin': const _RoleOption('Admin', catGovernance),
      'Church Admin': const _RoleOption('Church Admin', catGovernance),
      'Prayer Warrior': const _RoleOption('Prayer Warrior', catPrayerCare),
      'Counselor': const _RoleOption('Counselor', catPrayerCare),
      'Media Team': const _RoleOption('Media Team', catWorshipMedia),
      'Usher Lead': const _RoleOption('Usher Lead', catService),
      'Sunday School Leader':
          const _RoleOption('Sunday School Leader', catTeaching),
    };

    return byName.values.toList()
      ..sort((a, b) {
        final categoryCompare =
            a.category.toLowerCase().compareTo(b.category.toLowerCase());
        if (categoryCompare != 0) return categoryCompare;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  }

  String _roleDescription(String role) {
    final normalized = _normalizeRole(role);
    final alias = switch (normalized) {
      'admin' => 'church_admin',
      'secretary' => 'church_secretary',
      'prayer_warrior' => 'intercessor',
      'usher_lead' => 'head_usher',
      'sunday_school_leader' => 'sunday_school_superintendent',
      _ => normalized,
    };

    for (final churchRole in churchRoleRegistry) {
      if (churchRole.id == alias) {
        final duty = churchRole.platformDuties.isNotEmpty
            ? churchRole.platformDuties.first
            : churchRole.description;
        return duty;
      }
    }

    if (normalized == 'church_admin') {
      return 'Administrative access for member records and operations.';
    }

    return 'Standard church platform access for this ministry role.';
  }

  Set<String> _recommendedPrivilegesForRoles(Set<String> roles) {
    final permissions =
        RBACConfig.getPermissionsForRoles(roles.toList()).toSet();
    final normalizedRoles = roles.map(_normalizeRole).toSet();

    final isLeaderRole = normalizedRoles.any((role) =>
        role.contains('director') ||
        role.contains('coordinator') ||
        role.contains('superintendent') ||
        role.contains('leader'));
    final isCommunicationsRole = normalizedRoles.any((role) =>
        role.contains('secretary') ||
        role.split('_').contains('pro') ||
        role.contains('public_relations') ||
        role.contains('announcement_reader') ||
        role.contains('social_media'));
    final isFinanceRole = normalizedRoles.any((role) =>
        role.contains('treasurer') ||
        role.contains('financial') ||
        role.contains('fundraising'));
    final isMediaRole = normalizedRoles.any((role) =>
        role.contains('media') ||
        role.contains('technical') ||
        role.contains('sound_engineer') ||
        role.contains('camera_operator') ||
        role.contains('live_stream'));

    if (isLeaderRole) {
      permissions.add(AppPermission.createAnnouncement);
      permissions.add(AppPermission.createEvents);
    }
    if (isCommunicationsRole) {
      permissions.add(AppPermission.createAnnouncement);
      permissions.add(AppPermission.sendPushNotification);
    }
    if (isFinanceRole) {
      permissions.add(AppPermission.viewFinanceDashboard);
    }
    if (isMediaRole) {
      permissions.add(AppPermission.manageLivestream);
      permissions.add(AppPermission.pinPost);
    }

    return permissions.map((permission) => permission.name).toSet();
  }

  Map<String, List<AppPermission>> _permissionGroups() {
    return const {
      'Administration': [
        AppPermission.approveMembers,
        AppPermission.manageChurchSettings,
        AppPermission.manageRoles,
        AppPermission.viewOperationalAnalytics,
      ],
      'Finance': [
        AppPermission.viewFinanceDashboard,
        AppPermission.manageFinances,
        AppPermission.approveFinanceReports,
        AppPermission.manageChurchSubscription,
      ],
      'Community & Content': [
        AppPermission.createAnnouncement,
        AppPermission.sendPushNotification,
        AppPermission.pinPost,
        AppPermission.moderateCommunity,
        AppPermission.createEvents,
      ],
      'Ministries': [
        AppPermission.manageSundaySchool,
        AppPermission.manageLivestream,
        AppPermission.manageWorship,
      ],
      'Care & Prayer': [
        AppPermission.managePrayerRequests,
        AppPermission.assignCareRequests,
        AppPermission.viewPriorityList,
        AppPermission.managePriorityList,
      ],
      'Attendance & Scheduling': [
        AppPermission.manualCheckIn,
        AppPermission.viewAttendanceInsights,
        AppPermission.manageSchedule,
      ],
    };
  }

  String _permissionLabel(AppPermission permission) {
    return switch (permission) {
      AppPermission.approveMembers => 'Approve Members',
      AppPermission.manageChurchSettings => 'Manage Church Settings',
      AppPermission.manageRoles => 'Manage Roles',
      AppPermission.viewOperationalAnalytics => 'View Analytics',
      AppPermission.viewFinanceDashboard => 'View Finance Dashboard',
      AppPermission.manageFinances => 'Manage Finances',
      AppPermission.approveFinanceReports => 'Approve Finance Reports',
      AppPermission.manageChurchSubscription => 'Manage Church Subscription',
      AppPermission.createAnnouncement => 'Create Announcements',
      AppPermission.sendPushNotification => 'Send Push Notifications',
      AppPermission.pinPost => 'Pin Posts',
      AppPermission.moderateCommunity => 'Moderate Community',
      AppPermission.createEvents => 'Create Events',
      AppPermission.manageSundaySchool => 'Manage Sunday School',
      AppPermission.manageLivestream => 'Manage Livestream',
      AppPermission.manageWorship => 'Manage Worship',
      AppPermission.managePrayerRequests => 'Manage Prayer Requests',
      AppPermission.assignCareRequests => 'Assign Care Requests',
      AppPermission.manualCheckIn => 'Manual Check-In',
      AppPermission.viewAttendanceInsights => 'View Attendance Insights',
      AppPermission.viewPriorityList => 'View Priority List',
      AppPermission.managePriorityList => 'Manage Priority List',
      AppPermission.manageSchedule => 'Manage Schedule',
    };
  }

  String _permissionDescription(AppPermission permission) {
    return switch (permission) {
      AppPermission.approveMembers => 'Approve or decline member requests.',
      AppPermission.manageChurchSettings => 'Edit church-wide setup.',
      AppPermission.manageRoles => 'Assign roles and app privileges.',
      AppPermission.viewOperationalAnalytics => 'Open operational reports.',
      AppPermission.viewFinanceDashboard =>
        'View giving and finance summaries.',
      AppPermission.manageFinances => 'Create and edit finance records.',
      AppPermission.approveFinanceReports => 'Review finance reports.',
      AppPermission.manageChurchSubscription =>
        'View pricing and submit church billing or subscription requests.',
      AppPermission.createAnnouncement => 'Post official announcements.',
      AppPermission.sendPushNotification => 'Notify users about updates.',
      AppPermission.pinPost => 'Pin important community posts.',
      AppPermission.moderateCommunity => 'Moderate posts and reports.',
      AppPermission.createEvents => 'Create church or ministry events.',
      AppPermission.manageSundaySchool => 'Manage Sunday School workflows.',
      AppPermission.manageLivestream => 'Manage live service media.',
      AppPermission.manageWorship => 'Manage worship planning.',
      AppPermission.managePrayerRequests =>
        'Receive and update assigned prayer or care requests.',
      AppPermission.assignCareRequests =>
        'Assign confidential prayer and counseling requests to trusted helpers.',
      AppPermission.manualCheckIn => 'Check people in manually.',
      AppPermission.viewAttendanceInsights => 'Review attendance details.',
      AppPermission.viewPriorityList => 'View urgent care items.',
      AppPermission.managePriorityList => 'Resolve urgent care items.',
      AppPermission.manageSchedule => 'Create recurring service schedules.',
    };
  }

  String _normalizeRole(String role) {
    return role
        .trim()
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserRoleProvider>();
    final canManageRoles = userProvider.userProfile?.canManageRoles == true;

    if (_isLoading || _churchId == null) {
      return const AppScaffold(
        title: 'Role Management',
        body: Center(child: AppLoader()),
      );
    }

    return AppScaffold(
      title: 'Role Management',
      body: !canManageRoles
          ? const Center(child: Text('You do not have access to assign roles.'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search members by name or email',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          ),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value.trim().toLowerCase());
                  },
                ),
                const SizedBox(height: 16),
                _SectionHeader(
                  title: 'Members',
                  subtitle: 'Tap a member to assign or remove roles.',
                ),
                const SizedBox(height: 10),
                StreamBuilder<List<UserProfile>>(
                  stream: _userService.getMembers(_churchId!),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return AppCard(
                        child:
                            Text('Could not load members: ${snapshot.error}'),
                      );
                    }

                    if (!snapshot.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: AppLoader()),
                      );
                    }

                    final members = snapshot.data!.where((member) {
                      if (_searchQuery.isEmpty) return true;
                      return member.fullName
                              .toLowerCase()
                              .contains(_searchQuery) ||
                          member.email.toLowerCase().contains(_searchQuery);
                    }).toList()
                      ..sort((a, b) => a.fullName.compareTo(b.fullName));

                    if (members.isEmpty) {
                      return const AppCard(
                        child: Text('No members match that search.'),
                      );
                    }

                    return Column(
                      children: members.map((member) {
                        return _MemberRoleCard(
                          member: member,
                          isEditing: false,
                          onTap: () => _toggleInlineEditor(member),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 24),
                AppCard(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history_outlined),
                    title: const Text('Role Change History'),
                    subtitle:
                        const Text('Review role updates with date filters.'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              RoleHistoryScreen(churchId: _churchId!),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class RoleHistoryScreen extends StatefulWidget {
  const RoleHistoryScreen({super.key, required this.churchId});

  final String churchId;

  @override
  State<RoleHistoryScreen> createState() => _RoleHistoryScreenState();
}

class _RoleHistoryScreenState extends State<RoleHistoryScreen> {
  final RoleService _roleService = RoleService();
  final SupabaseClient _supabase = Supabase.instance.client;
  static final List<_RoleHistoryFilter> _filters = [
    _RoleHistoryFilter(
        '7 days', DateTime.now().subtract(const Duration(days: 7))),
    _RoleHistoryFilter(
        '30 days', DateTime.now().subtract(const Duration(days: 30))),
    _RoleHistoryFilter(
      '6 months',
      DateTime.now().subtract(const Duration(days: 183)),
    ),
    _RoleHistoryFilter(
      '1 year',
      DateTime.now().subtract(const Duration(days: 365)),
    ),
    const _RoleHistoryFilter('All', null),
  ];

  _RoleHistoryFilter _selectedFilter = _filters[1];
  final Map<String, _AuditPerson> _auditPeople = {};
  final Set<String> _loadingAuditPeople = {};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Role History',
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              scrollDirection: Axis.horizontal,
              itemBuilder: (context, index) {
                final filter = _filters[index];
                return ChoiceChip(
                  label: Text(filter.label),
                  selected: _selectedFilter.label == filter.label,
                  onSelected: (_) {
                    setState(() => _selectedFilter = filter);
                  },
                );
              },
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemCount: _filters.length,
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _roleService.getAuditLogs(widget.churchId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Could not load logs: ${snapshot.error}'),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: AppLoader());
                }

                final logs = snapshot.data!.where((log) {
                  final action = log['action']?.toString() ?? '';
                  final timestamp = _parseTimestamp(log['timestamp']);
                  final since = _selectedFilter.since;
                  final isRoleChange = action.startsWith('role_') ||
                      action == 'privileges_updated';
                  return isRoleChange &&
                      (since == null ||
                          timestamp == null ||
                          timestamp.isAfter(since));
                }).toList();

                _queueAuditPeopleLoad(logs);

                if (logs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No role changes found for this filter.'),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[index];
                    final details =
                        Map<String, dynamic>.from(log['details'] ?? {});
                    final roleChanged =
                        details['roleChanged']?.toString() ?? 'Role';
                    final targetUid = (details['targetUid'] ??
                            log['targetUid'] ??
                            log['target_uid'] ??
                            '')
                        .toString();
                    final performedBy =
                        (log['performedBy'] ?? log['performed_by'] ?? '')
                            .toString();
                    final timestamp = _parseTimestamp(log['timestamp']);
                    final formattedTime = timestamp == null
                        ? 'Just now'
                        : DateFormat.yMMMd().add_jm().format(timestamp);
                    final action = log['action']?.toString() ?? '';
                    final isPrivilegeUpdate = action == 'privileges_updated';
                    final isRemoval = action == 'role_removed';
                    final verb = isRemoval ? 'removed from' : 'assigned to';
                    final privilegesAfter = List<String>.from(
                        details['privilegesAfter'] ?? const []);
                    final targetName =
                        details['targetName']?.toString().trim().isNotEmpty ==
                                true
                            ? details['targetName'].toString()
                            : _personLabel(targetUid, 'member');
                    final actorName = details['performedByName']
                                ?.toString()
                                .trim()
                                .isNotEmpty ==
                            true
                        ? details['performedByName'].toString()
                        : _personLabel(performedBy, 'leader');
                    final targetSubtitle = _personSubtitle(targetUid);
                    final actorSubtitle = _personSubtitle(performedBy);

                    return AppCard(
                      margin: const EdgeInsets.only(bottom: 10),
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor:
                                (isRemoval ? Colors.orange : Colors.green)
                                    .withValues(alpha: 0.14),
                            child: Icon(
                              isRemoval
                                  ? Icons.remove_moderator_outlined
                                  : Icons.verified_user_outlined,
                              color: isRemoval ? Colors.orange : Colors.green,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isPrivilegeUpdate
                                      ? 'App privileges updated'
                                      : isRemoval
                                          ? '$roleChanged removed'
                                          : '$roleChanged assigned',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  isPrivilegeUpdate
                                      ? 'App access privileges were updated for $targetName.'
                                      : '$roleChanged was $verb $targetName.',
                                  style: theme.textTheme.bodyMedium,
                                ),
                                if (isPrivilegeUpdate) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    privilegesAfter.isEmpty
                                        ? 'No extra app privileges are currently granted.'
                                        : 'Granted: ${privilegesAfter.map(_prettifyPrivilege).join(', ')}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Text(
                                  'For: $targetName'
                                  '${targetSubtitle == null ? '' : ' - $targetSubtitle'}\n'
                                  'Changed by: $actorName'
                                  '${actorSubtitle == null ? '' : ' - $actorSubtitle'}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  formattedTime,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  DateTime? _parseTimestamp(dynamic value) {
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }

  void _queueAuditPeopleLoad(List<Map<String, dynamic>> logs) {
    final ids = <String>{};

    for (final log in logs) {
      final details = Map<String, dynamic>.from(log['details'] ?? {});
      for (final value in [
        details['targetUid'],
        log['targetUid'],
        log['target_uid'],
        log['performedBy'],
        log['performed_by'],
      ]) {
        final id = value?.toString() ?? '';
        if (id.isNotEmpty &&
            !_auditPeople.containsKey(id) &&
            !_loadingAuditPeople.contains(id)) {
          ids.add(id);
        }
      }
    }

    if (ids.isEmpty) return;
    _loadingAuditPeople.addAll(ids);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAuditPeople(ids.toList());
    });
  }

  Future<void> _loadAuditPeople(List<String> uids) async {
    try {
      final rows = await _supabase
          .from('users')
          .select('uid, fullName, email')
          .inFilter('uid', uids);

      if (!mounted) return;
      setState(() {
        for (final row in rows) {
          final person = _AuditPerson.fromMap(row);
          if (person.uid.isNotEmpty) {
            _auditPeople[person.uid] = person;
          }
        }
        for (final uid in uids) {
          _auditPeople.putIfAbsent(uid, () => _AuditPerson.unknown(uid));
        }
        _loadingAuditPeople.removeAll(uids);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        for (final uid in uids) {
          _auditPeople.putIfAbsent(uid, () => _AuditPerson.unknown(uid));
        }
        _loadingAuditPeople.removeAll(uids);
      });
    }
  }

  String _personLabel(String uid, String fallbackKind) {
    if (uid.isEmpty) return fallbackKind == 'leader' ? 'A leader' : 'A member';
    return _auditPeople[uid]?.label ?? _shortIdLabel(uid, fallbackKind);
  }

  String? _personSubtitle(String uid) {
    if (uid.isEmpty) return null;
    final subtitle = _auditPeople[uid]?.subtitle;
    if (subtitle == null || subtitle == uid) return null;
    return subtitle;
  }

  String _shortIdLabel(String uid, String fallbackKind) {
    final prefix = fallbackKind == 'leader' ? 'Leader' : 'Member';
    final shortId = uid.length <= 8 ? uid : uid.substring(0, 8);
    return '$prefix $shortId';
  }

  String _prettifyPrivilege(String value) {
    final words = value
        .replaceAllMapped(
          RegExp(r'([a-z])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .replaceAll('_', ' ')
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1))
        .join(' ');
    return words.isEmpty ? value : words;
  }
}

class _AuditPerson {
  const _AuditPerson({
    required this.uid,
    required this.label,
    this.subtitle,
  });

  final String uid;
  final String label;
  final String? subtitle;

  factory _AuditPerson.fromMap(Map<String, dynamic> data) {
    final uid = data['uid']?.toString() ?? '';
    final fullName = data['fullName']?.toString().trim() ?? '';
    final email = data['email']?.toString().trim() ?? '';

    return _AuditPerson(
      uid: uid,
      label: fullName.isNotEmpty
          ? fullName
          : email.isNotEmpty
              ? email
              : uid,
      subtitle: email.isNotEmpty ? email : null,
    );
  }

  factory _AuditPerson.unknown(String uid) {
    return _AuditPerson(uid: uid, label: uid);
  }
}

class _RoleHistoryFilter {
  const _RoleHistoryFilter(this.label, this.since);

  final String label;
  final DateTime? since;
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberRoleCard extends StatelessWidget {
  const _MemberRoleCard({
    required this.member,
    required this.isEditing,
    required this.onTap,
  });

  final UserProfile member;
  final bool isEditing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _MemberAvatar(member: member),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.fullName.isEmpty
                            ? member.email
                            : member.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        member.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final role in member.roles.take(4))
                            Chip(
                              label: Text(role),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          if (member.appPrivileges.isNotEmpty)
                            Chip(
                              avatar: const Icon(Icons.key_outlined, size: 16),
                              label: Text(
                                  '${member.appPrivileges.length} privileges'),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: onTap,
                  tooltip: isEditing ? 'Close role editor' : 'Manage roles',
                  icon: Icon(
                    isEditing ? Icons.keyboard_arrow_up : Icons.edit_outlined,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({required this.member});

  final UserProfile member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = member.fullName.isNotEmpty
        ? member.fullName.characters.first.toUpperCase()
        : '?';

    return CircleAvatar(
      radius: 24,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.16),
      backgroundImage:
          member.photoUrl.isNotEmpty ? NetworkImage(member.photoUrl) : null,
      child: member.photoUrl.isEmpty
          ? Text(
              fallback,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            )
          : null,
    );
  }
}

class _RoleOption {
  const _RoleOption(this.name, this.category);

  final String name;
  final String category;
}
