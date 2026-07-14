import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../providers/user_role_provider.dart';
import '../../models/user_profile.dart';
import 'edit_profile_screen.dart';
import 'family_link_sheet.dart';
import '../../models/family_relationship.dart';
import '../../services/family_service.dart';
import '../../services/profile_service.dart';
import '../../utils/profile_photo_picker.dart';
import '../../widgets/profile_photo_viewer.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ProfileService _profileService = ProfileService();
  final FamilyService _familyService = FamilyService();
  bool _isUploading = false;

  Future<void> _handlePhotoUpload() async {
    final userProvider = Provider.of<UserRoleProvider>(context, listen: false);
    final pickedPhoto = await pickProfilePhotoWithCropOption(context);

    if (pickedPhoto == null) return;

    setState(() => _isUploading = true);

    try {
      await _profileService.uploadProfilePhotoBytes(
        pickedPhoto.bytes,
        pickedPhoto.fileName,
      );
      await userProvider.refreshProfile();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile photo updated successfully')),
      );
    } catch (e) {
      if (mounted) {
        // Friendly Error Handling
        String message = 'Upload failed. Please try again.';
        String? actionLabel;
        VoidCallback? action;

        if (e.toString().contains('permission-denied') ||
            e.toString().contains('unauthorized')) {
          message = 'You don\'t have permission to upload a profile photo.';
          actionLabel = 'Get Help';
          action = () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          };
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            action: actionLabel != null
                ? SnackBarAction(label: actionLabel, onPressed: action!)
                : null,
            behavior: SnackBarBehavior.floating,
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _openFamilyLinkSheet() async {
    final user =
        Provider.of<UserRoleProvider>(context, listen: false).userProfile;
    if (user == null) return;

    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FamilyLinkSheet(currentUser: user),
    );
  }

  Future<void> _openProfilePhotoPreview(UserProfile userProfile) {
    return showProfilePhotoViewer(
      context: context,
      imageUrl: userProfile.photoUrl,
      displayName: userProfile.fullName,
      onChangePhoto: _isUploading ? null : _handlePhotoUpload,
    );
  }

  Future<void> _respondToFamilyRequest(
    FamilyRelationship relationship,
    bool approve,
  ) async {
    final roleProvider = Provider.of<UserRoleProvider>(context, listen: false);

    try {
      await _familyService.respondToRequest(
        relationshipId: relationship.id,
        approve: approve,
      );
      if (!mounted) return;
      await roleProvider.refreshProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve ? 'Family link approved.' : 'Family link declined.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update family request: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<UserRoleProvider>(context);
    final userProfile = provider.userProfile;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (provider.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (userProfile == null) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: BackButton(color: Theme.of(context).colorScheme.onSurface),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline,
                  size: 64, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'Profile Not Found',
                style: GoogleFonts.outfit(
                    fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('We could not load your profile data.'),
              const SizedBox(height: 24),
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

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: const BackButton(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: () {
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const EditProfileScreen()));
            },
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // 1. Modern Header
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                // Background
                Container(
                  width: double.infinity,
                  height: userProfile.bio.trim().isEmpty ? 280 : 330,
                  decoration: const BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius:
                        BorderRadius.vertical(bottom: Radius.circular(32)),
                  ),
                ),

                // Content
                Positioned(
                  bottom: 40,
                  child: Column(
                    children: [
                      // Avatar
                      GestureDetector(
                        onTap: _isUploading || userProfile.photoUrl.isEmpty
                            ? null
                            : () => _openProfilePhotoPreview(userProfile),
                        child: Stack(
                          children: [
                            Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: AppColors.gold, width: 4),
                                boxShadow: [
                                  BoxShadow(
                                      color: theme.shadowColor
                                          .withValues(alpha: 0.3),
                                      blurRadius: 15,
                                      offset: const Offset(0, 5))
                                ],
                                image: userProfile.photoUrl.isNotEmpty
                                    ? DecorationImage(
                                        image:
                                            NetworkImage(userProfile.photoUrl),
                                        fit: BoxFit.cover)
                                    : null,
                              ),
                              child: _isUploading
                                  ? const CircularProgressIndicator(
                                      color: AppColors.gold)
                                  : userProfile.photoUrl.isEmpty
                                      ? const Icon(Icons.person,
                                          size: 60, color: Colors.white)
                                      : null,
                            ),
                            if (!_isUploading)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: GestureDetector(
                                  onTap: _handlePhotoUpload,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                        color: theme.colorScheme.surface,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                              color: theme.shadowColor
                                                  .withValues(alpha: 0.1),
                                              blurRadius: 4)
                                        ]),
                                    child: Icon(Icons.camera_alt,
                                        size: 16, color: colorScheme.primary),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        userProfile.fullName,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Role Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 1),
                        ),
                        child: Text(
                          userProfile.roles.isNotEmpty
                              ? userProfile.roles.first
                              : 'Member',
                          style: GoogleFonts.outfit(
                            color: AppColors.gold,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      if (userProfile.bio.trim().isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: MediaQuery.of(context).size.width - 80,
                          child: Text(
                            userProfile.bio.trim(),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      // Email intentionally removed from here per user request
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12), // Overlap adjustment

            // 2. Compact Stats Chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildChip(context, Icons.calendar_today,
                      _calculateMemberDuration(userProfile.joinDate)),
                  _buildChip(context, Icons.church,
                      _shortenChurchName(userProfile.placeName)),
                  _buildChip(context, Icons.group_work,
                      '${userProfile.roles.length} Roles'),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 3. Info Sections (Restyled)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    leading: const Icon(Icons.person_pin_circle_outlined),
                    title: const Text('Public Profile'),
                    subtitle: const Text('Manage how you appear in Discover.'),
                    trailing: const Icon(Icons.chevron_right),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color:
                            colorScheme.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
                    onTap: () => Navigator.of(context).pushNamed(
                      '/public_profile?id=${Uri.encodeComponent(userProfile.uid)}',
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text('CONTACT INFO',
                      style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  _buildInfoCard(context, [
                    _buildInfoRow(context, Icons.email_outlined, 'Email',
                        userProfile.email),
                    if (userProfile.phone.isNotEmpty) ...[
                      const Divider(height: 24),
                      _buildInfoRow(context, Icons.phone_outlined, 'Phone',
                          userProfile.phone),
                    ]
                  ]),
                  const SizedBox(height: 24),
                  Text('MEMBER DETAILS',
                      style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  _buildInfoCard(context, [
                    if (userProfile.dateOfBirth != null)
                      _buildInfoRow(
                        context,
                        Icons.cake_outlined,
                        'Date of Birth',
                        DateFormat.yMMMMd().format(userProfile.dateOfBirth!),
                      ),
                    if (userProfile.gender.trim().isNotEmpty) ...[
                      if (userProfile.dateOfBirth != null)
                        const Divider(height: 24),
                      _buildInfoRow(context, Icons.person_search_outlined,
                          'Gender', userProfile.gender.trim()),
                    ],
                    if (userProfile.occupation.trim().isNotEmpty) ...[
                      if (userProfile.dateOfBirth != null ||
                          userProfile.gender.trim().isNotEmpty)
                        const Divider(height: 24),
                      _buildInfoRow(context, Icons.work_outline, 'Occupation',
                          userProfile.occupation.trim()),
                    ],
                    if (userProfile.address.trim().isNotEmpty ||
                        userProfile.city.trim().isNotEmpty ||
                        userProfile.parish.trim().isNotEmpty) ...[
                      if (userProfile.dateOfBirth != null ||
                          userProfile.gender.trim().isNotEmpty ||
                          userProfile.occupation.trim().isNotEmpty)
                        const Divider(height: 24),
                      _buildInfoRow(
                        context,
                        Icons.home_outlined,
                        'Address',
                        [
                          userProfile.address,
                          userProfile.city,
                          userProfile.parish,
                        ].where((part) => part.trim().isNotEmpty).join(', '),
                      ),
                    ],
                    if (userProfile.dateOfBirth == null &&
                        userProfile.gender.trim().isEmpty &&
                        userProfile.occupation.trim().isEmpty &&
                        userProfile.address.trim().isEmpty &&
                        userProfile.city.trim().isEmpty &&
                        userProfile.parish.trim().isEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'No member details added yet.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 24),
                  if (userProfile.hasPastoralRole) ...[
                    Text('PASTOR PROFILE',
                        style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    _buildInfoCard(context, [
                      if (userProfile.pastoralTitle.trim().isNotEmpty)
                        _buildInfoRow(
                          context,
                          Icons.workspace_premium_outlined,
                          'Title',
                          userProfile.pastoralTitle.trim(),
                        ),
                      if (userProfile.ordinationDate != null) ...[
                        if (userProfile.pastoralTitle.trim().isNotEmpty)
                          const Divider(height: 24),
                        _buildInfoRow(
                          context,
                          Icons.event_note_outlined,
                          'Ordination',
                          DateFormat.yMMMMd()
                              .format(userProfile.ordinationDate!),
                        ),
                      ],
                      if (userProfile.pastorPublicBio.trim().isNotEmpty) ...[
                        if (userProfile.pastoralTitle.trim().isNotEmpty ||
                            userProfile.ordinationDate != null)
                          const Divider(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(userProfile.pastorPublicBio.trim()),
                        ),
                      ],
                      if (userProfile.showPastorPublicContact &&
                          (userProfile.publicEmail.trim().isNotEmpty ||
                              userProfile.publicPhone.trim().isNotEmpty)) ...[
                        const Divider(height: 24),
                        if (userProfile.publicEmail.trim().isNotEmpty)
                          _buildInfoRow(
                            context,
                            Icons.alternate_email_outlined,
                            'Public Email',
                            userProfile.publicEmail.trim(),
                          ),
                        if (userProfile.publicPhone.trim().isNotEmpty) ...[
                          if (userProfile.publicEmail.trim().isNotEmpty)
                            const Divider(height: 24),
                          _buildInfoRow(
                            context,
                            Icons.phone_forwarded_outlined,
                            'Public Phone',
                            userProfile.publicPhone.trim(),
                          ),
                        ],
                      ],
                    ]),
                    const SizedBox(height: 24),
                  ],
                  if (userProfile.bio.trim().isNotEmpty) ...[
                    Text('ABOUT',
                        style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 12),
                    _buildInfoCard(context, [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          userProfile.bio.trim(),
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 24),
                  ],
                  Text('FAMILY & RELATIONSHIPS',
                      style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 12),
                  StreamBuilder<List<FamilyRelationship>>(
                    stream: _familyService.watchFamilyLinks(
                      currentUserId: userProfile.uid,
                      churchId: userProfile.placeId,
                    ),
                    builder: (context, snapshot) {
                      final relationships = snapshot.data ?? const [];
                      return _buildFamilyCard(
                        context,
                        userProfile,
                        relationships,
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(BuildContext context, IconData icon, String label) {
    if (label.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFamilyCard(
    BuildContext context,
    UserProfile userProfile,
    List<FamilyRelationship> relationships,
  ) {
    final currentUserId =
        Provider.of<UserRoleProvider>(context, listen: false).userProfile?.uid;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accepted =
        relationships.where((relationship) => relationship.isAccepted).toList();
    final incomingPending = relationships
        .where((relationship) =>
            relationship.isPending &&
            relationship.relatedUserId == currentUserId)
        .toList();
    final outgoingPending = relationships
        .where((relationship) =>
            relationship.isPending && relationship.requesterId == currentUserId)
        .toList();

    return _buildInfoCard(context, [
      Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: colorScheme.secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.family_restroom,
                color: colorScheme.secondary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('My Family',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 2),
                Text(
                  accepted.isEmpty
                      ? 'No family members linked yet.'
                      : '${accepted.length} official family link${accepted.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  userProfile.showFamilyTree
                      ? 'Visible based on your family privacy settings.'
                      : 'Hidden from other members in your privacy settings.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: userProfile.showFamilyTree
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      if (incomingPending.isNotEmpty) ...[
        const SizedBox(height: 16),
        ...incomingPending.map((relationship) =>
            _buildIncomingFamilyRequest(context, relationship)),
      ],
      if (accepted.isNotEmpty) ...[
        const SizedBox(height: 16),
        ...accepted.map((relationship) =>
            _buildAcceptedFamilyRelationship(context, relationship)),
      ],
      if (outgoingPending.isNotEmpty) ...[
        const SizedBox(height: 12),
        Text(
          '${outgoingPending.length} request${outgoingPending.length == 1 ? '' : 's'} waiting for approval',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: _openFamilyLinkSheet,
          icon: const Icon(Icons.group_add_outlined),
          label: const Text('Connect Family'),
        ),
      )
    ]);
  }

  Widget _buildIncomingFamilyRequest(
    BuildContext context,
    FamilyRelationship relationship,
  ) {
    final theme = Theme.of(context);
    final requesterName = relationship.requesterName.isEmpty
        ? 'A member'
        : relationship.requesterName;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$requesterName listed you as their ${relationship.labelForRequester().toLowerCase()}.',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (relationship.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              relationship.note,
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _respondToFamilyRequest(
                    relationship,
                    false,
                  ),
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => _respondToFamilyRequest(
                    relationship,
                    true,
                  ),
                  child: const Text('Approve'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptedFamilyRelationship(
    BuildContext context,
    FamilyRelationship relationship,
  ) {
    final currentUserId =
        Provider.of<UserRoleProvider>(context, listen: false).userProfile?.uid;
    final otherName = relationship.requesterId == currentUserId
        ? relationship.relatedName
        : relationship.requesterName;
    final label = relationship.labelForViewer(currentUserId);
    final category = relationship.categoryForViewer(currentUserId);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const CircleAvatar(child: Icon(Icons.family_restroom)),
      title: Text(otherName.isEmpty ? 'Family member' : otherName),
      subtitle: Text('$label - $category'),
      dense: true,
    );
  }

  Widget _buildInfoCard(BuildContext context, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildInfoRow(
      BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 22, color: theme.colorScheme.primary), // Navy Icon
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text(value,
                  style: GoogleFonts.outfit(
                      fontSize: 16, fontWeight: FontWeight.normal)),
            ],
          ),
        )
      ],
    );
  }

  String _shortenChurchName(String name) {
    if (name.isEmpty) return 'No Church';
    if (name.length > 20) return '${name.substring(0, 18)}...';
    return name;
  }

  String _calculateMemberDuration(dynamic date) {
    if (date == null) return '';
    if (date is! DateTime && date is! String) return '';

    var joinDate = date is String
        ? DateTime.tryParse(date) ?? DateTime.now()
        : date as DateTime;
    final now = DateTime.now();
    if (joinDate.isAfter(now)) joinDate = now;

    var years = now.year - joinDate.year;
    var months = now.month - joinDate.month;
    var days = now.day - joinDate.day;

    if (days < 0) {
      months -= 1;
      days += DateTime(now.year, now.month, 0).day;
    }

    if (months < 0) {
      years -= 1;
      months += 12;
    }

    final parts = <String>[];
    if (years > 0) parts.add('${years}y');
    if (months > 0) parts.add('${months}mo');
    if (days > 0 || parts.isEmpty) parts.add('${days}d');

    return 'Member: ${parts.join(' ')}';
  }
}
