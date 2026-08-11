import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/user_role_provider.dart';
import '../../services/notification_service.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';

class MembershipRequestsScreen extends StatefulWidget {
  const MembershipRequestsScreen({super.key});

  @override
  State<MembershipRequestsScreen> createState() =>
      _MembershipRequestsScreenState();
}

class _MembershipRequestsScreenState extends State<MembershipRequestsScreen> {
  late Future<List<Map<String, dynamic>>> _requestsFuture;

  @override
  void initState() {
    super.initState();
    _requestsFuture = _fetchRequests();
  }

  Future<List<Map<String, dynamic>>> _fetchRequests() async {
    final churchId = context.read<UserRoleProvider>().userProfile?.placeId;
    if (churchId == null || churchId.isEmpty) return const [];

    try {
      final rows = await Supabase.instance.client.rpc(
        'list_church_membership_requests',
        params: {'p_church_id': churchId},
      );
      if (rows is List) {
        return List<Map<String, dynamic>>.from(rows);
      }
    } catch (error) {
      debugPrint('Membership review RPC unavailable: $error');
    }

    return _fetchRequestsFallback(churchId);
  }

  Future<List<Map<String, dynamic>>> _fetchRequestsFallback(
    String churchId,
  ) async {
    final rows = await Supabase.instance.client
        .from('church_memberships')
        .select('id, user_id, church_id, request_message, requested_at')
        .eq('church_id', churchId)
        .eq('membership_status', 'pending')
        .order('requested_at');

    final requests = List<Map<String, dynamic>>.from(rows);
    for (final request in requests) {
      final requesterId = request['user_id']?.toString() ?? '';
      try {
        final user = await Supabase.instance.client
            .from('users')
            .select('id, uid, fullName, email, phone, photoUrl, joinDate')
            .or('id.eq.$requesterId,uid.eq.$requesterId')
            .maybeSingle();
        request['profile'] = user;
      } catch (error) {
        debugPrint('Membership requester profile unavailable: $error');
      }
    }
    return requests;
  }

  Future<void> _decide({
    required String membershipId,
    required bool approve,
  }) async {
    final reason = await _decisionReason(approve: approve);
    if (reason == null || !mounted) return;

    final currentUser = context.read<UserRoleProvider>().userProfile;
    final rpc =
        approve ? 'approve_church_membership' : 'decline_church_membership';
    try {
      await Supabase.instance.client.rpc(
        rpc,
        params: {
          'membership_id': membershipId,
          'decision_note': reason,
        },
      );
      if (approve) {
        await NotificationService().sendMembershipApprovedPush(membershipId);
      }
      if (currentUser != null) {
        await NotificationService().markEntityAsRead(
          userId: currentUser.uid,
          entityTable: 'church_memberships',
          entityId: membershipId,
        );
      }

      if (!mounted) return;
      setState(() {
        _requestsFuture = _fetchRequests();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve
              ? 'Membership request approved.'
              : 'Membership request declined.'),
        ),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update request: ${error.message}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update request: $error')),
      );
    }
  }

  Future<String?> _decisionReason({required bool approve}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Approve Request' : 'Decline Request'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: approve ? 'Approval note' : 'Reason',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(approve ? 'Approve' : 'Decline'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Membership Requests',
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _requestsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final requests = snapshot.data ?? const [];
          if (requests.isEmpty) {
            return const Center(child: Text('No pending requests.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final request = requests[index];
              final profile =
                  Map<String, dynamic>.from(request['profile'] ?? const {});
              final name = _displayName(profile);
              final email = (profile['email'] ?? '').toString().trim();
              final phone = (profile['phone'] ?? '').toString().trim();
              final requestedAt =
                  _formatRequestedAt(request['requested_at']?.toString());
              final requestMessage =
                  (request['request_message'] ?? '').toString().trim();
              final profileComplete = profile['profileComplete'] == true;
              final requesterId = (request['user_id'] ?? '').toString();
              return AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundImage:
                              (profile['photoUrl'] ?? '').toString().isNotEmpty
                                  ? NetworkImage(profile['photoUrl'].toString())
                                  : null,
                          child: (profile['photoUrl'] ?? '').toString().isEmpty
                              ? Text(name.characters.first.toUpperCase())
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              if (requestedAt.isNotEmpty)
                                Text('Requested $requestedAt'),
                              const SizedBox(height: 4),
                              _StatusChip(
                                label: profileComplete
                                    ? 'Profile details supplied'
                                    : 'Profile details incomplete',
                                icon: profileComplete
                                    ? Icons.verified_user_outlined
                                    : Icons.info_outline,
                                isPositive: profileComplete,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _DetailLine(
                      icon: Icons.mail_outline,
                      label: email.isEmpty ? 'No email on profile' : email,
                    ),
                    _DetailLine(
                      icon: Icons.phone_outlined,
                      label: phone.isEmpty ? 'No phone on profile' : phone,
                    ),
                    if (requesterId.isNotEmpty)
                      _DetailLine(
                        icon: Icons.badge_outlined,
                        label:
                            'User id: ${requesterId.length > 8 ? requesterId.substring(0, 8) : requesterId}',
                      ),
                    if (requestMessage.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Message to leaders',
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(requestMessage),
                    ] else ...[
                      const SizedBox(height: 10),
                      Text(
                        'No message was included with this request.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            text: 'Decline',
                            isSecondary: true,
                            onPressed: () => _decide(
                              membershipId: request['id'].toString(),
                              approve: false,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppButton(
                            text: 'Approve',
                            onPressed: () => _decide(
                              membershipId: request['id'].toString(),
                              approve: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemCount: requests.length,
          );
        },
      ),
    );
  }

  String _displayName(Map<String, dynamic> profile) {
    final candidates = [
      profile['fullName'],
      profile['displayName'],
      profile['email'],
    ];
    for (final value in candidates) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return 'Member';
  }

  String _formatRequestedAt(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return '';
    return DateFormat('MMM d, y h:mm a').format(parsed.toLocal());
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.icon,
    required this.isPositive,
  });

  final String label;
  final IconData icon;
  final bool isPositive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        isPositive ? theme.colorScheme.primary : theme.colorScheme.tertiary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
