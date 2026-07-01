import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../providers/user_role_provider.dart';
import '../../models/family_relationship.dart';
import '../../models/priority_follow_up.dart';
import '../../models/user_profile.dart';
import '../../services/attendance_analysis_service.dart';
import '../../services/direct_message_service.dart';
import '../../services/bible_nudge_service.dart';
import '../../services/family_service.dart';
import '../../widgets/ui/app_feedback.dart';
import '../messages/message_thread_screen.dart';

class MembersListScreen extends StatefulWidget {
  const MembersListScreen({super.key});

  @override
  State<MembersListScreen> createState() => _MembersListScreenState();
}

class _MembersListScreenState extends State<MembersListScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final DirectMessageService _messageService = DirectMessageService();
  final BibleNudgeService _bibleNudgeService = BibleNudgeService();
  final AttendanceAnalysisService _attendanceAnalysisService =
      AttendanceAnalysisService();
  final FamilyService _familyService = FamilyService();

  List<Map<String, dynamic>> _members = [];
  Map<String, PriorityFollowUp> _careAlertsByUserId = {};
  bool _isLoading = true;
  bool _hasMore = true;
  int _currentOffset = 0;
  static const int _limit = 20;

  @override
  void initState() {
    super.initState();
    _fetchMembers();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _fetchMembers();
    }
  }

  Future<void> _fetchMembers() async {
    if (!mounted) return;

    // Get current user's church ID
    final userProvider = Provider.of<UserRoleProvider>(context, listen: false);
    final myChurchId = userProvider.userProfile?.placeId;

    if (myChurchId == null || myChurchId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('users')
          .select()
          .eq('placeId', myChurchId)
          .order('fullName', ascending: true)
          .range(_currentOffset, _currentOffset + _limit - 1)
          .timeout(const Duration(seconds: 10));

      if (response.isNotEmpty) {
        if (mounted) {
          setState(() {
            _members.addAll(response);
            _currentOffset += response.length;
            _isLoading = false;
            if (response.length < _limit) _hasMore = false;
          });
        }
        await _loadCareAlertsForVisibleMembers();
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasMore = false;
          });
        }
        await _loadCareAlertsForVisibleMembers();
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("Error fetching members: $e");
    }
  }

  // Search Logic (Client-side for simplicity per user plan, or robust server query)
  // For strict isolation, search MUST also include placeId
  Future<void> _performSearch(String queryText) async {
    setState(() {
      _isLoading = true;
      _members = [];
      _currentOffset = 0;
      _hasMore = false; // Disable pagination for search for now
    });

    final userProvider = Provider.of<UserRoleProvider>(context, listen: false);
    final myChurchId = userProvider.userProfile?.placeId;

    if (myChurchId == null) return;

    try {
      final cleanQuery = queryText.trim().replaceAll(',', ' ');
      final response = await Supabase.instance.client
          .from('users')
          .select()
          .eq('placeId', myChurchId)
          .or('fullName.ilike.%$cleanQuery%,email.ilike.%$cleanQuery%')
          .order('fullName')
          .limit(50)
          .timeout(const Duration(seconds: 10));

      if (mounted) {
        setState(() {
          _members = response;
          _isLoading = false;
        });
      }
      await _loadCareAlertsForVisibleMembers();
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCareAlertsForVisibleMembers() async {
    if (!mounted || _members.isEmpty) {
      if (mounted) setState(() => _careAlertsByUserId = {});
      return;
    }

    final currentUser =
        Provider.of<UserRoleProvider>(context, listen: false).userProfile;
    final churchId = currentUser?.churchId;
    if (churchId == null || churchId.isEmpty) return;

    try {
      final alerts = await _attendanceAnalysisService.getOpenFollowUpsByUserIds(
        churchId,
        _members.map((member) => member['uid']?.toString() ?? ''),
      );
      if (!mounted) return;
      setState(() => _careAlertsByUserId = alerts);
    } catch (error) {
      debugPrint('Could not load attendance care markers: $error');
    }
  }

  Future<void> _openMessageWithMember(Map<String, dynamic> data) async {
    final currentUser =
        Provider.of<UserRoleProvider>(context, listen: false).userProfile;
    if (currentUser == null) return;

    try {
      final otherUser = UserProfile.fromMap(data);
      final conversation = await _messageService.getOrCreateConversation(
        currentUser: currentUser,
        otherUser: otherUser,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MessageThreadScreen(
            conversation: conversation,
            otherUser: otherUser,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final otherUser = UserProfile.fromMap(data);
      AppFeedback.show(
        context,
        _messageAccessHelpForMember(otherUser, error),
        type: AppFeedbackType.warning,
      );
    }
  }

  String _messageAccessHelpForMember(UserProfile member, Object error) {
    final currentUser =
        Provider.of<UserRoleProvider>(context, listen: false).userProfile;
    final errorText = error.toString().toLowerCase();
    final isOtherChurch = currentUser?.churchId.isNotEmpty == true &&
        member.churchId.isNotEmpty &&
        member.churchId != currentUser!.churchId;
    final looksLikeAccessRule = errorText.contains('bible nudge') ||
        errorText.contains('outside your church') ||
        errorText.contains('profile was not found') ||
        errorText.contains('not accepting messages') ||
        errorText.contains('not available') ||
        errorText.contains('blocked');

    if (isOtherChurch && looksLikeAccessRule) {
      return 'This person is outside your church. Send a Bible Nudge first. Once both people accept, you can view their profile and message each other anytime.';
    }

    return 'Could not open message: $error';
  }

  Future<void> _sendBibleNudge(UserProfile recipient) async {
    final sender =
        Provider.of<UserRoleProvider>(context, listen: false).userProfile;
    if (sender == null) return;

    final senderChurch = sender.churchId.trim();
    final recipientChurch = recipient.churchId.trim();
    if (senderChurch.isNotEmpty &&
        recipientChurch.isNotEmpty &&
        senderChurch == recipientChurch) {
      AppFeedback.show(
        context,
        'Bible Nudge is only for people outside your church. Use Message for members of your church.',
        type: AppFeedbackType.info,
      );
      return;
    }

    final messageController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Bible Nudge ${recipient.fullName}'),
          content: TextField(
            controller: messageController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Optional note',
              hintText: 'Example: Want to study John 15 this week?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Send Nudge'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      messageController.dispose();
      return;
    }

    try {
      await _bibleNudgeService.sendNudge(
        sender: sender,
        recipient: recipient,
        message: messageController.text,
      );
      if (!mounted) return;
      AppFeedback.show(
        context,
        'Bible Nudge sent to ${recipient.fullName}.',
        type: AppFeedbackType.success,
      );
    } catch (error) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        'Could not send Bible Nudge: $error',
        type: AppFeedbackType.error,
      );
    } finally {
      messageController.dispose();
    }
  }

  void _showMemberDetails(Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final currentUser =
        Provider.of<UserRoleProvider>(context, listen: false).userProfile;
    final currentUserId =
        currentUser?.uid ?? Supabase.instance.client.auth.currentUser?.id;
    final memberProfile = UserProfile.fromMap(data);
    final isOwnProfile = memberProfile.uid == currentUserId;
    final isPrivate = memberProfile.isProfilePrivate && !isOwnProfile;
    final displayName =
        memberProfile.fullName.isNotEmpty ? memberProfile.fullName : 'Member';
    final bio = memberProfile.bio.trim();
    final isSameChurch = (currentUser?.placeId ?? '').isNotEmpty &&
        currentUser?.placeId == memberProfile.placeId;
    final showContactInfo = isOwnProfile ||
        (!isPrivate &&
            memberProfile.canShowContactInfoTo(isSameChurch: isSameChurch));
    final canViewExtendedProfile = isOwnProfile ||
        currentUser?.capabilities.canManageMembersBasic == true ||
        currentUser?.hasPastoralRole == true;
    final hasExtendedProfileDetails = memberProfile.dateOfBirth != null ||
        memberProfile.gender.trim().isNotEmpty ||
        memberProfile.occupation.trim().isNotEmpty ||
        memberProfile.address.trim().isNotEmpty ||
        memberProfile.city.trim().isNotEmpty ||
        memberProfile.parish.trim().isNotEmpty ||
        memberProfile.emergencyContactName.trim().isNotEmpty ||
        memberProfile.emergencyContactPhone.trim().isNotEmpty;
    final careAlert = _careAlertsByUserId[memberProfile.uid];
    final canMessage =
        !isOwnProfile && memberProfile.allowMessages && !isPrivate;
    final canNudge = !isOwnProfile && !isPrivate && !isSameChurch;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2))),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: memberProfile.photoUrl.isNotEmpty
                          ? NetworkImage(memberProfile.photoUrl)
                          : null,
                      child: memberProfile.photoUrl.isEmpty
                          ? Text(
                              displayName[0].toUpperCase(),
                              style: const TextStyle(fontSize: 30),
                            )
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      displayName,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _calculateMemberDuration(memberProfile.joinDate),
                        style: TextStyle(
                          color: theme.colorScheme.onSecondaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        bio,
                        textAlign: TextAlign.center,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    if (careAlert != null) ...[
                      const SizedBox(height: 16),
                      _buildCareAlertNotice(context, careAlert),
                    ],
                    const SizedBox(height: 24),
                    if (isPrivate)
                      _buildPrivacyNotice(
                        context,
                        'Private profile',
                        'This member keeps profile details private.',
                      )
                    else ...[
                      _buildMemberFamilyPreview(
                        context,
                        memberProfile,
                        currentUserId,
                      ),
                      const SizedBox(height: 12),
                      if (showContactInfo) ...[
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.email_outlined),
                          title: Text(memberProfile.email.isEmpty
                              ? 'No email'
                              : memberProfile.email),
                          onTap: memberProfile.email.isEmpty
                              ? null
                              : () => launchUrl(
                                    Uri.parse('mailto:${memberProfile.email}'),
                                  ),
                        ),
                        if (memberProfile.phone.isNotEmpty)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.phone_outlined),
                            title: Text(memberProfile.phone),
                            onTap: () => launchUrl(
                              Uri.parse('tel:${memberProfile.phone}'),
                            ),
                          ),
                      ] else
                        _buildPrivacyNotice(
                          context,
                          'Contact info hidden',
                          'This member has turned off email and phone visibility.',
                        ),
                      if (canViewExtendedProfile &&
                          hasExtendedProfileDetails) ...[
                        const Divider(height: 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Member Details',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (memberProfile.dateOfBirth != null)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.cake_outlined),
                            title: Text(DateFormat.yMMMMd()
                                .format(memberProfile.dateOfBirth!)),
                            subtitle: const Text('Date of birth'),
                          ),
                        if (memberProfile.gender.trim().isNotEmpty)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.person_search_outlined),
                            title: Text(memberProfile.gender.trim()),
                            subtitle: const Text('Gender'),
                          ),
                        if (memberProfile.occupation.trim().isNotEmpty)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.work_outline),
                            title: Text(memberProfile.occupation.trim()),
                            subtitle: const Text('Occupation'),
                          ),
                        if (memberProfile.address.trim().isNotEmpty ||
                            memberProfile.city.trim().isNotEmpty ||
                            memberProfile.parish.trim().isNotEmpty)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.home_outlined),
                            title: Text([
                              memberProfile.address,
                              memberProfile.city,
                              memberProfile.parish,
                            ]
                                .where((part) => part.trim().isNotEmpty)
                                .join(', ')),
                            subtitle: const Text('Address'),
                          ),
                        if (memberProfile.emergencyContactName
                                .trim()
                                .isNotEmpty ||
                            memberProfile.emergencyContactPhone
                                .trim()
                                .isNotEmpty)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading:
                                const Icon(Icons.contact_emergency_outlined),
                            title: Text([
                              memberProfile.emergencyContactName,
                              memberProfile.emergencyContactPhone,
                            ]
                                .where((part) => part.trim().isNotEmpty)
                                .join(' - ')),
                            subtitle: const Text('Emergency contact'),
                          ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            _buildProfileActions(
              memberProfile: memberProfile,
              data: data,
              canMessage: canMessage,
              canNudge: canNudge,
              careAlert: careAlert,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileActions({
    required UserProfile memberProfile,
    required Map<String, dynamic> data,
    required bool canMessage,
    required bool canNudge,
    PriorityFollowUp? careAlert,
  }) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hasAction = canMessage || canNudge;
          final twoColumn = hasAction && constraints.maxWidth >= 360;
          final buttonWidth = twoColumn
              ? (constraints.maxWidth - 12) / 2
              : constraints.maxWidth;

          final actions = <Widget>[
            SizedBox(
              width: hasAction ? buttonWidth : constraints.maxWidth,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ),
            if (canNudge)
              SizedBox(
                width: buttonWidth,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.menu_book_outlined),
                  label: const Text(
                    'Bible Nudge',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _sendBibleNudge(memberProfile);
                  },
                ),
              ),
            if (canMessage)
              SizedBox(
                width: constraints.maxWidth,
                child: FilledButton.icon(
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: Text(
                    careAlert == null ? 'Message' : 'Reach Out',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    _openMessageWithMember(data);
                  },
                ),
              ),
          ];

          return Wrap(
            spacing: 12,
            runSpacing: 10,
            children: actions,
          );
        },
      ),
    );
  }

  Widget _buildCareAlertNotice(
    BuildContext context,
    PriorityFollowUp careAlert,
  ) {
    final theme = Theme.of(context);
    final weeks = careAlert.absenceStreakWeeks;
    final lastSeen = careAlert.lastAttendedDate == null
        ? 'No attendance recorded yet'
        : 'Last attended ${_formatShortDate(careAlert.lastAttendedDate!)}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.favorite_outline,
            color: theme.colorScheme.error,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Care check-in',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Missed $weeks week${weeks == 1 ? '' : 's'} • $lastSeen',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberFamilyPreview(
    BuildContext context,
    UserProfile memberProfile,
    String? currentUserId,
  ) {
    final theme = Theme.of(context);

    if (!memberProfile.showFamilyTree) {
      return _buildPrivacyNotice(
        context,
        'Family tree hidden',
        'This member has turned off family tree visibility.',
      );
    }

    return FutureBuilder<List<FamilyRelationship>>(
      future: _familyService.visibleFamilyLinksForProfile(
        profileUserId: memberProfile.uid,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return _buildPrivacyNotice(
            context,
            'Family tree unavailable',
            'Family connections could not be loaded right now.',
          );
        }

        final relationships = snapshot.data ?? const <FamilyRelationship>[];
        if (relationships.isEmpty) {
          return _buildPrivacyNotice(
            context,
            'No visible family links',
            'No approved family connections are visible on this profile.',
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_tree_outlined,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Family Connections',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...relationships.take(6).map(
                    (relationship) => _buildVisibleFamilyRow(
                      context,
                      relationship,
                      memberProfile,
                      currentUserId,
                    ),
                  ),
              if (relationships.length > 6)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '+${relationships.length - 6} more family link${relationships.length - 6 == 1 ? '' : 's'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVisibleFamilyRow(
    BuildContext context,
    FamilyRelationship relationship,
    UserProfile profileOwner,
    String? currentUserId,
  ) {
    final theme = Theme.of(context);
    final otherName = relationship.requesterId == profileOwner.uid
        ? relationship.relatedName
        : relationship.requesterName;
    final label = profileOwner.showFamilyRelationshipTypes
        ? relationship.labelForViewer(profileOwner.uid)
        : 'Family connection';
    final category = profileOwner.showFamilyRelationshipTypes
        ? relationship.categoryForViewer(profileOwner.uid)
        : 'Private relationship type';
    final isCurrentUser = currentUserId != null &&
        (relationship.requesterId == currentUserId ||
            relationship.relatedUserId == currentUserId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            child: Icon(
              isCurrentUser ? Icons.how_to_reg_outlined : Icons.family_restroom,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  otherName.isEmpty ? 'Family member' : otherName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$label - $category',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyNotice(
    BuildContext context,
    String title,
    String message,
  ) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.privacy_tip_outlined,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _calculateMemberDuration(dynamic date) {
    if (date == null) return '';
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
    if (years > 0) parts.add('$years ${years == 1 ? 'year' : 'years'}');
    if (months > 0) {
      parts.add('$months ${months == 1 ? 'month' : 'months'}');
    }
    if (days > 0 || parts.isEmpty) {
      parts.add('$days ${days == 1 ? 'day' : 'days'}');
    }

    return 'Member for ${parts.join(', ')}';
  }

  String _formatShortDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final canPop = Navigator.canPop(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                right: 16,
                bottom: 16),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (canPop) ...[
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back),
                        color: Colors.white,
                        tooltip: 'Back',
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        'Community Directory',
                        style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchController,
                  onSubmitted: _performSearch, // Trigger search
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Search members...',
                    hintStyle: TextStyle(color: Colors.grey[600]),
                    prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                    filled: true,
                    fillColor: theme.colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.clear, color: Colors.grey[600]),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _members = [];
                          _careAlertsByUserId = {};
                          _isLoading = true;
                          _hasMore = true;
                          _currentOffset = 0;
                        });
                        _fetchMembers();
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading && _members.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _members.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline,
                                size: 64,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.2)),
                            const SizedBox(height: 16),
                            Text(
                              'No members found',
                              style: GoogleFonts.outfit(
                                fontSize: 18,
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (_searchController.text.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _members = [];
                                    _careAlertsByUserId = {};
                                    _isLoading = true;
                                    _hasMore = true;
                                    _currentOffset = 0;
                                  });
                                  _fetchMembers();
                                },
                                child: const Text('Clear Search'),
                              ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _members.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _members.length) {
                            return const Center(
                                child: Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator()));
                          }

                          final member = _members[index];
                          final fullName =
                              (member['fullName'] as String?)?.trim();
                          final displayName =
                              fullName != null && fullName.isNotEmpty
                                  ? fullName
                                  : 'Member';
                          final role = (member['roles'] != null &&
                                  (member['roles'] as List).isNotEmpty)
                              ? member['roles'][0]
                              : 'Member';
                          final bio = (member['bio'] as String?)?.trim() ?? '';
                          final careAlert = _careAlertsByUserId[
                              member['uid']?.toString() ?? ''];

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                                color: theme.cardTheme.color,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.shadowColor
                                        .withValues(alpha: 0.1),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  )
                                ]),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () =>
                                    _showMemberDetails(_members[index]),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          CircleAvatar(
                                            radius: 28,
                                            backgroundColor: colorScheme
                                                .surfaceContainerHighest,
                                            backgroundImage:
                                                (member['photoUrl'] != null &&
                                                        member['photoUrl'] !=
                                                            '')
                                                    ? NetworkImage(
                                                        member['photoUrl'])
                                                    : null,
                                            child: (member['photoUrl'] ==
                                                        null ||
                                                    member['photoUrl'] == '')
                                                ? Text(displayName[0],
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: colorScheme
                                                            .primary))
                                                : null,
                                          ),
                                          if (careAlert != null)
                                            Positioned(
                                              right: -1,
                                              top: -1,
                                              child: Container(
                                                width: 15,
                                                height: 15,
                                                decoration: BoxDecoration(
                                                  color: colorScheme.error,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: theme
                                                        .scaffoldBackgroundColor,
                                                    width: 2,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              displayName,
                                              style: GoogleFonts.outfit(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                  color: colorScheme.onSurface),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              role, // Shows Role
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: colorScheme.primary,
                                                  fontWeight: FontWeight.bold),
                                            ),
                                            if (careAlert != null) ...[
                                              const SizedBox(height: 5),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: colorScheme
                                                      .errorContainer
                                                      .withValues(alpha: 0.5),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          999),
                                                ),
                                                child: Text(
                                                  'Care check-in • ${careAlert.absenceStreakWeeks} wk',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: colorScheme
                                                        .onErrorContainer,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            if (bio.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                bio,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      Icon(Icons.chevron_right,
                                          color: colorScheme.onSurfaceVariant),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
