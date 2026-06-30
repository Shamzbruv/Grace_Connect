import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/church_service.dart';
import '../../services/role_service.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_button.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/app_loader.dart';

class TransferOwnershipScreen extends StatefulWidget {
  final String churchId;
  const TransferOwnershipScreen({super.key, required this.churchId});

  @override
  State<TransferOwnershipScreen> createState() =>
      _TransferOwnershipScreenState();
}

class _TransferOwnershipScreenState extends State<TransferOwnershipScreen> {
  final TextEditingController _emailController = TextEditingController();
  final ChurchService _churchService = ChurchService();
  final RoleService _roleService = RoleService();

  bool _isLoading = false;
  Map<String, dynamic>? _foundUser;
  String? _foundUserUid;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _searchUser() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;

    setState(() {
      _isLoading = true;
      _foundUser = null;
      _foundUserUid = null;
    });

    try {
      final church = await _churchService.getChurch(widget.churchId);
      final validChurchIds = {
        widget.churchId,
        if (church != null) church.id,
        if (church != null) church.placeId,
      }.where((id) => id.trim().isNotEmpty).toSet();

      final query = await Supabase.instance.client
          .from('users')
          .select()
          .ilike('email', email)
          .limit(1);

      if (query.isNotEmpty) {
        final data = query.first;
        final authUserId = (data['id'] ?? data['uid'] ?? '').toString();
        final roleTargetUid = (data['uid'] ?? data['id'] ?? '').toString();
        final userChurchId = data['placeId']?.toString() ?? '';
        final memberships = authUserId.isEmpty
            ? const []
            : await Supabase.instance.client
                .from('church_memberships')
                .select('id, church_id, membership_status')
                .eq('user_id', authUserId)
                .eq('membership_status', 'active');
        final hasActiveMembership = memberships.any((membership) {
          final churchId = membership['church_id']?.toString() ?? '';
          return validChurchIds.contains(churchId);
        });

        // Prefer the canonical membership table. The legacy users.placeId check
        // remains as a fallback for older rows that are still being repaired.
        if (hasActiveMembership || validChurchIds.contains(userChurchId)) {
          setState(() {
            _foundUser = data;
            _foundUserUid = roleTargetUid.isEmpty ? null : roleTargetUid;
          });
        } else {
          if (mounted) {
            AppFeedback.show(
              context,
              'User found, but they do not belong to this church.',
              type: AppFeedbackType.warning,
            );
          }
        }
      } else {
        if (mounted) {
          AppFeedback.show(
            context,
            'No user found with that email.',
            type: AppFeedbackType.warning,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.show(
          context,
          'Error: $e',
          type: AppFeedbackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _transferOwnership() async {
    if (_foundUserUid == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer Ownership?'),
        content: Text(
          'Are you sure you want to transfer ownership of this church to ${_foundUser?['fullName']}?\n\n'
          'You will no longer be the primary owner and may lose access to some administrative features.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Transfer',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      // Transfer Ownership
      await _churchService.transferOwnership(widget.churchId, _foundUserUid!);

      // Also assign Admin/Pastor roles just to be safe so they can manage
      final currentRoles = List<String>.from(_foundUser?['roles'] ?? []);
      if (!currentRoles.contains('Pastor')) {
        await _roleService.assignRole(
            _foundUserUid!, 'Pastor', widget.churchId);
      }
      if (!currentRoles.contains('Admin')) {
        await _roleService.assignRole(_foundUserUid!, 'Admin', widget.churchId);
      }

      if (mounted) {
        AppFeedback.show(
          context,
          'Ownership transferred successfully.',
          type: AppFeedbackType.success,
        );
        Navigator.pop(context); // Go back to admin settings
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.show(
          context,
          'Transfer failed: $e',
          type: AppFeedbackType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Transfer Ownership',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the email address of the member you want to transfer church ownership to. They must already be a member of this church.',
            ),
            if (widget.churchId.trim().isEmpty) ...[
              const SizedBox(height: 12),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'This church record is missing an id. Go back to Church Settings and reopen this screen after the church profile loads.',
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Member Email',
                hintText: 'user@example.com',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
              onSubmitted: (_) => _searchUser(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: AppButton(
                text: 'Search Member',
                onPressed: _isLoading ? null : _searchUser,
              ),
            ),
            if (_foundUser == null && !_isLoading) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Search for an active member of this church. The member must already be approved before ownership can be transferred.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 32),
            if (_isLoading)
              const Center(child: AppLoader())
            else if (_foundUser != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'User Found',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text('Name: ${_foundUser?['fullName']}'),
                      Text('Email: ${_foundUser?['email']}'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _transferOwnership,
                        child: const Text('Transfer Ownership'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
