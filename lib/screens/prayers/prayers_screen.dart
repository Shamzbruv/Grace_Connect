import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/prayer_request.dart';
import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/prayer_service.dart';
import '../../services/user_service.dart';
import '../../widgets/ui/app_button.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_text_field.dart';

class PrayersScreen extends StatefulWidget {
  const PrayersScreen({super.key});

  @override
  State<PrayersScreen> createState() => _PrayersScreenState();
}

class _PrayersScreenState extends State<PrayersScreen> {
  final PrayerService _service = PrayerService();
  final TextEditingController _requestController = TextEditingController();
  bool _isAnonymous = false;
  bool _isPrivate = true;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _requestController.dispose();
    super.dispose();
  }

  Future<void> _submitPrayer(UserRoleProvider provider) async {
    final user = provider.userProfile;
    final content = _requestController.text.trim();

    if (user == null || user.churchId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Join a church before submitting prayer.')),
      );
      return;
    }

    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your prayer request.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _service.submitRequest(
        PrayerRequest(
          id: '',
          userId: user.uid,
          churchId: user.churchId,
          userName: _isAnonymous ? 'Anonymous' : user.fullName,
          title: _isPrivate ? 'Private Prayer Request' : 'Prayer Request',
          content: content,
          isAnonymous: _isAnonymous,
          isPrivate: _isPrivate,
          createdAt: DateTime.now(),
        ),
      );

      _requestController.clear();
      if (!mounted) return;
      setState(() {
        _isAnonymous = false;
        _isPrivate = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prayer request submitted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit prayer: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UserRoleProvider>();
    final user = provider.userProfile;
    final canAssignPrayers = user?.capabilities.canAssignPrayers == true;
    final canViewAssignedPrayers =
        user?.capabilities.canViewAssignedCareCases == true ||
            user?.isPrayerWarrior == true;

    if (canAssignPrayers || canViewAssignedPrayers) {
      return _PrayerAdminView(
        service: _service,
        churchId: user?.churchId,
        user: user,
        canManageAssignments: canAssignPrayers,
      );
    }

    return AppScaffold(
      title: 'Prayer Requests',
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Submit Request',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 16),
                      AppTextField(
                        controller: _requestController,
                        label: 'Your Request',
                        hint:
                            'Share what you would like the church to pray for',
                        maxLines: 5,
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Keep this private'),
                        subtitle: const Text(
                            'Only prayer leaders and pastors can see it.'),
                        value: _isPrivate,
                        onChanged: (value) =>
                            setState(() => _isPrivate = value),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Submit anonymously'),
                        value: _isAnonymous,
                        onChanged: (value) =>
                            setState(() => _isAnonymous = value ?? false),
                      ),
                      const SizedBox(height: 12),
                      AppButton(
                        text: 'Submit Prayer',
                        icon: Icons.volunteer_activism_outlined,
                        isLoading: _isSubmitting,
                        onPressed: () => _submitPrayer(provider),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'My Requests',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 10),
                StreamBuilder<List<PrayerRequest>>(
                  stream: _service.getMyRequests(user.uid),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Text('Could not load requests: ${snapshot.error}');
                    }

                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final requests = snapshot.data!;
                    if (requests.isEmpty) {
                      return const AppCard(
                        child: Text('No prayer requests yet.'),
                      );
                    }

                    return Column(
                      children: requests
                          .map(
                            (request) => _PrayerRequestCard(
                              request: request,
                              showActions: false,
                              canDelete: true,
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
    );
  }
}

class _PrayerAdminView extends StatelessWidget {
  const _PrayerAdminView({
    required this.service,
    required this.churchId,
    required this.user,
    required this.canManageAssignments,
  });

  final PrayerService service;
  final String? churchId;
  final UserProfile? user;
  final bool canManageAssignments;

  @override
  Widget build(BuildContext context) {
    final effectiveChurchId = churchId;
    if (effectiveChurchId == null || effectiveChurchId.isEmpty) {
      return const AppScaffold(
        title: 'Prayer Requests',
        body: Center(child: Text('Join a church to manage prayer requests.')),
      );
    }

    final effectiveUser = user;
    if (effectiveUser == null) {
      return const AppScaffold(
        title: 'Prayer Requests',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return AppScaffold(
      title: canManageAssignments ? 'Prayer Requests' : 'Assigned Prayers',
      body: StreamBuilder<List<PrayerRequest>>(
        stream: canManageAssignments
            ? service.getChurchRequests(effectiveChurchId)
            : service.getAssignedRequests(effectiveChurchId, effectiveUser.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
                child: Text('Could not load requests: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final requests = snapshot.data!;
          if (requests.isEmpty) {
            return Center(
              child: Text(
                canManageAssignments
                    ? 'No prayer requests yet.'
                    : 'No prayer requests have been assigned to you yet.',
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _PrayerRequestCard(
              request: requests[index],
              showActions: true,
              canDelete: canManageAssignments,
              canManageAssignments: canManageAssignments,
            ),
          );
        },
      ),
    );
  }
}

class _PrayerRequestCard extends StatelessWidget {
  const _PrayerRequestCard({
    required this.request,
    required this.showActions,
    required this.canDelete,
    this.canManageAssignments = false,
  });

  final PrayerRequest request;
  final bool showActions;
  final bool canDelete;
  final bool canManageAssignments;

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete prayer request?'),
        content: const Text('This removes the prayer request permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await PrayerService().deleteRequest(request.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Prayer request deleted.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete prayer request: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final created = DateFormat('MMM d, yyyy h:mm a').format(request.createdAt);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.volunteer_activism_outlined,
                  color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${request.userName} • $created',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (showActions || canDelete)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showActions) _PrayerStatusMenu(request: request),
                    if (canDelete)
                      IconButton(
                        tooltip: 'Delete prayer request',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(context),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(request.content),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(label: request.status),
              if (request.isPrivate) const _StatusChip(label: 'Private'),
              if (request.isAnonymous) const _StatusChip(label: 'Anonymous'),
            ],
          ),
          if (canManageAssignments) ...[
            const SizedBox(height: 14),
            _PrayerAssignmentControl(request: request),
          ] else if (request.assignedToHelperId != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Assigned to you',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
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

class _PrayerAssignmentControl extends StatelessWidget {
  const _PrayerAssignmentControl({required this.request});

  final PrayerRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<List<UserProfile>>(
      stream: UserService().getMembers(request.churchId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'Could not load members for assignment.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          );
        }

        final members = (snapshot.data ?? const <UserProfile>[]).toList()
          ..sort((a, b) => a.fullName.compareTo(b.fullName));
        final selectedValue =
            members.any((member) => member.uid == request.assignedToHelperId)
                ? request.assignedToHelperId!
                : '';

        return DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: selectedValue,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Assigned helper',
            prefixIcon: const Icon(Icons.support_agent_outlined),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          items: [
            const DropdownMenuItem(
              value: '',
              child: Text('Unassigned'),
            ),
            ...members.map(
              (member) => DropdownMenuItem(
                value: member.uid,
                child: Text(
                  member.fullName.isEmpty ? member.email : member.fullName,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: snapshot.hasData
              ? (value) async {
                  final helperId =
                      value == null || value.isEmpty ? null : value;
                  if (helperId == request.assignedToHelperId) return;

                  await PrayerService().assignHelper(request.id, helperId);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        helperId == null
                            ? 'Prayer helper removed'
                            : 'Prayer helper assigned',
                      ),
                    ),
                  );
                }
              : null,
        );
      },
    );
  }
}

class _PrayerStatusMenu extends StatelessWidget {
  const _PrayerStatusMenu({required this.request});

  final PrayerRequest request;

  @override
  Widget build(BuildContext context) {
    const statuses = ['active', 'acknowledged', 'prayed', 'closed'];

    return PopupMenuButton<String>(
      tooltip: 'Update status',
      initialValue: statuses.contains(request.status) ? request.status : null,
      onSelected: (status) async {
        await PrayerService().updateStatus(request.id, status);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Marked $status')),
        );
      },
      itemBuilder: (context) => statuses
          .map(
            (status) => PopupMenuItem(
              value: status,
              child: Text(status[0].toUpperCase() + status.substring(1)),
            ),
          )
          .toList(),
      child: const Icon(Icons.more_horiz),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}
