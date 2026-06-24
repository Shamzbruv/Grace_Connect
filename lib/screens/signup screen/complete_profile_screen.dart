import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../../models/user_profile.dart'; // Ensure this model exists
import '../../providers/user_role_provider.dart';
import '../../services/church_service.dart';
import '../../services/membership_service.dart';
import '../../services/profile_service.dart';
import '../../utils/profile_photo_picker.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_card.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _bioController = TextEditingController();
  final _churchSearchController = TextEditingController();

  bool _isLoading = false;
  Uint8List? _imageBytes;
  String? _imageName;
  String? _selectedChurchId;
  String _selectedChurchName = '';

  @override
  void dispose() {
    _bioController.dispose();
    _churchSearchController.dispose();
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

  Future<void> _handleCompleteProfile() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) {
          throw Exception("No authenticated user found.");
        }

        // 1. Get existing data from Supabase that was saved during signup.
        // If it is missing, rebuild a starter profile from auth metadata.
        final existingData = await Supabase.instance.client
            .from('users')
            .select()
            .eq('uid', user.id)
            .maybeSingle();
        final metadata = user.userMetadata ?? {};

        // Upload Profile Picture if selected
        String finalPhotoUrl = user.userMetadata?['avatar_url'] ?? '';
        if (_imageBytes != null && _imageName != null) {
          finalPhotoUrl = await ProfileService()
              .uploadProfilePhotoBytes(_imageBytes!, _imageName!);
        }

        final profileData = {
          'id': user.id,
          'uid': user.id,
          'email': user.email ?? '',
          'fullName': _stringValue(
              existingData, metadata, const ['fullName', 'full_name', 'name']),
          'phone': _stringValue(
              existingData, metadata, const ['phone', 'phoneNumber']),
          'placeId': '',
          'placeName': '',
          'roles': const ['Member'],
          'joinDate': existingData?['joinDate'] ??
              metadata['joinDate'] ??
              DateTime.now().toIso8601String(),
          'photoUrl': finalPhotoUrl,
          'bio': _bioController.text.trim(),
          'isDeveloper': existingData?['isDeveloper'] ?? false,
          'accountState': 'active',
        };

        // 2. Update Supabase users table with all details
        await Supabase.instance.client
            .from('users')
            .upsert(profileData, onConflict: 'uid');

        if (_selectedChurchId != null) {
          await MembershipService().requestMembership(
            churchId: _selectedChurchId!,
            message: _selectedChurchName.isEmpty
                ? 'Requested while completing profile.'
                : 'Requested to join $_selectedChurchName while completing profile.',
          );
        }

        // Construct full UserProfile to update provider
        final updatedData = await Supabase.instance.client
            .from('users')
            .select()
            .eq('uid', user.id)
            .maybeSingle();
        final userProfile = UserProfile.fromMap(updatedData ?? profileData);

        if (mounted) {
          // Set user profile in provider
          final roleProvider =
              Provider.of<UserRoleProvider>(context, listen: false);
          roleProvider.setUserProfile(userProfile);

          // Head to the protected route gate. Active members will enter the
          // dashboard; pending or unaffiliated users see the correct status.
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/dashboard', (route) => false);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  String _stringValue(
    Map<String, dynamic>? existingData,
    Map<String, dynamic> metadata,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = existingData?[key] ?? metadata[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      withBackground: true,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_add_alt_1_outlined,
                    size: 60, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Finish Setting Up',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add your profile details. Church access starts after a leader approves your membership request.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                AppCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _pickImage,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 50,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              backgroundImage: _imageBytes != null
                                  ? MemoryImage(_imageBytes!)
                                  : null,
                              child: _imageBytes == null
                                  ? Icon(Icons.add_a_photo,
                                      size: 32,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)
                                  : null,
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: Theme.of(context)
                                          .scaffoldBackgroundColor,
                                      width: 2),
                                ),
                                child: Icon(Icons.edit,
                                    size: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onPrimary),
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      TypeAheadField<Map<String, String>>(
                        controller: _churchSearchController,
                        builder: (context, controller, focusNode) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'Church',
                              hintText: 'Optional: request to join a church',
                              prefixIcon: Icon(Icons.church_outlined),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(12)),
                              ),
                            ),
                          );
                        },
                        suggestionsCallback: (pattern) async {
                          return await ChurchService.searchChurches(pattern);
                        },
                        itemBuilder: (context, suggestion) {
                          return ListTile(
                            leading: Icon(Icons.church,
                                color: Theme.of(context).colorScheme.primary),
                            title: Text(suggestion['name']!),
                            subtitle: Text(
                              suggestion['address']!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                        onSelected: (suggestion) {
                          setState(() {
                            _selectedChurchId = suggestion['id'];
                            _selectedChurchName = suggestion['name']!;
                            _churchSearchController.text = suggestion['name']!;
                          });
                        },
                        emptyBuilder: (context) => const Padding(
                          padding: EdgeInsets.all(16),
                          child:
                              Text('No approved churches match that search.'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _bioController,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: 'About Me',
                          alignLabelWithHint: true,
                          hintText: 'Share a brief testimony or bio...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Theme.of(context).colorScheme.surface,
                        ),
                      ),
                      const SizedBox(height: 24),
                      AppButton(
                        text: 'Complete Setup',
                        onPressed: _handleCompleteProfile,
                        isLoading: _isLoading,
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () async {
                    await Supabase.instance.client.auth.signOut();
                    if (!context.mounted) return;
                    Navigator.pushNamedAndRemoveUntil(
                        context, '/login', (route) => false);
                  },
                  child: const Text('Cancel and Sign Out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
