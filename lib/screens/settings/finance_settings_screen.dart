import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../providers/user_role_provider.dart';
import '../../widgets/ui/app_scaffold.dart';

class FinanceSettingsScreen extends StatefulWidget {
  const FinanceSettingsScreen({super.key});

  @override
  State<FinanceSettingsScreen> createState() => _FinanceSettingsScreenState();
}

class _FinanceSettingsScreenState extends State<FinanceSettingsScreen> {
  final _approvalThresholdController = TextEditingController();
  final _givingUrlController = TextEditingController();

  String _currency = 'JMD';
  int _fiscalYearStartMonth = 1;
  bool _requireReceipts = true;
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
    _approvalThresholdController.dispose();
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
        _currency = finance['currency'] ?? 'JMD';
        _fiscalYearStartMonth = finance['fiscalYearStartMonth'] ?? 1;
        _requireReceipts = finance['requireReceipts'] ?? true;
        _givingUrlController.text = finance['givingUrl'] ?? '';
        _approvalThresholdController.text =
            (finance['approvalThreshold'] ?? 50000).toString();
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
    final threshold =
        double.tryParse(_approvalThresholdController.text.trim()) ?? 0;

    final updatedPolicies = Map<String, dynamic>.from(_policies)
      ..['financeSettings'] = {
        'currency': _currency,
        'fiscalYearStartMonth': _fiscalYearStartMonth,
        'requireReceipts': _requireReceipts,
        'approvalThreshold': threshold,
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
        const SnackBar(content: Text('Finance settings saved')),
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
        title: 'Finance Settings',
        body:
            Center(child: Text('You do not have access to finance settings.')),
      );
    }

    return AppScaffold(
      title: 'Finance Settings',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  value: _currency,
                  decoration: const InputDecoration(
                    labelText: 'Default Currency',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'JMD', child: Text('JMD')),
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                    DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                    DropdownMenuItem(value: 'CAD', child: Text('CAD')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _currency = value);
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: _fiscalYearStartMonth,
                  decoration: const InputDecoration(
                    labelText: 'Fiscal Year Starts',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('January')),
                    DropdownMenuItem(value: 4, child: Text('April')),
                    DropdownMenuItem(value: 7, child: Text('July')),
                    DropdownMenuItem(value: 10, child: Text('October')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _fiscalYearStartMonth = value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _approvalThresholdController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Approval Threshold',
                    helperText:
                        'Expenses above this amount should be reviewed first.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Require Receipts'),
                  subtitle:
                      const Text('Flag expense records that have no receipt.'),
                  value: _requireReceipts,
                  onChanged: (value) =>
                      setState(() => _requireReceipts = value),
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
                  label: const Text('Save Finance Settings'),
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
}
