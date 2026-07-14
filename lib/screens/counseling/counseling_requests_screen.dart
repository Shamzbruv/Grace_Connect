import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/counseling_request_model.dart';
import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/counseling_service.dart';
import '../../services/user_service.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_scaffold.dart';

class CounselingRequestsScreen extends StatelessWidget {
  const CounselingRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userProfile = context.watch<UserRoleProvider>().userProfile;
    final churchId = userProfile?.churchId;
    final capabilities = userProfile?.capabilities;
    final canManageAllCases = capabilities?.canManageCareCases == true;
    final canViewAssignedCases = capabilities?.canViewAssignedCareCases == true;

    if (churchId == null || churchId.isEmpty) {
      return const AppScaffold(
        title: 'Counseling Requests',
        body: Center(child: Text('Join a church to manage counseling.')),
      );
    }

    if (!canManageAllCases && !canViewAssignedCases) {
      return const AppScaffold(
        title: 'Counseling Requests',
        body:
            Center(child: Text('You do not have access to counseling cases.')),
      );
    }

    final requestStream = canManageAllCases
        ? CounselingService().getChurchRequests(churchId)
        : CounselingService().getAssignedRequests(churchId, userProfile!.uid);

    return AppScaffold(
      title: canManageAllCases ? 'Counseling Requests' : 'Assigned Counseling',
      body: StreamBuilder<List<CounselingRequest>>(
        stream: requestStream,
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
                canManageAllCases
                    ? 'No counseling requests yet.'
                    : 'No counseling cases have been assigned to you yet.',
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              return _CounselingRequestCard(
                request: requests[index],
                canManageAssignments: canManageAllCases,
                canUpdateStatus: canManageAllCases || canViewAssignedCases,
                canDelete: canManageAllCases,
              );
            },
          );
        },
      ),
    );
  }
}

class _CounselingRequestCard extends StatelessWidget {
  const _CounselingRequestCard({
    required this.request,
    required this.canManageAssignments,
    required this.canUpdateStatus,
    required this.canDelete,
  });

  final CounselingRequest request;
  final bool canManageAssignments;
  final bool canUpdateStatus;
  final bool canDelete;

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete counseling request?'),
        content: const Text('This removes the counseling request permanently.'),
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
      await CounselingService().deleteRequest(request.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Counseling request deleted.')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete counseling request: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final created = DateFormat('MMM d, yyyy h:mm a').format(request.createdAt);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.favorite_outline, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.category,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$created • ${request.preferredContactMethod}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (canUpdateStatus || canDelete)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (canUpdateStatus)
                      _StatusMenu(
                        requestId: request.id,
                        currentStatus: request.status,
                      ),
                    if (canDelete)
                      IconButton(
                        tooltip: 'Delete counseling request',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _confirmDelete(context),
                      ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ChipLabel(label: request.urgency),
              _ChipLabel(label: request.status),
            ],
          ),
          if (request.description.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(request.description),
          ],
          if (canManageAssignments) ...[
            const SizedBox(height: 14),
            _CareTeamAssignment(request: request),
          ] else if (request.assignedToHelperId != null) ...[
            const SizedBox(height: 14),
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

class _CareTeamAssignment extends StatelessWidget {
  const _CareTeamAssignment({required this.request});

  final CounselingRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return StreamBuilder<List<UserProfile>>(
      stream: UserService().getMembers(request.churchId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'Could not load care team.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          );
        }

        final careTeam = (snapshot.data ?? const <UserProfile>[])
            .where(_isCareTeamMember)
            .toList();

        final selectedValue =
            careTeam.any((member) => member.uid == request.assignedToHelperId)
                ? request.assignedToHelperId!
                : '';

        return DropdownButtonFormField<String>(
          // ignore: deprecated_member_use
          value: selectedValue,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'Assigned counselor',
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
            ...careTeam.map(
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

                  await CounselingService().assignHelper(
                    request.id,
                    helperId,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        helperId == null
                            ? 'Counselor removed'
                            : 'Counselor assigned',
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

bool _isCareTeamMember(UserProfile member) {
  const careRoles = {
    'counselor',
    'care_counseling_coordinator',
    'pastor',
    'senior_pastor',
    'assistant_pastor',
    'acting_pastor',
    'admin',
    'administrator',
    'church_admin',
    'deacon',
    'deaconess',
    'elder',
  };

  return member.roles.map(_normalizeRole).any(careRoles.contains);
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

class _StatusMenu extends StatelessWidget {
  const _StatusMenu({
    required this.requestId,
    required this.currentStatus,
  });

  final String requestId;
  final String currentStatus;

  @override
  Widget build(BuildContext context) {
    const statuses = ['pending', 'scheduled', 'completed', 'cancelled'];

    return PopupMenuButton<String>(
      tooltip: 'Update status',
      initialValue: statuses.contains(currentStatus) ? currentStatus : null,
      onSelected: (status) async {
        await CounselingService().updateStatus(requestId, status);
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

class _ChipLabel extends StatelessWidget {
  const _ChipLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
    );
  }
}
