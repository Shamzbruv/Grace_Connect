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
  late TextEditingController _addressController;
  late TextEditingController _cityController;
  late TextEditingController _parishController;
  late TextEditingController _occupationController;
  late TextEditingController _emergencyNameController;
  late TextEditingController _emergencyPhoneController;
  late TextEditingController _pastoralTitleController;
  late TextEditingController _pastorBioController;
  late TextEditingController _publicEmailController;
  late TextEditingController _publicPhoneController;
  late DateTime _memberSince;
  DateTime? _dateOfBirth;
  DateTime? _ordinationDate;
  String _gender = '';
  bool _isProfilePrivate = false;
  bool _showContactInfo = true;
  bool _showPastorPublicContact = true;

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
    _addressController = TextEditingController(text: user?.address ?? '');
    _cityController = TextEditingController(text: user?.city ?? '');
    _parishController = TextEditingController(text: user?.parish ?? '');
    _occupationController = TextEditingController(text: user?.occupation ?? '');
    _emergencyNameController =
        TextEditingController(text: user?.emergencyContactName ?? '');
    _emergencyPhoneController =
        TextEditingController(text: user?.emergencyContactPhone ?? '');
    _pastoralTitleController =
        TextEditingController(text: user?.pastoralTitle ?? '');
    _pastorBioController =
        TextEditingController(text: user?.pastorPublicBio ?? '');
    _publicEmailController =
        TextEditingController(text: user?.publicEmail ?? '');
    _publicPhoneController =
        TextEditingController(text: user?.publicPhone ?? '');
    _memberSince = user?.joinDate ?? DateTime.now();
    _dateOfBirth = user?.dateOfBirth;
    _ordinationDate = user?.ordinationDate;
    _gender = user?.gender ?? '';
    _isProfilePrivate = user?.isProfilePrivate ?? false;
    _showContactInfo = user?.showContactInfo ?? true;
    _showPastorPublicContact = user?.showPastorPublicContact ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _parishController.dispose();
    _occupationController.dispose();
    _emergencyNameController.dispose();
    _emergencyPhoneController.dispose();
    _pastoralTitleController.dispose();
    _pastorBioController.dispose();
    _publicEmailController.dispose();
    _publicPhoneController.dispose();
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
        'dateOfBirth': _dateOnly(_dateOfBirth),
        'gender': _gender,
        'address': _addressController.text.trim(),
        'city': _cityController.text.trim(),
        'parish': _parishController.text.trim(),
        'occupation': _occupationController.text.trim(),
        'emergencyContactName': _emergencyNameController.text.trim(),
        'emergencyContactPhone': _emergencyPhoneController.text.trim(),
        'isProfilePrivate': _isProfilePrivate,
        'showContactInfo': _showContactInfo,
        'contactInfoVisibility':
            _showContactInfo && !_isProfilePrivate ? 'church' : 'private',
        'pastoralTitle': _pastoralTitleController.text.trim(),
        'pastorPublicBio': _pastorBioController.text.trim(),
        'ordinationDate': _dateOnly(_ordinationDate),
        'publicEmail': _publicEmailController.text.trim(),
        'publicPhone': _publicPhoneController.text.trim(),
        'showPastorPublicContact': _showPastorPublicContact,
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
    const genderOptions = ['Female', 'Male', 'Prefer not to say'];

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
                      onTap: () => _pickOptionalDate(
                        initialDate: _dateOfBirth,
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                        onPicked: (date) => setState(() => _dateOfBirth = date),
                      ),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date of Birth',
                          prefixIcon: Icon(Icons.cake_outlined),
                        ),
                        child: Text(_dateOfBirth == null
                            ? 'Not set'
                            : DateFormat.yMMMMd().format(_dateOfBirth!)),
                      ),
                    ),
                    const SizedBox(height: 20),

                    DropdownButtonFormField<String>(
                      value: genderOptions.contains(_gender) ? _gender : null,
                      decoration: const InputDecoration(
                        labelText: 'Gender',
                        prefixIcon: Icon(Icons.person_search_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'Female', child: Text('Female')),
                        DropdownMenuItem(value: 'Male', child: Text('Male')),
                        DropdownMenuItem(
                            value: 'Prefer not to say',
                            child: Text('Prefer not to say')),
                      ],
                      onChanged: (value) =>
                          setState(() => _gender = value ?? ''),
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _occupationController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Occupation',
                        prefixIcon: Icon(Icons.work_outline),
                      ),
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _addressController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        prefixIcon: Icon(Icons.home_outlined),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _cityController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'City',
                              prefixIcon: Icon(Icons.location_city_outlined),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _parishController,
                            textCapitalization: TextCapitalization.words,
                            decoration: const InputDecoration(
                              labelText: 'Parish',
                              prefixIcon: Icon(Icons.map_outlined),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    _buildSectionHeader(context, 'EMERGENCY CONTACT'),
                    const SizedBox(height: 16),

                    TextFormField(
                      controller: _emergencyNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Emergency Contact Name',
                        prefixIcon: Icon(Icons.contact_emergency_outlined),
                      ),
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _emergencyPhoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Emergency Contact Phone',
                        prefixIcon: Icon(Icons.phone_in_talk_outlined),
                      ),
                    ),
                    const SizedBox(height: 32),

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
                    if (user?.hasPastoralRole == true) ...[
                      const SizedBox(height: 32),
                      _buildSectionHeader(context, 'PASTOR PUBLIC PROFILE'),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _pastoralTitleController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Pastoral Title',
                          prefixIcon: Icon(Icons.workspace_premium_outlined),
                          hintText: 'Lead Pastor, Senior Pastor, etc.',
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _pastorBioController,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          labelText: 'Public Pastor Bio',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 20),
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _pickOptionalDate(
                          initialDate: _ordinationDate,
                          firstDate: DateTime(1900),
                          lastDate: DateTime.now(),
                          onPicked: (date) =>
                              setState(() => _ordinationDate = date),
                        ),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Ordination Date',
                            prefixIcon: Icon(Icons.event_note_outlined),
                          ),
                          child: Text(_ordinationDate == null
                              ? 'Not set'
                              : DateFormat.yMMMMd().format(_ordinationDate!)),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _publicEmailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Public Email',
                          prefixIcon: Icon(Icons.alternate_email_outlined),
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: _publicPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Public Phone',
                          prefixIcon: Icon(Icons.phone_forwarded_outlined),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Show pastor contact publicly'),
                        value: _showPastorPublicContact,
                        onChanged: (value) =>
                            setState(() => _showPastorPublicContact = value),
                      ),
                    ],
                    const SizedBox(height: 32),
                    _buildSectionHeader(context, 'PRIVACY'),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Private profile'),
                      subtitle: const Text(
                          'Hide most profile details from other members.'),
                      value: _isProfilePrivate,
                      onChanged: (value) {
                        setState(() {
                          _isProfilePrivate = value;
                          if (value) _showContactInfo = false;
                        });
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Show contact info to church members'),
                      value: _showContactInfo,
                      onChanged: _isProfilePrivate
                          ? null
                          : (value) => setState(() => _showContactInfo = value),
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

  Future<void> _pickOptionalDate({
    required DateTime? initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final safeInitial = initialDate == null || initialDate.isAfter(lastDate)
        ? lastDate
        : initialDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: safeInitial,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked == null || !mounted) return;
    onPicked(picked);
  }

  String? _dateOnly(DateTime? date) {
    if (date == null) return null;
    return DateFormat('yyyy-MM-dd').format(date);
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
