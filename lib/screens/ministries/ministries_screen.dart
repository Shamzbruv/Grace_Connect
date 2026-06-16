import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/ministry.dart';
import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/ministry_service.dart';
import '../../widgets/ui/app_button.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_text_field.dart';

class MinistriesScreen extends StatefulWidget {
  const MinistriesScreen({super.key});

  @override
  State<MinistriesScreen> createState() => _MinistriesScreenState();
}

class _MinistriesScreenState extends State<MinistriesScreen> {
  final MinistryService _service = MinistryService();

  Future<void> _showMinistrySheet({
    Ministry? ministry,
  }) async {
    final nameController = TextEditingController(text: ministry?.name ?? '');
    final descriptionController =
        TextEditingController(text: ministry?.description ?? '');
    var status = ministry?.status ?? 'active';
    var isSaving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final bottomPadding = MediaQuery.viewInsetsOf(sheetContext).bottom;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> save() async {
              final name = nameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Add a ministry name.')),
                );
                return;
              }

              setSheetState(() => isSaving = true);
              try {
                if (ministry == null) {
                  await _service.createMinistry(
                    name: name,
                    description: descriptionController.text,
                  );
                } else {
                  await _service.updateMinistry(
                    ministry: ministry,
                    name: name,
                    description: descriptionController.text,
                    status: status,
                  );
                }

                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ministry == null
                        ? 'Ministry created.'
                        : 'Ministry updated.'),
                  ),
                );
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Could not save ministry: $error')),
                );
              } finally {
                if (context.mounted) setSheetState(() => isSaving = false);
              }
            }

            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + bottomPadding),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ministry == null ? 'Create Ministry' : 'Edit Ministry',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Create ministry areas such as Youth, Worship, Media, Sunday School, Outreach, or Prayer.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 18),
                    AppTextField(
                      controller: nameController,
                      label: 'Ministry Name',
                      hint: 'Example: Youth Ministry',
                    ),
                    const SizedBox(height: 14),
                    AppTextField(
                      controller: descriptionController,
                      label: 'Description',
                      hint: 'What does this ministry handle?',
                      maxLines: 4,
                    ),
                    if (ministry != null) ...[
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: status,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          prefixIcon: Icon(Icons.flag_outlined),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('Active'),
                          ),
                          DropdownMenuItem(
                            value: 'archived',
                            child: Text('Archived'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setSheetState(() => status = value);
                        },
                      ),
                    ],
                    const SizedBox(height: 22),
                    AppButton(
                      text: ministry == null ? 'Create Ministry' : 'Save',
                      icon: Icons.save_outlined,
                      isLoading: isSaving,
                      onPressed: save,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    descriptionController.dispose();
  }

  Future<void> _showManagerSheet(Ministry ministry) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MinistryManagerSheet(
        ministry: ministry,
        service: _service,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<UserRoleProvider>().userProfile;
    final canManage = _service.canManageMinistrySetup(user);
    final churchId = user?.churchId ?? '';

    return AppScaffold(
      title: 'Ministries',
      actions: [
        if (canManage)
          IconButton(
            tooltip: 'Create ministry',
            onPressed: () => _showMinistrySheet(),
            icon: const Icon(Icons.add_circle_outline),
          ),
      ],
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _showMinistrySheet(),
              icon: const Icon(Icons.group_add_outlined),
              label: const Text('Create'),
            )
          : null,
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : churchId.isEmpty
              ? const Center(child: Text('Join a church to view ministries.'))
              : StreamBuilder<List<Ministry>>(
                  stream: _service.watchMinistries(churchId),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Could not load ministries: ${snapshot.error}',
                          ),
                        ),
                      );
                    }

                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final ministries = snapshot.data ?? const <Ministry>[];
                    if (ministries.isEmpty) {
                      return _EmptyMinistries(canManage: canManage);
                    }

                    return RefreshIndicator(
                      onRefresh: () async {
                        await _service.fetchMinistries(churchId);
                      },
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        itemCount: ministries.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final ministry = ministries[index];
                          return _MinistryCard(
                            ministry: ministry,
                            canManage: canManage,
                            service: _service,
                            onEdit: () =>
                                _showMinistrySheet(ministry: ministry),
                            onManage: () => _showManagerSheet(ministry),
                          );
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

class _MinistryCard extends StatelessWidget {
  const _MinistryCard({
    required this.ministry,
    required this.canManage,
    required this.service,
    required this.onEdit,
    required this.onManage,
  });

  final Ministry ministry;
  final bool canManage;
  final MinistryService service;
  final VoidCallback onEdit;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.14),
                child: Icon(
                  Icons.groups_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ministry.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (ministry.description.trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        ministry.description.trim(),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!ministry.isActive)
                Chip(
                  label: const Text('Archived'),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
            ],
          ),
          const SizedBox(height: 14),
          FutureBuilder<List<MinistryManager>>(
            future: service.fetchMinistryManagers(ministry.id),
            builder: (context, snapshot) {
              final managers = snapshot.data ?? const <MinistryManager>[];
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Text(
                  'Loading managers...',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              }
              return Text(
                managers.isEmpty
                    ? 'No managers assigned yet.'
                    : '${managers.length} manager${managers.length == 1 ? '' : 's'} assigned',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              );
            },
          ),
          if (canManage) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edit'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onManage,
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: const Text('Managers'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MinistryManagerSheet extends StatefulWidget {
  const _MinistryManagerSheet({
    required this.ministry,
    required this.service,
  });

  final Ministry ministry;
  final MinistryService service;

  @override
  State<_MinistryManagerSheet> createState() => _MinistryManagerSheetState();
}

class _MinistryManagerSheetState extends State<_MinistryManagerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _roleController =
      TextEditingController(text: 'Ministry Manager');
  List<UserProfile> _results = [];
  UserProfile? _selectedUser;
  bool _canCreateEvents = true;
  bool _canPublishAnnouncements = true;
  bool _isSearching = false;
  bool _isAssigning = false;

  @override
  void dispose() {
    _searchController.dispose();
    _roleController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _isSearching = true);
    try {
      final rows = await widget.service.searchMembers(
        churchId: widget.ministry.churchId,
        query: _searchController.text,
      );
      if (!mounted) return;
      setState(() => _results = rows);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not search members: $error')),
      );
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _assign() async {
    final selectedUser = _selectedUser;
    if (selectedUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a member to assign.')),
      );
      return;
    }

    setState(() => _isAssigning = true);
    try {
      await widget.service.assignManager(
        ministryId: widget.ministry.id,
        userId: selectedUser.uid,
        roleTitle: _roleController.text,
        canCreateEvents: _canCreateEvents,
        canPublishAnnouncements: _canPublishAnnouncements,
      );
      if (!mounted) return;
      setState(() {
        _selectedUser = null;
        _searchController.clear();
        _results = [];
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${selectedUser.fullName} assigned.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not assign manager: $error')),
      );
    } finally {
      if (mounted) setState(() => _isAssigning = false);
    }
  }

  Future<void> _removeManager(MinistryManager manager) async {
    try {
      await widget.service.removeManager(manager.id);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${manager.userName} removed.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove manager: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomPadding = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + bottomPadding),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.ministry.name} Managers',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Managers can create ministry events and announcements based on the access you give them.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FutureBuilder<List<MinistryManager>>(
              future: widget.service.fetchMinistryManagers(widget.ministry.id),
              builder: (context, snapshot) {
                final managers = snapshot.data ?? const <MinistryManager>[];
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (managers.isEmpty) {
                  return Text(
                    'No managers assigned yet.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                }

                return Column(
                  children: managers
                      .map(
                        (manager) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundImage: manager.userPhotoUrl.isNotEmpty
                                ? NetworkImage(manager.userPhotoUrl)
                                : null,
                            child: manager.userPhotoUrl.isEmpty
                                ? Text(
                                    manager.userName.isEmpty
                                        ? 'M'
                                        : manager.userName[0].toUpperCase(),
                                  )
                                : null,
                          ),
                          title: Text(manager.userName),
                          subtitle: Text(
                            [
                              manager.roleTitle,
                              if (manager.canCreateEvents) 'events',
                              if (manager.canPublishAnnouncements)
                                'announcements',
                            ].join(' - '),
                          ),
                          trailing: IconButton(
                            tooltip: 'Remove manager',
                            onPressed: () => _removeManager(manager),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
            const Divider(height: 32),
            AppTextField(
              controller: _searchController,
              label: 'Find Member',
              hint: 'Search by name or email',
              suffixIcon: IconButton(
                onPressed: _isSearching ? null : _search,
                icon: _isSearching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
              ),
            ),
            if (_results.isNotEmpty) ...[
              const SizedBox(height: 8),
              ..._results.map(
                (user) => RadioListTile<UserProfile>(
                  value: user,
                  groupValue: _selectedUser,
                  onChanged: (value) => setState(() => _selectedUser = value),
                  title:
                      Text(user.fullName.isEmpty ? user.email : user.fullName),
                  subtitle: Text(user.email),
                ),
              ),
            ],
            const SizedBox(height: 14),
            AppTextField(
              controller: _roleController,
              label: 'Manager Title',
              hint: 'Example: Youth Director',
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Can create events'),
              subtitle:
                  const Text('Allow this manager to add ministry events.'),
              value: _canCreateEvents,
              onChanged: (value) => setState(() => _canCreateEvents = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Can publish announcements'),
              subtitle: const Text(
                  'Allow this manager to send ministry announcements.'),
              value: _canPublishAnnouncements,
              onChanged: (value) =>
                  setState(() => _canPublishAnnouncements = value),
            ),
            const SizedBox(height: 18),
            AppButton(
              text: 'Assign Manager',
              icon: Icons.person_add_alt_1_outlined,
              isLoading: _isAssigning,
              onPressed: _assign,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMinistries extends StatelessWidget {
  const _EmptyMinistries({required this.canManage});

  final bool canManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.groups_outlined,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 14),
            Text(
              'No ministries yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              canManage
                  ? 'Create ministries and assign people to manage them.'
                  : 'Ministries created by leadership will appear here.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
