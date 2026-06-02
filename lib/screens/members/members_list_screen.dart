import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_colors.dart';
import '../../providers/user_role_provider.dart';
import '../../models/user_profile.dart';
import '../../services/direct_message_service.dart';
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

  List<Map<String, dynamic>> _members = [];
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
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasMore = false;
          });
        }
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
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open message: $error')),
      );
    }
  }

  void _showMemberDetails(Map<String, dynamic> data) {
    final theme = Theme.of(context);
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isPrivate =
        data['isProfilePrivate'] == true && data['uid'] != currentUserId;
    final fullName = (data['fullName'] as String?)?.trim();
    final displayName =
        fullName != null && fullName.isNotEmpty ? fullName : 'Member';
    final bio = (data['bio'] as String?)?.trim() ?? '';
    final canMessage = data['uid'] != currentUserId &&
        data['allowMessages'] != false &&
        !isPrivate;

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
            const SizedBox(height: 20),
            CircleAvatar(
              radius: 50,
              backgroundImage:
                  (data['photoUrl'] != null && data['photoUrl'] != '')
                      ? NetworkImage(data['photoUrl'])
                      : null,
              child: (data['photoUrl'] == null || data['photoUrl'] == '')
                  ? Text(displayName[0].toUpperCase(),
                      style: const TextStyle(fontSize: 30))
                  : null,
            ),
            const SizedBox(height: 16),
            Text(displayName,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            // Member Duration
            if (data['joinDate'] != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(16)),
                child: Text(
                  _calculateMemberDuration(data['joinDate']),
                  style: TextStyle(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.bold),
                ),
              ),
            if (bio.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  bio,
                  textAlign: TextAlign.center,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),
            if (isPrivate)
              const ListTile(
                leading: Icon(Icons.lock_outline),
                title: Text('This member keeps contact details private.'),
              )
            else ...[
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: Text(data['email'] ?? 'No email'),
                onTap: () => launchUrl(Uri.parse('mailto:${data["email"]}')),
              ),
              if (data['phone'] != null)
                ListTile(
                  leading: const Icon(Icons.phone_outlined),
                  title: Text(data['phone']),
                  onTap: () => launchUrl(Uri.parse('tel:${data["phone"]}')),
                ),
            ],

            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ),
                  if (canMessage) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Message'),
                        onPressed: () {
                          Navigator.pop(context);
                          _openMessageWithMember(data);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            )
          ],
        ),
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
                                      CircleAvatar(
                                        radius: 28,
                                        backgroundColor:
                                            colorScheme.surfaceContainerHighest,
                                        backgroundImage: (member['photoUrl'] !=
                                                    null &&
                                                member['photoUrl'] != '')
                                            ? NetworkImage(member['photoUrl'])
                                            : null,
                                        child: (member['photoUrl'] == null ||
                                                member['photoUrl'] == '')
                                            ? Text(displayName[0],
                                                style: TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: colorScheme.primary))
                                            : null,
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
