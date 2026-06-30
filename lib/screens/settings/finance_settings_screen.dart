import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/user_role_provider.dart';
import '../../widgets/ui/app_scaffold.dart';

class FinanceSettingsScreen extends StatefulWidget {
  const FinanceSettingsScreen({super.key});

  @override
  State<FinanceSettingsScreen> createState() => _FinanceSettingsScreenState();
}

class _FinanceSettingsScreenState extends State<FinanceSettingsScreen> {
  final _givingUrlController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic> _policies = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _givingUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final churchId = Provider.of<UserRoleProvider>(context, listen: false)
        .userProfile
        ?.churchId;

    if (churchId == null || churchId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final data = await Supabase.instance.client
          .from('churches')
          .select('policies')
          .eq('id', churchId)
          .maybeSingle();
      final policies = Map<String, dynamic>.from(data?['policies'] ?? {});
      final finance =
          Map<String, dynamic>.from(policies['financeSettings'] ?? {});

      if (!mounted) return;
      setState(() {
        _policies = policies;
        _givingUrlController.text = finance['givingUrl'] ?? '';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load finance settings: $e')),
      );
    }
  }

  Future<void> _saveSettings() async {
    final userProvider = Provider.of<UserRoleProvider>(context, listen: false);
    final churchId = userProvider.userProfile?.churchId;
    if (churchId == null || churchId.isEmpty) return;

    setState(() => _isSaving = true);
    final currentFinance =
        Map<String, dynamic>.from(_policies['financeSettings'] ?? {});

    final updatedPolicies = Map<String, dynamic>.from(_policies)
      ..['financeSettings'] = {
        ...currentFinance,
        'givingProvider': 'SpurrOpen',
        'givingUrl': _normalizeUrl(_givingUrlController.text),
        'updatedAt': DateTime.now().toIso8601String(),
      };

    try {
      await Supabase.instance.client
          .from('churches')
          .update({'policies': updatedPolicies}).eq('id', churchId);
      if (!mounted) return;
      setState(() {
        _policies = updatedPolicies;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Giving settings saved')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save finance settings: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserRoleProvider>(context).userProfile;
    final canManageFinance = (user?.capabilities.canManageFinance ?? false) ||
        _hasAnyRole(user?.roles ?? const [], const ['pastor', 'senior_pastor']);

    if (!canManageFinance) {
      return const AppScaffold(
        title: 'Giving Settings',
        body: Center(child: Text('You do not have access to giving settings.')),
      );
    }

    return AppScaffold(
      title: 'Giving Settings',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.volunteer_activism_outlined,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'SpurrOpen Giving',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Grace Connect does not process offerings directly. Add your church SpurrOpen giving page so members can continue in a secure external browser.',
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _openSpurrOpen,
                          icon: const Icon(Icons.open_in_new_outlined),
                          label: const Text('Set up SpurrOpen'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _givingUrlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                    labelText: 'SpurrOpen Giving Link',
                    helperText:
                        'Members will be redirected to this link when they tap Give.',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.link_outlined),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _saveSettings,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save SpurrOpen Link'),
                ),
              ],
            ),
    );
  }

  bool _hasAnyRole(List<String> roles, List<String> targets) {
    final normalizedTargets = targets.toSet();
    return roles.map(_normalizeRole).any(normalizedTargets.contains);
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

  String _normalizeUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  Future<void> _openSpurrOpen() async {
    final uri = Uri.parse('https://www.spurropen.com/giving/');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
