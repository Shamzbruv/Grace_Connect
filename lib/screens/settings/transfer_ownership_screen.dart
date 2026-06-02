import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/church_service.dart';
import '../../services/role_service.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_button.dart';
import '../../widgets/ui/app_loader.dart';

class TransferOwnershipScreen extends StatefulWidget {
  final String churchId;
  const TransferOwnershipScreen({super.key, required this.churchId});

  @override
  State<TransferOwnershipScreen> createState() => _TransferOwnershipScreenState();
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
      final query = await Supabase.instance.client
          .from('users')
          .select()
          .eq('email', email)
          .limit(1);

      if (query.isNotEmpty) {
        final data = query.first;
        final docId = data['uid']; 
        
        // Ensure the user belongs to the same church
        if (data['placeId'] == widget.churchId) {
          setState(() {
            _foundUser = data;
            _foundUserUid = docId as String?;
          });
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('User found, but they do not belong to this church.')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No user found with that email.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
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
            child: const Text('Yes, Transfer', style: TextStyle(color: Colors.white)),
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
        await _roleService.assignRole(_foundUserUid!, 'Pastor', widget.churchId);
      }
      if (!currentRoles.contains('Admin')) {
        await _roleService.assignRole(_foundUserUid!, 'Admin', widget.churchId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ownership transferred successfully.')),
        );
        Navigator.pop(context); // Go back to admin settings
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Transfer failed: $e')),
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
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the email address of the member you want to transfer church ownership to. They must already be a member of this church.',
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Member Email',
                      hintText: 'user@example.com',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    onSubmitted: (_) => _searchUser(),
                  ),
                ),
                const SizedBox(width: 8),
                AppButton(
                  text: 'Search',
                  onPressed: _isLoading ? null : _searchUser,
                ),
              ],
            ),
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
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
