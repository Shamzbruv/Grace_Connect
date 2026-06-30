import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/user_role_provider.dart';
import '../../services/finance_service.dart';
import '../../widgets/app_bottom_menu.dart';

class DonationsScreen extends StatefulWidget {
  const DonationsScreen({super.key});

  @override
  State<DonationsScreen> createState() => _DonationsScreenState();
}

class _DonationsScreenState extends State<DonationsScreen> {
  final FinanceService _financeService = FinanceService();
  late Future<String?> _givingUrlFuture;

  @override
  void initState() {
    super.initState();
    _givingUrlFuture = Future.value(null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadGivingUrl();
    });
  }

  void _loadGivingUrl() {
    final churchId = context.read<UserRoleProvider>().userProfile?.churchId;
    setState(() {
      _givingUrlFuture = churchId == null || churchId.isEmpty
          ? Future.value(null)
          : _financeService.getGivingUrl(churchId);
    });
  }

  Future<void> _openGivingLink(String url) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Continue to SpurrOpen?'),
        content: const Text(
          'Grace Connect will open your church giving page in a secure external browser.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.open_in_new_outlined),
            label: const Text('Continue'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The giving link is not valid.')),
      );
      return;
    }

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the giving link.')),
      );
    }
  }

  bool _canManageGiving(UserRoleProvider roleProvider) {
    final user = roleProvider.userProfile;
    if (user?.capabilities.canManageFinance == true) return true;

    const allowed = {
      'pastor',
      'senior_pastor',
      'treasurer',
      'financial_secretary',
    };
    return user?.roles.map(_normalizeRole).any(allowed.contains) == true;
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
    final theme = Theme.of(context);
    final roleProvider = context.watch<UserRoleProvider>();
    final canManageGiving = _canManageGiving(roleProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Giving'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadGivingUrl,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomMenu(),
      body: FutureBuilder<String?>(
        future: _givingUrlFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final givingUrl = snapshot.data;

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.volunteer_activism_outlined,
                      size: 34,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Give securely',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      givingUrl == null
                          ? 'Your church has not configured its SpurrOpen giving link yet. SpurrOpen is free to sign up for, and your church admin can add the giving link from settings.'
                          : 'You will be redirected to your church SpurrOpen giving page.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: givingUrl == null
                            ? null
                            : () => _openGivingLink(givingUrl),
                        icon: const Icon(Icons.open_in_new_outlined),
                        label: const Text('Open Giving Page'),
                      ),
                    ),
                  ],
                ),
              ),
              if (canManageGiving) ...[
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.pushNamed(context, '/settings/finance');
                    if (mounted) _loadGivingUrl();
                  },
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Configure SpurrOpen Link'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
