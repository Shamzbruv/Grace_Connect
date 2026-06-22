import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../providers/user_role_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/profile_service.dart';
import 'dart:typed_data';
import 'package:intl/intl.dart';
import '../../utils/profile_photo_picker.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _bioController;
  late DateTime _memberSince;

  bool _isLoading = false;
  Uint8List? _imageBytes;
  String? _imageName;

  @override
  void initState() {
    super.initState();
    final user =
        Provider.of<UserRoleProvider>(context, listen: false).userProfile;
    _nameController = TextEditingController(text: user?.fullName ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
    _memberSince = user?.joinDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final pickedPhoto = await pickProfilePhotoWithCropOption(context);
    if (pickedPhoto == null) return;
    setState(() {
      _imageBytes = pickedPhoto.bytes;
      _imageName = pickedPhoto.fileName;
    });
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final userProvider =
          Provider.of<UserRoleProvider>(context, listen: false);
      final user = userProvider.userProfile;
      if (user == null) return;

      String photoUrl = user.photoUrl;

      if (_imageBytes != null && _imageName != null) {
        photoUrl = await ProfileService()
            .uploadProfilePhotoBytes(_imageBytes!, _imageName!);
      }

      await Supabase.instance.client.from('users').update({
        'fullName': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'bio': _bioController.text.trim(),
        'joinDate': _memberSince.toIso8601String(),
        'photoUrl': photoUrl,
      }).eq('uid', user.uid);

      await userProvider.refreshProfile();

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile Updated')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Provider.of<UserRoleProvider>(context).userProfile;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Profile',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Avatar Picker
                    GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 50,
                            backgroundColor:
                                colorScheme.surfaceContainerHighest,
                            backgroundImage: _imageBytes != null
                                ? MemoryImage(_imageBytes!)
                                : (user?.photoUrl.isNotEmpty ?? false)
                                    ? NetworkImage(user!.photoUrl)
                                        as ImageProvider
                                    : null,
                            child: (_imageBytes == null &&
                                    (user?.photoUrl.isEmpty ?? true))
                                ? Icon(Icons.add_a_photo,
                                    size: 24,
                                    color: colorScheme.onSurfaceVariant)
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: theme.scaffoldBackgroundColor,
                                    width: 2),
                              ),
                              child: Icon(Icons.edit,
                                  size: 14, color: theme.colorScheme.onPrimary),
                            ),
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    _buildSectionHeader(context, 'PERSONAL DETAILS'),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        prefixIcon: Icon(Icons.person_outline),
                        hintText: 'John Doe',
                      ),
                      validator: (val) => val == null || val.isEmpty
                          ? 'Name is required'
                          : null,
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Mobile Phone',
                        prefixIcon: Icon(Icons.phone_outlined),
                        hintText: '+1 876 555 0199',
                        helperText: 'Include country code',
                      ),
                    ),
                    const SizedBox(height: 20),

                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _pickMemberSince,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Member Since',
                          prefixIcon: Icon(Icons.event_available_outlined),
                          helperText:
                              'Used to calculate how long you have been a member',
                        ),
                        child: Text(DateFormat.yMMMMd().format(_memberSince)),
                      ),
                    ),

                    const SizedBox(height: 32),
                    _buildSectionHeader(context, 'BIO & ABOUT'),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _bioController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'About Me',
                        alignLabelWithHint: true,
                        hintText: 'Share a brief testimony or bio...',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Sticky Bottom Bar
          Container(
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
            decoration:
                BoxDecoration(color: theme.scaffoldBackgroundColor, boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withValues(alpha: 0.1),
                offset: const Offset(0, -4),
                blurRadius: 10,
              )
            ]),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveProfile,
                child: _isLoading
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: theme.colorScheme.onPrimary, strokeWidth: 2))
                    : const Text('Save Changes'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickMemberSince() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _memberSince.isAfter(now) ? now : _memberSince,
      firstDate: DateTime(1900),
      lastDate: now,
    );

    if (picked == null || !mounted) return;
    setState(() => _memberSince = picked);
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      ),
    );
  }
}
