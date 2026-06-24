import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_scaffold.dart';

class ChurchApplicationsScreen extends StatefulWidget {
  const ChurchApplicationsScreen({super.key});

  @override
  State<ChurchApplicationsScreen> createState() =>
      _ChurchApplicationsScreenState();
}

class _ChurchApplicationsScreenState extends State<ChurchApplicationsScreen> {
  late Future<List<Map<String, dynamic>>> _applicationsFuture;

  @override
  void initState() {
    super.initState();
    _applicationsFuture = _fetchApplications();
  }

  Future<List<Map<String, dynamic>>> _fetchApplications() async {
    final rows = await Supabase.instance.client
        .from('church_registration_requests')
        .select()
        .inFilter('application_status', [
      'submitted',
      'under_review',
      'needs_information',
    ]).order('created_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _decide({
    required String requestId,
    required bool approve,
  }) async {
    final note = await _reviewNote(approve: approve);
    if (note == null || !mounted) return;

    final rpc =
        approve ? 'approve_church_registration' : 'reject_church_registration';
    await Supabase.instance.client.rpc(
      rpc,
      params: {
        'request_id': requestId,
        'review_note': note,
      },
    );

    if (!mounted) return;
    setState(() {
      _applicationsFuture = _fetchApplications();
    });
  }

  Future<String?> _reviewNote({required bool approve}) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Approve Church' : 'Reject Church'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Review note',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(approve ? 'Approve' : 'Reject'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Church Applications',
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _applicationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final applications = snapshot.data ?? const [];
          if (applications.isEmpty) {
            return const Center(child: Text('No pending applications.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, index) {
              final app = applications[index];
              return AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (app['church_name_submitted'] ?? 'Church').toString(),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text((app['address'] ?? '').toString()),
                    if ((app['pastor_name'] ?? '').toString().isNotEmpty)
                      Text('Contact: ${app['pastor_name']}'),
                    if ((app['pastor_email'] ?? '').toString().isNotEmpty)
                      Text((app['pastor_email']).toString()),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            text: 'Reject',
                            isSecondary: true,
                            onPressed: () => _decide(
                              requestId: app['id'].toString(),
                              approve: false,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppButton(
                            text: 'Approve',
                            onPressed: () => _decide(
                              requestId: app['id'].toString(),
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
            itemCount: applications.length,
          );
        },
      ),
    );
  }
}
