import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/prayer_request.dart';
import '../../providers/user_role_provider.dart';
import '../../services/prayer_service.dart';
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
    final canManagePrayers = user?.capabilities.canAssignPrayers == true ||
        user?.capabilities.canViewSensitivePrayers == true;

    if (canManagePrayers) {
      return _PrayerAdminView(service: _service, churchId: user?.churchId);
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
  });

  final PrayerService service;
  final String? churchId;

  @override
  Widget build(BuildContext context) {
    final effectiveChurchId = churchId;
    if (effectiveChurchId == null || effectiveChurchId.isEmpty) {
      return const AppScaffold(
        title: 'Prayer Requests',
        body: Center(child: Text('Join a church to manage prayer requests.')),
      );
    }

    return AppScaffold(
      title: 'Prayer Requests',
      body: StreamBuilder<List<PrayerRequest>>(
        stream: service.getChurchRequests(effectiveChurchId),
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
            return const Center(child: Text('No prayer requests yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: requests.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) => _PrayerRequestCard(
              request: requests[index],
              showActions: true,
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
  });

  final PrayerRequest request;
  final bool showActions;

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
              if (showActions) _PrayerStatusMenu(request: request),
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
        ],
      ),
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
