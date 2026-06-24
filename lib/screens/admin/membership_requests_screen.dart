import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/user_role_provider.dart';
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

    final rows = await Supabase.instance.client
        .from('church_memberships')
        .select('id, user_id, church_id, request_message, requested_at')
        .eq('church_id', churchId)
        .eq('membership_status', 'pending')
        .order('requested_at');

    final requests = List<Map<String, dynamic>>.from(rows);
    for (final request in requests) {
      final user = await Supabase.instance.client
          .from('users')
          .select('fullName, email, phone, photoUrl')
          .eq('id', request['user_id'])
          .maybeSingle();
      request['profile'] = user;
    }
    return requests;
  }

  Future<void> _decide({
    required String membershipId,
    required bool approve,
  }) async {
    final reason = await _decisionReason(approve: approve);
    if (reason == null || !mounted) return;

    final rpc =
        approve ? 'approve_church_membership' : 'decline_church_membership';
    await Supabase.instance.client.rpc(
      rpc,
      params: {
        'membership_id': membershipId,
        'decision_note': reason,
      },
    );

    if (!mounted) return;
    setState(() {
      _requestsFuture = _fetchRequests();
    });
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
              final name = (profile['fullName'] ?? 'Member').toString();
              final email = (profile['email'] ?? '').toString();
              return AppCard(
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
                    if (email.isNotEmpty) Text(email),
                    if ((request['request_message'] ?? '')
                        .toString()
                        .isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(request['request_message'].toString()),
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
}
