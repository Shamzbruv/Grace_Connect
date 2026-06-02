import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_text_field.dart';
import '../../theme/app_colors.dart';
import '../../providers/user_role_provider.dart';
import '../../services/auth_flow_service.dart';
import '../../services/profile_service.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final ProfileService _profileService = ProfileService();
  final ImagePicker _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;

  bool _isLoading = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    final userProfile =
        Provider.of<UserRoleProvider>(context, listen: false).userProfile;
    _nameController = TextEditingController(text: userProfile?.fullName ?? '');
    _phoneController = TextEditingController(text: userProfile?.phone ?? '');
    _emailController = TextEditingController(text: userProfile?.email ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    try {
      final userProvider =
          Provider.of<UserRoleProvider>(context, listen: false);
      final XFile? image =
          await _picker.pickImage(source: ImageSource.gallery, maxWidth: 800);
      if (image == null) return;

      setState(() => _isLoading = true);

      if (kIsWeb) {
        await _profileService.uploadProfilePhotoBytes(
          await image.readAsBytes(),
          image.name,
        );
      } else {
        final File file = File(image.path);
        await _profileService.uploadProfilePhoto(file);
      }

      // Refresh provider
      await userProvider.fetchUserProfile();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated successfully')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating photo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final userProvider =
          Provider.of<UserRoleProvider>(context, listen: false);
      final currentProfile = userProvider.userProfile;
      if (currentProfile == null) {
        throw Exception('Please finish setting up your profile first.');
      }

      final updatedProfile = currentProfile.copyWith(
        fullName: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
      );

      await _profileService.updateProfile(updatedProfile);

      // Refresh local data
      await userProvider.fetchUserProfile();

      if (mounted) {
        setState(() => _isEditing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _changePassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No email address found to send reset link.')),
      );
      return;
    }

    try {
      await AuthFlowService.sendPasswordResetEmail(email);
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Password Reset'),
            content: Text(
                'A password reset link has been sent to $email. Please check your inbox.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sending reset email: $e')),
        );
      }
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text(
            'This action is permanent and cannot be undone. Are you sure you want to delete your account?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // In a real app, you might want to call a Cloud Function to clean up data securely
      try {
        // NOTE: Deleting a Supabase user directly from the client is not allowed by default.
        // You would typically call a Supabase Edge Function here. For now, we sign out.
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/login', (route) => false);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Error deleting account: $e. You may need to re-login first.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<UserRoleProvider>(context);
    final userProfile = provider.userProfile;
    final theme = Theme.of(context);

    if (provider.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (userProfile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Account Settings')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'Profile Not Found',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('We could not load your profile data.'),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(
                      context, '/complete_profile', (route) => false);
                },
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Finish Setup'),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: () {
                  provider.refreshProfile();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return AppScaffold(
      title: 'Account Settings',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Profile Photo
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      backgroundImage: (userProfile.photoUrl.isNotEmpty)
                          ? NetworkImage(userProfile.photoUrl)
                          : null,
                      child: (userProfile.photoUrl.isEmpty)
                          ? Text(userProfile.fullName[0].toUpperCase(),
                              style: GoogleFonts.outfit(fontSize: 40))
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: _pickAndUploadImage,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.camera_alt,
                              color: Colors.white, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Info Fields
              AppTextField(
                controller: _nameController,
                label: 'Full Name',
                readOnly: !_isEditing,
                prefixIcon: Icons.person_outline,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _phoneController,
                label: 'Phone Number',
                readOnly: !_isEditing,
                prefixIcon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _emailController,
                label: 'Email',
                readOnly:
                    true, // Email usually requires re-verification to change
                prefixIcon: Icons.email_outlined,
                suffixIcon: const Icon(Icons.lock_outline,
                    size: 16, color: Colors.grey),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              if (!_isEditing)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _isEditing = true),
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Profile'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.all(16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          // Undo changes
                          _nameController.text = userProfile.fullName;
                          _phoneController.text = userProfile.phone;
                          setState(() => _isEditing = false);
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        onPressed: _isLoading ? null : _saveProfile,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.all(16),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Text('Save Changes'),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 40),

              // Security Section
              _buildSectionHeader(context, 'Security'),
              const SizedBox(height: 8),
              _buildSettingsTile(
                context,
                title: 'Change Password',
                icon: Icons.lock_reset,
                onTap: _changePassword,
              ),

              const SizedBox(height: 24),
              _buildSectionHeader(context, 'Account Actions',
                  isDestructive: true),
              const SizedBox(height: 8),
              _buildSettingsTile(
                context,
                title: 'Sign Out',
                icon: Icons.logout,
                onTap: () async {
                  await Supabase.instance.client.auth.signOut();
                  if (!context.mounted) return;
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil('/login', (route) => false);
                },
              ),
              _buildSettingsTile(
                context,
                title: 'Delete Account',
                icon: Icons.delete_forever,
                isDestructive: true,
                onTap: _deleteAccount,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title,
      {bool isDestructive = false}) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: GoogleFonts.outfit(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: isDestructive
              ? AppColors.error
              : (isDarkMode ? Colors.white : AppColors.primary),
        ),
      ),
    );
  }

  Widget _buildSettingsTile(
    BuildContext context, {
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: Icon(icon,
            color: isDestructive
                ? AppColors.error
                : (isDarkMode ? Colors.white : AppColors.primary)),
        title: Text(
          title,
          style: TextStyle(
            color: isDestructive
                ? AppColors.error
                : (isDarkMode
                    ? AppColors.textPrimaryDark
                    : AppColors.textPrimary),
            fontWeight: FontWeight.w500,
          ),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
