import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import '../../services/church_service.dart';
import '../../models/church_model.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_loader.dart';
import '../../widgets/ui/app_text_field.dart';
import '../admin/role_management_screen.dart';
import 'transfer_ownership_screen.dart';

class ChurchAdminSettingsScreen extends StatefulWidget {
  const ChurchAdminSettingsScreen({super.key});

  @override
  State<ChurchAdminSettingsScreen> createState() =>
      _ChurchAdminSettingsScreenState();
}

class _ChurchAdminSettingsScreenState extends State<ChurchAdminSettingsScreen> {
  final ChurchService _churchService = ChurchService();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _denominationController = TextEditingController();
  final _timezoneController = TextEditingController();
  Church? _church;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadChurch();
  }

  Future<void> _loadChurch() async {
    final userProvider = Provider.of<UserRoleProvider>(context, listen: false);
    final churchId = userProvider.userProfile?.churchId;
    if (churchId != null) {
      final church = await _churchService.getChurch(churchId);
      if (mounted) {
        setState(() {
          _church = church;
          _nameController.text = church?.name ?? '';
          _addressController.text = church?.address ?? '';
          _denominationController.text = church?.denomination ?? '';
          _timezoneController.text = church?.timezone ?? 'America/Jamaica';
        });
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _denominationController.dispose();
    _timezoneController.dispose();
    super.dispose();
  }

  Future<void> _saveChurchProfile() async {
    final church = _church;
    if (church == null) return;

    setState(() => _isSaving = true);
    final updatedChurch = Church(
      id: church.id,
      name: _nameController.text.trim(),
      placeId: church.placeId,
      address: _addressController.text.trim(),
      denomination: _denominationController.text.trim(),
      ownerUserId: church.ownerUserId,
      timezone: _timezoneController.text.trim().isEmpty
          ? 'America/Jamaica'
          : _timezoneController.text.trim(),
      status: church.status,
      createdAt: church.createdAt,
      parish: church.parish,
      latitude: church.latitude,
      longitude: church.longitude,
      policies: church.policies,
      liveStreamUrl: church.liveStreamUrl,
      isLive: church.isLive,
    );

    try {
      await _churchService.updateChurch(updatedChurch);
      if (!mounted) return;
      setState(() {
        _church = updatedChurch;
        _isSaving = false;
      });
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Church profile saved')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save church profile: $e')),
      );
    }
  }

  void _showChurchProfileDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Church Profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(controller: _nameController, label: 'Church Name'),
              const SizedBox(height: 12),
              AppTextField(controller: _addressController, label: 'Address'),
              const SizedBox(height: 12),
              AppTextField(
                controller: _denominationController,
                label: 'Denomination',
              ),
              const SizedBox(height: 12),
              AppTextField(controller: _timezoneController, label: 'Timezone'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _isSaving ? null : _saveChurchProfile,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AppScaffold(
        title: 'Church Settings',
        body: Center(child: AppLoader()),
      );
    }

    final userProvider = Provider.of<UserRoleProvider>(context);
    final canManageChurch =
        userProvider.userProfile?.capabilities.canManageMembersBasic ?? false;
    final isOwner = _church != null &&
        _church!.ownerUserId == userProvider.userProfile?.uid;

    if (!canManageChurch) {
      return const AppScaffold(
        title: 'Church Settings',
        body: Center(child: Text('You do not have access to church settings.')),
      );
    }

    return AppScaffold(
      title: 'Church Settings',
      body: ListView(
        children: [
          if (_church != null)
            ListTile(
              leading: const Icon(Icons.church_outlined),
              title: Text(_church!.name),
              subtitle: Text(_church!.address.isEmpty
                  ? 'Update church profile'
                  : _church!.address),
              trailing: const Icon(Icons.edit_outlined),
              onTap: _showChurchProfileDialog,
            ),
          ListTile(
            leading: const Icon(Icons.security),
            title: const Text('Role Management'),
            subtitle: const Text('Assign roles and view audit logs'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const RoleManagementScreen()));
            },
          ),
          if (isOwner)
            ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: const Text('Transfer Ownership'),
              subtitle:
                  const Text('Transfer church ownership to another member'),
              trailing: const Icon(Icons.arrow_forward_ios),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => TransferOwnershipScreen(
                      churchId: _church!.placeId.isNotEmpty
                          ? _church!.placeId
                          : _church!.id,
                    ),
                  ),
                ).then((_) => _loadChurch()); // Reload in case of transfer
              },
            ),
        ],
      ),
    );
  }
}
