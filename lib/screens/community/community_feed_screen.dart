import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/app_skeleton_list_item.dart';
import '../../widgets/ui/app_text_field.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../services/community_service.dart';
import '../../services/church_service.dart';
import '../../services/bible_nudge_service.dart';
import '../../services/direct_message_service.dart';
import '../../services/feed_scroll_service.dart';
import '../../services/moderation_service.dart';
import '../../services/user_service.dart';
import '../../models/church_model.dart';
import '../../models/community_story.dart';
import '../../models/post.dart';
import '../../models/user_profile.dart';
import 'post_detail_screen.dart';
import '../messages/message_thread_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/inbox_icon_button.dart';

class CommunityFeedScreen extends StatefulWidget {
  const CommunityFeedScreen({
    super.key,
    this.showBottomMenu = true,
  });

  final bool showBottomMenu;

  @override
  State<CommunityFeedScreen> createState() => _CommunityFeedScreenState();
}

class _CommunityFeedScreenState extends State<CommunityFeedScreen>
    with WidgetsBindingObserver {
  final TextEditingController _postController = TextEditingController();
  final CommunityService _communityService = CommunityService();
  final DirectMessageService _messageService = DirectMessageService();
  final BibleNudgeService _bibleNudgeService = BibleNudgeService();
  final ModerationService _moderationService = ModerationService();
  final UserService _userService = UserService();
  final ChurchService _churchService = ChurchService();
  final GoTrueClient _auth = Supabase.instance.client.auth;
  final ScrollController _feedScrollController = ScrollController();
  StreamSubscription<void>? _scrollToTopSubscription;
  Timer? _scrollIdleTimer;
  bool _isPosting = false;
  bool _isPostingStory = false;
  bool _showMediaPreviews = true;
  bool _confirmBeforePosting = false;
  bool _composeActionsOpen = false;
  bool _showFloatingCompose = true;
  int _feedRefreshToken = 0;
  int _storiesRefreshToken = 0;
  Set<String> _watchedStoryIds = {};
  Set<String> _blockedUserIds = {};
  final Map<String, String> _churchNamesById = {};
  final Set<String> _loadingChurchNameIds = {};
  final Map<String, List<String>> _postLikeOverrides = {};
  String _feedScope = 'church';
  List<String>? _selectedFeedChurchIds;
  String? _selectedFeedLabel;
  bool _postVisibleToAllChurches = false;

  XFile? _selectedMedia;
  Uint8List? _selectedImagePreviewBytes;
  String? _mediaType; // 'image' or 'video'

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCommunityPreferences();
    _loadWatchedStories();
    _loadBlockedUsers();
    _communityService.cleanupExpiredStories();
    _communityService.cleanupVanishingContent();
    _scrollToTopSubscription =
        FeedScrollService.scrollToTopRequests.listen((_) => _scrollToTop());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;

    _communityService.cleanupExpiredStories();
    _communityService.cleanupVanishingContent();
    _loadBlockedUsers();
    setState(() {
      _feedRefreshToken++;
      _storiesRefreshToken++;
    });
  }

  Future<void> _loadCommunityPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final dataSaver = prefs.getBool('data_saver') ?? false;
    final uid = _auth.currentUser?.id ?? 'guest';
    final savedScope = prefs.getString('community_feed_scope_$uid') ?? 'church';
    final savedChurchIds =
        prefs.getStringList('community_feed_church_ids_$uid');
    final savedLabel = prefs.getString('community_feed_label_$uid');
    final validScope =
        savedScope == 'all' || savedScope == 'custom' || savedScope == 'church'
            ? savedScope
            : 'church';
    setState(() {
      _showMediaPreviews =
          !dataSaver && (prefs.getBool('community_show_media') ?? true);
      _confirmBeforePosting =
          prefs.getBool('community_confirm_before_posting') ?? false;
      _feedScope = validScope == 'custom' &&
              (savedChurchIds == null || savedChurchIds.isEmpty)
          ? 'church'
          : validScope;
      _selectedFeedChurchIds = _feedScope == 'custom' ? savedChurchIds : null;
      _selectedFeedLabel = _feedScope == 'custom' ? savedLabel : null;
    });
  }

  Future<void> _saveFeedScopePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = _auth.currentUser?.id ?? 'guest';
    await prefs.setString('community_feed_scope_$uid', _feedScope);
    if (_selectedFeedChurchIds == null || _selectedFeedChurchIds!.isEmpty) {
      await prefs.remove('community_feed_church_ids_$uid');
    } else {
      await prefs.setStringList(
        'community_feed_church_ids_$uid',
        _selectedFeedChurchIds!,
      );
    }
    if (_selectedFeedLabel == null || _selectedFeedLabel!.trim().isEmpty) {
      await prefs.remove('community_feed_label_$uid');
    } else {
      await prefs.setString('community_feed_label_$uid', _selectedFeedLabel!);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollToTopSubscription?.cancel();
    _scrollIdleTimer?.cancel();
    _feedScrollController.dispose();
    _postController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (!_feedScrollController.hasClients) return;
    _feedScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  bool _handleFeedScrollNotification(ScrollNotification notification) {
    if (notification is UserScrollNotification ||
        notification is ScrollUpdateNotification) {
      _scrollIdleTimer?.cancel();
      if (_showFloatingCompose) {
        setState(() {
          _showFloatingCompose = false;
          _composeActionsOpen = false;
        });
      }
      _scrollIdleTimer = Timer(const Duration(milliseconds: 420), () {
        if (!mounted) return;
        setState(() => _showFloatingCompose = true);
      });
    }
    return false;
  }

  Future<void> _loadWatchedStories() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = _auth.currentUser?.id ?? 'guest';
    if (!mounted) return;
    setState(() {
      _watchedStoryIds =
          (prefs.getStringList('watched_status_ids_$uid') ?? const []).toSet();
    });
  }

  Future<void> _loadBlockedUsers() async {
    try {
      final blockedUserIds = await _moderationService.blockedUserIds();
      if (!mounted) return;
      setState(() => _blockedUserIds = blockedUserIds);
    } catch (_) {
      if (mounted) setState(() => _blockedUserIds = {});
    }
  }

  Future<void> _markStoryWatched(CommunityStory story) async {
    if (story.id.isEmpty || _watchedStoryIds.contains(story.id)) return;

    final uid = _auth.currentUser?.id ?? 'guest';
    final nextWatched = {..._watchedStoryIds, story.id};
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('watched_status_ids_$uid', nextWatched.toList());
    if (!mounted) return;
    setState(() => _watchedStoryIds = nextWatched);
  }

  Future<void> _pickImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final previewBytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedMedia = image;
        _selectedImagePreviewBytes = previewBytes;
        _mediaType = 'image';
      });
    }
  }

  Future<void> _pickVideo() async {
    final ImagePicker picker = ImagePicker();
    final XFile? video = await picker.pickVideo(source: ImageSource.gallery);

    // Check file size limit (50 MB) before accepting
    if (video != null) {
      final size = await video.length();
      if (size > 52428800) {
        // 50MB
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Video file size must be less than 50MB')),
          );
        }
        return;
      }

      setState(() {
        _selectedMedia = video;
        _selectedImagePreviewBytes = null;
        _mediaType = 'video';
      });
    }
  }

  Future<void> _showCreateStorySheet() async {
    final captionController = TextEditingController();
    XFile? selectedStoryMedia;
    Uint8List? selectedStoryPreviewBytes;
    String? selectedStoryType;
    var shareWithAllChurches = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> pickStoryMedia(ImageSource source) async {
            final picker = ImagePicker();
            final image = await picker.pickImage(source: source);
            if (image == null) return;
            final bytes = await image.readAsBytes();
            if (!sheetContext.mounted) return;
            setSheetState(() {
              selectedStoryMedia = image;
              selectedStoryPreviewBytes = bytes;
              selectedStoryType = 'image';
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Create Status',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  AspectRatio(
                    aspectRatio: 9 / 14,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => pickStoryMedia(ImageSource.gallery),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                          image: selectedStoryPreviewBytes == null
                              ? null
                              : DecorationImage(
                                  image:
                                      MemoryImage(selectedStoryPreviewBytes!),
                                  fit: BoxFit.cover,
                                ),
                        ),
                        child: selectedStoryPreviewBytes == null
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add_photo_alternate_outlined,
                                      size: 42,
                                      color:
                                          Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(height: 10),
                                    const Text('Add a photo'),
                                  ],
                                ),
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: captionController,
                    hint: 'Add a short caption...',
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  _AudienceSelector(
                    visibleToAllChurches: shareWithAllChurches,
                    onChanged: (value) => setSheetState(
                      () => shareWithAllChurches = value,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isPostingStory
                          ? null
                          : () async {
                              await _handleStoryPost(
                                caption: captionController.text,
                                media: selectedStoryMedia,
                                mediaType: selectedStoryType,
                                visibleToAllChurches: shareWithAllChurches,
                              );
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                      icon: _isPostingStory
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Share Status'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleStoryPost({
    required String caption,
    required XFile? media,
    required String? mediaType,
    required bool visibleToAllChurches,
  }) async {
    if (_isPostingStory) return;
    final cleanCaption = caption.trim();
    if (cleanCaption.isEmpty && media == null) return;

    setState(() => _isPostingStory = true);
    try {
      final authUser = _auth.currentUser;
      final profile = context.read<UserRoleProvider>().userProfile;
      final churchId = profile?.placeId ?? '';
      if (authUser == null || churchId.isEmpty) return;

      String? mediaUrl;
      String? mediaPath;
      if (media != null) {
        final mimeType = media.mimeType ?? 'image/jpeg';
        final extension = _extensionFor(media, mimeType);
        final fileName =
            '$churchId/stories/${DateTime.now().millisecondsSinceEpoch}_${authUser.id}.$extension';
        mediaPath = fileName;
        mediaUrl = await _communityService.uploadMediaBytes(
          await media.readAsBytes(),
          fileName,
          contentType: mimeType,
        );
      }

      final story = CommunityStory(
        id: '',
        churchId: churchId,
        authorId: authUser.id,
        authorName: profile?.fullName.isNotEmpty == true
            ? profile!.fullName
            : authUser.userMetadata?['full_name'] ?? 'Member',
        authorPhoto: profile?.photoUrl.isNotEmpty == true
            ? profile!.photoUrl
            : authUser.userMetadata?['avatar_url'],
        caption: cleanCaption.isEmpty ? null : cleanCaption,
        mediaUrl: mediaUrl,
        mediaPath: mediaPath,
        mediaType: mediaType,
        visibleToAllChurches: visibleToAllChurches,
        createdAt: DateTime.now(),
        expiresAt: DateTime.now().add(const Duration(hours: 24)),
      );

      await _communityService.addStory(story);
      if (mounted) {
        setState(() => _storiesRefreshToken++);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not share status: $error')),
      );
    } finally {
      if (mounted) setState(() => _isPostingStory = false);
    }
  }

  Future<bool> _handlePost() async {
    if (_isPosting) return false;
    if (_postController.text.trim().isEmpty && _selectedMedia == null) {
      return false;
    }

    if (_confirmBeforePosting) {
      final audience =
          _postVisibleToAllChurches ? 'all churches' : 'your church feed';
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Post to Community?'),
          content: Text('This will be visible in $audience.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Post'),
            ),
          ],
        ),
      );
      if (confirmed != true) return false;
      if (!mounted) return false;
    }

    setState(() => _isPosting = true);

    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final userProvider =
          Provider.of<UserRoleProvider>(context, listen: false);
      final churchId = userProvider.userProfile?.placeId;

      if (churchId == null || churchId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Error: No church affiliation found. Cannot post.')),
          );
        }
        return false;
      }

      String? mediaUrl;
      String? mediaPath;
      if (_selectedMedia != null) {
        final mimeType = _selectedMedia!.mimeType ??
            (_mediaType == 'image' ? 'image/jpeg' : 'video/mp4');
        final extension = _extensionFor(_selectedMedia!, mimeType);
        final fileName =
            '$churchId/${DateTime.now().millisecondsSinceEpoch}_${user.id}.$extension';
        mediaPath = fileName;
        mediaUrl = await _communityService.uploadMediaBytes(
          await _selectedMedia!.readAsBytes(),
          fileName,
          contentType: mimeType,
        );
      }

      String authorName = user.userMetadata?['full_name'] ?? 'Anonymous Member';

      final newPost = Post(
        id: '', // Handled by DB
        authorName: authorName,
        authorId: user.id,
        authorPhoto: user.userMetadata?['avatar_url'],
        content: _postController.text.trim(),
        timestamp: DateTime.now(),
        likes: [],
        commentsCount: 0,
        placeId: churchId,
        mediaUrl: mediaUrl,
        mediaPath: mediaPath,
        mediaType: _mediaType,
        expiresAt: DateTime.now().add(const Duration(days: 30)),
        visibleToAllChurches: _postVisibleToAllChurches,
      );

      await _communityService.addPost(newPost);

      _postController.clear();
      setState(() {
        _selectedMedia = null;
        _selectedImagePreviewBytes = null;
        _mediaType = null;
        _postVisibleToAllChurches = false;
        _feedRefreshToken++;
      });
      if (mounted) FocusScope.of(context).unfocus();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Posted successfully!')),
        );
      }
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error posting: $e')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  String _extensionFor(XFile file, String mimeType) {
    final name = file.name.trim();
    if (name.contains('.')) {
      final extension = name.split('.').last.toLowerCase();
      if (extension.length <= 5) return extension;
    }

    return switch (mimeType) {
      'image/png' => 'png',
      'image/jpg' => 'jpg',
      'image/gif' => 'gif',
      'image/webp' => 'webp',
      'image/heic' => 'heic',
      'image/heif' => 'heif',
      'video/quicktime' => 'mov',
      'video/x-m4v' => 'm4v',
      'video/webm' => 'webm',
      'video/mp4' => 'mp4',
      _ => _mediaType == 'video' ? 'mp4' : 'jpg',
    };
  }

  bool _canDeletePost(Post post) {
    return post.authorId == _auth.currentUser?.id;
  }

  Future<void> _confirmDeletePost(Post post) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text(
            'This will remove your post, its comments, and any attached media.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _communityService.deletePost(post);
      if (!mounted) return;
      AppFeedback.show(
        context,
        'Post deleted.',
        type: AppFeedbackType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AppFeedback.show(
        context,
        'Could not delete post: $e',
        type: AppFeedbackType.error,
      );
    }
  }

  Future<void> _messagePostAuthor(Post post) async {
    final currentUser = context.read<UserRoleProvider>().userProfile;
    final currentAuthUser = _auth.currentUser;
    if (currentUser == null || currentAuthUser == null) return;

    if (post.authorId == currentAuthUser.id) {
      Navigator.pushNamed(context, '/profile');
      return;
    }

    try {
      final conversation =
          await _messageService.getOrCreateConversationWithUserId(
        currentUser: currentUser,
        otherUserId: post.authorId,
      );
      final otherUser = await _messageService.getConversationPeer(
              conversation, currentAuthUser.id) ??
          _profileFromPostAuthor(post);
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
      final fallbackAuthor = _profileFromPostAuthor(post);
      if (_shouldOfferBibleNudgeForPost(post, currentUser, error)) {
        await _showBibleNudgeRequiredPrompt(fallbackAuthor);
        return;
      }
      AppFeedback.show(
        context,
        _messageAccessHelpForPost(post, currentUser, error),
        type: AppFeedbackType.warning,
      );
    }
  }

  UserProfile _profileFromPostAuthor(Post post) {
    return UserProfile(
      uid: post.authorId,
      email: '',
      fullName:
          post.authorName.trim().isEmpty ? 'Member' : post.authorName.trim(),
      phoneNumber: '',
      placeId: post.placeId,
      placeName: _churchNamesById[post.placeId] ?? '',
      roles: const ['Member'],
      joinDate: DateTime.now(),
      photoUrl: post.authorPhoto ?? '',
      allowMessages: true,
    );
  }

  bool _shouldOfferBibleNudgeForPost(
    Post post,
    UserProfile currentUser,
    Object error,
  ) {
    return _isDifferentKnownChurch(post.placeId, currentUser.churchId) &&
        _isBibleNudgeAccessIssue(error);
  }

  bool _shouldOfferBibleNudgeForProfile(
    UserProfile otherUser,
    UserProfile currentUser,
    Object error,
  ) {
    return _isDifferentKnownChurch(otherUser.churchId, currentUser.churchId) &&
        _isBibleNudgeAccessIssue(error);
  }

  bool _isDifferentKnownChurch(String otherChurchId, String currentChurchId) {
    final other = otherChurchId.trim();
    final current = currentChurchId.trim();
    return other.isNotEmpty && current.isNotEmpty && other != current;
  }

  bool _isBibleNudgeAccessIssue(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('bible nudge') ||
        message.contains('outside your church') ||
        message.contains('member profile was not found') ||
        message.contains('profile was not found') ||
        message.contains('not accepting messages') ||
        message.contains('not available') ||
        message.contains('blocked');
  }

  Future<void> _showBibleNudgeRequiredPrompt(UserProfile recipient) async {
    if (!mounted) return;

    final displayName = recipient.fullName.trim().isNotEmpty
        ? recipient.fullName.trim()
        : recipient.email.trim().isNotEmpty
            ? recipient.email.trim()
            : 'this member';

    final shouldSend = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Bible Nudge required'),
          content: Text(
            'To view $displayName\'s profile or send a message, send a Bible Nudge first. Once both of you accept, you can view the profile and message each other anytime.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not now'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Bible Nudge'),
            ),
          ],
        );
      },
    );

    if (shouldSend == true && mounted) {
      await _sendBibleNudge(recipient);
    }
  }

  String _messageAccessHelpForPost(
    Post post,
    UserProfile currentUser,
    Object error,
  ) {
    final isOtherChurch =
        post.placeId.trim().isNotEmpty && post.placeId != currentUser.churchId;
    final isAccessIssue = _isBibleNudgeAccessIssue(error);

    if (isOtherChurch && isAccessIssue) {
      return 'This person is outside your church. Send a Bible Nudge first. Once both people accept, you can view their profile and message each other anytime.';
    }

    return 'Could not open message: $error';
  }

  Future<void> _showReportContentSheet({
    required String churchId,
    required String contentType,
    required String contentId,
    required String reportedUserId,
    String? preview,
  }) async {
    String selectedReason = ModerationService.reportReasons.first;
    final descriptionController = TextEditingController();

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Report Content',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(sheetContext, false),
                        ),
                      ],
                    ),
                    if (preview?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 8),
                      Text(
                        preview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: selectedReason,
                      decoration: const InputDecoration(labelText: 'Reason'),
                      items: [
                        for (final reason in ModerationService.reportReasons)
                          DropdownMenuItem(
                            value: reason,
                            child: Text(reason),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setSheetState(() => selectedReason = value);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Additional context',
                        hintText: 'Optional',
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.flag_outlined),
                        label: const Text('Submit Report'),
                        onPressed: () async {
                          await _moderationService.reportContent(
                            churchId: churchId,
                            contentType: contentType,
                            contentId: contentId,
                            reportedUserId: reportedUserId,
                            reason: selectedReason,
                            description: descriptionController.text,
                            metadata: {'preview': preview},
                          );
                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext, true);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    descriptionController.dispose();
    if (!mounted || submitted != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Thank you. This report has been submitted for review.'),
      ),
    );
  }

  Future<void> _confirmBlockUser({
    required String churchId,
    required String userId,
    required String displayName,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Block $displayName?'),
        content: const Text(
          'They will no longer be able to message you or interact with your content. This is private and they will not be notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _moderationService.blockUser(
      churchId: churchId,
      blockedUserId: userId,
      reason: 'Blocked from feed post options',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$displayName has been blocked.')),
    );
    await _loadBlockedUsers();
    setState(() => _feedRefreshToken++);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userProvider = Provider.of<UserRoleProvider>(context);
    final churchId = userProvider.userProfile?.placeId ?? "";
    final feedChurchIds = _feedChurchIds(churchId);

    return AppScaffold(
      title: 'Community Feed',
      leading: IconButton(
        tooltip: 'Search feed',
        icon: const Icon(Icons.search),
        onPressed:
            churchId.isEmpty ? null : () => _showFeedSearchSheet(churchId),
      ),
      actions: [
        Builder(
          builder: (actionContext) => IconButton(
            tooltip: 'Feed settings',
            icon: const Icon(Icons.tune_outlined),
            onPressed: churchId.isEmpty
                ? null
                : () => Scaffold.maybeOf(actionContext)?.openDrawer(),
          ),
        ),
        const InboxIconButton(),
      ],
      drawer:
          churchId.isEmpty ? null : _buildFeedSettingsDrawer(context, churchId),
      showBottomMenu: widget.showBottomMenu,
      appBarHeight: 48,
      appBarTitleStyle: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
      ),
      bodySafeAreaTop: false,
      body: churchId.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                StreamBuilder<List<Post>>(
                  key: ValueKey(
                    'feed-$churchId-$_feedScope-${_selectedFeedChurchIds?.join('|')}-$_feedRefreshToken',
                  ),
                  stream: _communityService.getPostsForChurches(
                    churchId,
                    feedChurchIds,
                    includeShared: _feedScope != 'church',
                  ),
                  builder: (context, snapshot) {
                    final posts = (snapshot.data ?? [])
                        .where(
                          (post) => !_blockedUserIds.contains(post.authorId),
                        )
                        .toList();
                    _queueChurchNameLoads(posts, churchId);
                    final isWaiting =
                        snapshot.connectionState == ConnectionState.waiting;
                    final hasLoadIssue = snapshot.hasError && posts.isEmpty;

                    return NotificationListener<ScrollNotification>(
                      onNotification: _handleFeedScrollNotification,
                      child: RefreshIndicator(
                        onRefresh: () async {
                          await _communityService.cleanupVanishingContent();
                          if (mounted) {
                            setState(() => _feedRefreshToken++);
                          }
                        },
                        child: ListView.builder(
                          key: PageStorageKey<String>(
                            'community-feed-list-$churchId-$_feedScope-${_selectedFeedChurchIds?.join('|') ?? 'own'}',
                          ),
                          controller: _feedScrollController,
                          physics: const ClampingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          padding: EdgeInsets.zero,
                          cacheExtent: 1200,
                          clipBehavior: Clip.hardEdge,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          itemCount: _feedListItemCount(
                            postsLength: posts.length,
                            isWaiting: isWaiting,
                            hasConnectionNotice: snapshot.hasError,
                          ),
                          itemBuilder: (context, index) {
                            return _buildFeedListItem(
                              context,
                              index: index,
                              churchId: churchId,
                              posts: posts,
                              isWaiting: isWaiting,
                              hasConnectionNotice: snapshot.hasError,
                              hasLoadIssue: hasLoadIssue,
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
                _buildFloatingComposeMenu(context),
              ],
            ),
    );
  }

  int _feedListItemCount({
    required int postsLength,
    required bool isWaiting,
    required bool hasConnectionNotice,
  }) {
    const headerCount = 3;
    final noticeCount = hasConnectionNotice ? 1 : 0;
    final contentCount = isWaiting && postsLength == 0
        ? 5
        : postsLength == 0
            ? 1
            : postsLength;
    return headerCount + noticeCount + contentCount;
  }

  Widget _buildFeedListItem(
    BuildContext context, {
    required int index,
    required String churchId,
    required List<Post> posts,
    required bool isWaiting,
    required bool hasConnectionNotice,
    required bool hasLoadIssue,
  }) {
    if (index == 0) return _buildStoriesSection(context, churchId);
    if (index == 1) return _buildFeedScopeSummary(context);
    if (index == 2) return const Divider(height: 1);

    var contentIndex = index - 3;
    if (hasConnectionNotice) {
      if (contentIndex == 0) {
        return _buildFeedConnectionNotice(context, hasLoadIssue);
      }
      contentIndex--;
    }

    if (isWaiting && posts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: AppSkeletonListItem(),
      );
    }

    if (posts.isEmpty) return _buildEmptyFeedState(context);

    final post = posts[contentIndex];
    final isLast = contentIndex == posts.length - 1;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, contentIndex == 0 ? 10 : 0, 12, 0),
      child: Padding(
        padding: EdgeInsets.only(bottom: isLast ? 104 : 0),
        child: _buildPostCard(
          context,
          post,
          viewerChurchId: churchId,
        ),
      ),
    );
  }

  List<String>? _feedChurchIds(String ownChurchId) {
    if (_feedScope == 'all') return null;
    if (_feedScope == 'custom') return _selectedFeedChurchIds;
    return [ownChurchId];
  }

  Widget _buildFeedScopeSummary(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = switch (_feedScope) {
      'all' => 'Showing shared posts from all churches',
      'custom' => _selectedFeedLabel ?? 'Shared posts from selected churches',
      _ => 'Showing your church',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          Icon(
            _feedScope == 'all'
                ? Icons.public_outlined
                : _feedScope == 'custom'
                    ? Icons.filter_alt_outlined
                    : Icons.church_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedSettingsDrawer(BuildContext context, String ownChurchId) {
    final theme = Theme.of(context);

    void applyScope({
      required String scope,
      List<String>? churchIds,
      String? label,
    }) {
      setState(() {
        _feedScope = scope;
        _selectedFeedChurchIds = churchIds;
        _selectedFeedLabel = label;
        _feedRefreshToken++;
      });
      unawaited(_saveFeedScopePreferences());
      Navigator.maybePop(context);
    }

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text(
              'Feed Settings',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            _FeedScopeChip(
              label: 'My Church',
              selected: _feedScope == 'church',
              icon: Icons.church_outlined,
              onSelected: () => applyScope(scope: 'church'),
            ),
            const SizedBox(height: 10),
            _FeedScopeChip(
              label: 'All Churches',
              selected: _feedScope == 'all',
              icon: Icons.public_outlined,
              onSelected: () => applyScope(scope: 'all'),
            ),
            const SizedBox(height: 10),
            _FeedScopeChip(
              label: _feedScope == 'custom'
                  ? (_selectedFeedLabel ?? 'Filtered feed')
                  : 'Filter churches',
              selected: _feedScope == 'custom',
              icon: Icons.filter_alt_outlined,
              onSelected: () {
                Navigator.maybePop(context);
                _showFeedSearchSheet(ownChurchId);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showFeedSearchSheet(String ownChurchId) async {
    final searchController = TextEditingController();
    Timer? searchDebounce;
    var initialLoadStarted = false;
    var searchGeneration = 0;
    var denominations = const <String>[];
    var selectedDenomination = '';
    var churches = const <Church>[];
    var people = const <UserProfile>[];
    var peopleExpanded = false;
    var isLoading = true;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> load({String? query}) async {
              final generation = ++searchGeneration;
              setSheetState(() => isLoading = true);
              final nextDenominations =
                  await _churchService.fetchDenominations();
              final nextChurches = await _churchService.fetchChurches(
                denomination:
                    selectedDenomination.isEmpty ? null : selectedDenomination,
                query: query,
              );
              final nextPeople = query == null || query.trim().length < 2
                  ? const <UserProfile>[]
                  : await _userService.searchPeople(query);
              final mergedChurches = _mergeChurchResults(
                directChurches: nextChurches,
                people: nextPeople,
                query: query,
                selectedDenomination: selectedDenomination,
              );
              if (sheetContext.mounted && generation == searchGeneration) {
                setSheetState(() {
                  denominations = nextDenominations;
                  churches = mergedChurches;
                  people = nextPeople;
                  isLoading = false;
                });
              }
            }

            if (!initialLoadStarted) {
              initialLoadStarted = true;
              unawaited(load());
            }

            Future<void> runSearch() async {
              await load(query: searchController.text);
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.82,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Search Feed',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: searchController,
                      textInputAction: TextInputAction.search,
                      onChanged: (value) {
                        searchDebounce?.cancel();
                        searchDebounce =
                            Timer(const Duration(milliseconds: 280), () {
                          if (sheetContext.mounted) load(query: value);
                        });
                      },
                      onSubmitted: (_) => runSearch(),
                      decoration: InputDecoration(
                        labelText: 'Search churches or people',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          tooltip: 'Search',
                          onPressed: runSearch,
                          icon: const Icon(Icons.arrow_forward),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedDenomination.isEmpty
                          ? null
                          : selectedDenomination,
                      decoration: const InputDecoration(
                        labelText: 'Denomination',
                        prefixIcon: Icon(Icons.account_balance_outlined),
                      ),
                      items: [
                        for (final denomination in denominations)
                          DropdownMenuItem(
                            value: denomination,
                            child: Text(denomination),
                          ),
                      ],
                      onChanged: (value) async {
                        selectedDenomination = value ?? '';
                        await load(query: searchController.text);
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _feedScope = 'church';
                                _selectedFeedChurchIds = null;
                                _selectedFeedLabel = null;
                                _feedRefreshToken++;
                              });
                              unawaited(_saveFeedScopePreferences());
                              Navigator.pop(sheetContext);
                            },
                            icon: const Icon(Icons.church_outlined),
                            label: const Text('My Church'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () {
                              final filteredIds = churches
                                  .map((church) => church.placeId.isNotEmpty
                                      ? church.placeId
                                      : church.id)
                                  .where((id) => id.isNotEmpty)
                                  .toSet()
                                  .toList();
                              if (filteredIds.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Search or select at least one church first.',
                                    ),
                                  ),
                                );
                                return;
                              }
                              final cleanSearch = searchController.text.trim();
                              setState(() {
                                _feedScope = 'custom';
                                _selectedFeedChurchIds = filteredIds;
                                _selectedFeedLabel = filteredIds.length == 1
                                    ? churches.first.name
                                    : selectedDenomination.isNotEmpty
                                        ? selectedDenomination
                                        : cleanSearch.isNotEmpty
                                            ? '$cleanSearch churches'
                                            : 'Filtered churches';
                                _feedRefreshToken++;
                              });
                              unawaited(_saveFeedScopePreferences());
                              Navigator.pop(sheetContext);
                            },
                            icon: const Icon(Icons.filter_alt_outlined),
                            label: const Text('Use Filter'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : ListView(
                              children: [
                                Text(
                                  'Churches',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 8),
                                if (churches.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Text('No churches found.'),
                                  )
                                else
                                  for (final church in churches)
                                    ListTile(
                                      leading:
                                          const Icon(Icons.church_outlined),
                                      title: Text(church.name),
                                      subtitle: Text([
                                        church.denomination,
                                        church.address,
                                      ]
                                          .where((value) =>
                                              value.trim().isNotEmpty)
                                          .join(' - ')),
                                      onTap: () {
                                        final id = church.placeId.isNotEmpty
                                            ? church.placeId
                                            : church.id;
                                        setState(() {
                                          _feedScope = id == ownChurchId
                                              ? 'church'
                                              : 'custom';
                                          _selectedFeedChurchIds = [id];
                                          _selectedFeedLabel = church.name;
                                          _feedRefreshToken++;
                                        });
                                        unawaited(_saveFeedScopePreferences());
                                        Navigator.pop(sheetContext);
                                      },
                                    ),
                                if (people.isNotEmpty) ...[
                                  const Divider(height: 28),
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      'People (${people.length})',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    subtitle: const Text(
                                      'Expand to message or Bible Nudge members.',
                                    ),
                                    trailing: Icon(
                                      peopleExpanded
                                          ? Icons.keyboard_arrow_up
                                          : Icons.keyboard_arrow_down,
                                    ),
                                    onTap: () {
                                      setSheetState(() {
                                        peopleExpanded = !peopleExpanded;
                                      });
                                    },
                                  ),
                                  if (peopleExpanded)
                                    for (final person in people)
                                      ListTile(
                                        leading: CircleAvatar(
                                          backgroundImage:
                                              person.photoUrl.isNotEmpty
                                                  ? NetworkImage(
                                                      person.photoUrl,
                                                    )
                                                  : null,
                                          child: person.photoUrl.isEmpty
                                              ? Text(person.fullName.isEmpty
                                                  ? '?'
                                                  : person.fullName[0])
                                              : null,
                                        ),
                                        title: Text(person.fullName.isEmpty
                                            ? person.email
                                            : person.fullName),
                                        subtitle: Text(person.placeName.isEmpty
                                            ? 'Member'
                                            : person.placeName),
                                        trailing: Wrap(
                                          spacing: 2,
                                          children: [
                                            IconButton(
                                              tooltip: 'Bible Nudge',
                                              icon: const Icon(
                                                Icons.menu_book_outlined,
                                              ),
                                              onPressed: () {
                                                Navigator.pop(sheetContext);
                                                _sendBibleNudge(person);
                                              },
                                            ),
                                            IconButton(
                                              tooltip: 'Message',
                                              icon: const Icon(
                                                Icons.chat_bubble_outline,
                                              ),
                                              onPressed: () {
                                                Navigator.pop(sheetContext);
                                                _openMessageWithUserProfile(
                                                  person,
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                        onTap: () {
                                          Navigator.pop(sheetContext);
                                          _openMessageWithUserProfile(person);
                                        },
                                      ),
                                ],
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    searchDebounce?.cancel();
    searchController.dispose();
  }

  List<Church> _mergeChurchResults({
    required List<Church> directChurches,
    required List<UserProfile> people,
    required String? query,
    required String selectedDenomination,
  }) {
    final byKey = <String, Church>{};

    void addChurch(Church church) {
      final id = church.placeId.trim().isNotEmpty
          ? church.placeId.trim()
          : church.id.trim();
      final name = church.name.trim();
      if (id.isEmpty && name.isEmpty) return;
      final key = id.isNotEmpty ? id : name.toLowerCase();
      byKey.putIfAbsent(key, () => church);
    }

    for (final church in directChurches) {
      addChurch(church);
    }

    final cleanQuery = query?.trim().toLowerCase() ?? '';
    final canDeriveFromPeople =
        cleanQuery.length >= 2 && selectedDenomination.trim().isEmpty;

    if (canDeriveFromPeople) {
      for (final person in people) {
        final placeId = person.placeId.trim();
        final placeName = person.placeName.trim();
        if (placeId.isEmpty || placeName.isEmpty) continue;
        if (!placeName.toLowerCase().contains(cleanQuery)) continue;

        addChurch(
          Church(
            id: placeId,
            placeId: placeId,
            name: placeName,
            address: '',
            denomination: '',
            ownerUserId: '',
            timezone: 'UTC',
            status: 'active',
            createdAt: DateTime.now(),
          ),
        );
      }
    }

    final results = byKey.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return results;
  }

  Future<void> _sendBibleNudge(UserProfile recipient) async {
    final sender = context.read<UserRoleProvider>().userProfile;
    if (sender == null) return;

    final displayName =
        recipient.fullName.isNotEmpty ? recipient.fullName : recipient.email;
    final messageController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('Bible Nudge $displayName'),
          content: TextField(
            controller: messageController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Optional note',
              hintText: 'Want to study a passage together?',
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
        'Bible Nudge sent to $displayName.',
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

  Future<void> _openMessageWithUserProfile(UserProfile otherUser) async {
    final currentUser = context.read<UserRoleProvider>().userProfile;
    final currentAuthUser = _auth.currentUser;
    if (currentUser == null || currentAuthUser == null) return;
    if (otherUser.uid == currentAuthUser.id) {
      Navigator.pushNamed(context, '/profile');
      return;
    }

    try {
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
      if (_shouldOfferBibleNudgeForProfile(otherUser, currentUser, error)) {
        await _showBibleNudgeRequiredPrompt(otherUser);
        return;
      }
      AppFeedback.show(
        context,
        _messageAccessHelpForProfile(otherUser, currentUser, error),
        type: AppFeedbackType.warning,
      );
    }
  }

  String _messageAccessHelpForProfile(
    UserProfile otherUser,
    UserProfile currentUser,
    Object error,
  ) {
    final isOtherChurch = otherUser.churchId.trim().isNotEmpty &&
        otherUser.churchId != currentUser.churchId;
    final isAccessIssue = _isBibleNudgeAccessIssue(error);

    if (isOtherChurch && isAccessIssue) {
      return 'This person is outside your church. Send a Bible Nudge first. Once both people accept, you can view their profile and message each other anytime.';
    }

    return 'Could not open message: $error';
  }

  Widget _buildFloatingComposeMenu(BuildContext context) {
    final theme = Theme.of(context);
    final isVisible = _showFloatingCompose || _composeActionsOpen;

    return Positioned(
      right: 18,
      bottom: 18,
      child: IgnorePointer(
        ignoring: !isVisible,
        child: AnimatedOpacity(
          opacity: isVisible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: !_composeActionsOpen
                    ? const SizedBox.shrink()
                    : DecoratedBox(
                        key: const ValueKey('compose-actions'),
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.surface.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 22,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _ComposeActionButton(
                                label: 'Status',
                                icon: Icons.auto_awesome_outlined,
                                onPressed: () {
                                  setState(() => _composeActionsOpen = false);
                                  _showCreateStorySheet();
                                },
                              ),
                              _ComposeActionButton(
                                label: 'Video',
                                icon: Icons.videocam_outlined,
                                onPressed: () async {
                                  setState(() => _composeActionsOpen = false);
                                  await _pickVideo();
                                  if (mounted) _showPostComposerSheet();
                                },
                              ),
                              _ComposeActionButton(
                                label: 'Photo',
                                icon: Icons.image_outlined,
                                onPressed: () async {
                                  setState(() => _composeActionsOpen = false);
                                  await _pickImage();
                                  if (mounted) _showPostComposerSheet();
                                },
                              ),
                              _ComposeActionButton(
                                label: 'Post',
                                icon: Icons.edit_outlined,
                                onPressed: () {
                                  setState(() => _composeActionsOpen = false);
                                  _showPostComposerSheet();
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              FloatingActionButton(
                tooltip: _composeActionsOpen ? 'Close composer' : 'Create',
                onPressed: () => setState(
                  () => _composeActionsOpen = !_composeActionsOpen,
                ),
                child: Icon(_composeActionsOpen ? Icons.close : Icons.add),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPostComposerSheet() async {
    setState(() => _postVisibleToAllChurches = false);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Create Post',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _buildComposer(
                      context,
                      onMediaChanged: () => setSheetState(() {}),
                      onPosted: () {
                        if (sheetContext.mounted) {
                          Navigator.pop(sheetContext);
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFeedConnectionNotice(BuildContext context, bool isBlocking) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.18),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                isBlocking ? Icons.cloud_off_outlined : Icons.sync_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isBlocking
                      ? 'Feed is reconnecting. Pull back here in a moment.'
                      : 'Showing latest saved feed while live updates reconnect.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              IconButton(
                tooltip: 'Retry',
                onPressed: () => setState(() => _feedRefreshToken++),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyFeedState(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 260,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.forum_outlined,
              size: 48,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 12),
            Text(
              'No posts yet. Be the first!',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  void _queueChurchNameLoads(List<Post> posts, String ownChurchId) {
    for (final post in posts) {
      final postChurchId = post.placeId.trim();
      if (postChurchId.isEmpty ||
          postChurchId == ownChurchId ||
          _churchNamesById.containsKey(postChurchId) ||
          _loadingChurchNameIds.contains(postChurchId)) {
        continue;
      }

      _loadingChurchNameIds.add(postChurchId);
      unawaited(() async {
        final church = await _churchService.getChurch(postChurchId);
        if (!mounted) return;
        setState(() {
          _churchNamesById[postChurchId] =
              church?.name.trim().isNotEmpty == true
                  ? church!.name.trim()
                  : _prettifyChurchIdentifier(postChurchId);
          _loadingChurchNameIds.remove(postChurchId);
        });
      }());
    }
  }

  String _compactChurchLabel(String churchName) {
    final clean = _prettifyChurchIdentifier(churchName);
    if (clean.length <= 24) return clean;
    final words = clean
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]+'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) =>
            word.length > 2 &&
            !{'the', 'and', 'of', 'for', 'church'}.contains(
              word.toLowerCase(),
            ))
        .toList();
    final acronym = words.take(5).map((word) => word[0].toUpperCase()).join();
    return acronym.length >= 2 ? acronym : clean.substring(0, 24);
  }

  String _prettifyChurchIdentifier(String value) {
    var clean = value.trim();
    if (clean.isEmpty) return 'Church';
    clean = clean.replaceFirst(RegExp(r'^(local|manual)_'), '');
    clean = clean.replaceAll(RegExp(r'[_-]+'), ' ');
    clean = clean.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (clean.startsWith('church ') || clean.length > 48) return 'Other Church';

    final uppercaseWords = {'ntcog', 'cog', 'cogop', 'ja', 'jm'};
    return clean.split(' ').map((word) {
      final lower = word.toLowerCase();
      if (uppercaseWords.contains(lower)) return lower.toUpperCase();
      if (word.length <= 2) return lower;
      return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
    }).join(' ');
  }

  List<String> _effectivePostLikes(Post post) {
    return _postLikeOverrides[post.id] ?? post.likes;
  }

  Future<void> _togglePostLike(Post post) async {
    final uid = _auth.currentUser?.id ?? '';
    if (uid.isEmpty) return;

    final originalLikes = _effectivePostLikes(post);
    final nextLikes = [...originalLikes];
    if (nextLikes.contains(uid)) {
      nextLikes.remove(uid);
    } else {
      nextLikes.add(uid);
    }

    setState(() => _postLikeOverrides[post.id] = nextLikes);

    try {
      final updatedPost = await _communityService.toggleLike(post.id, uid);
      if (!mounted) return;
      if (updatedPost != null) {
        setState(() => _postLikeOverrides[post.id] = updatedPost.likes);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _postLikeOverrides[post.id] = originalLikes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save like: $error')),
      );
    }
  }

  Widget _buildPostCard(
    BuildContext context,
    Post post, {
    required String viewerChurchId,
  }) {
    final likes = _effectivePostLikes(post);
    final isLiked = likes.contains(_auth.currentUser?.id);
    final canDelete = _canDeletePost(post);
    final isOtherChurch =
        post.placeId.trim().isNotEmpty && post.placeId != viewerChurchId;
    final churchName = _churchNamesById[post.placeId] ??
        _prettifyChurchIdentifier(post.placeId);
    final churchLabel = _compactChurchLabel(churchName);

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _messagePostAuthor(post),
                  child: CircleAvatar(
                    backgroundImage: post.authorPhoto != null
                        ? NetworkImage(post.authorPhoto!)
                        : null,
                    child: post.authorPhoto == null
                        ? const Icon(Icons.person)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _messagePostAuthor(post),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                post.authorName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (isOtherChurch)
                                Tooltip(
                                  message: churchName,
                                  child: Container(
                                    constraints:
                                        const BoxConstraints(maxWidth: 132),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .outlineVariant,
                                      ),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.55),
                                    ),
                                    child: Text(
                                      churchLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            timeago.format(post.timestamp),
                            style: TextStyle(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (post.authorId != _auth.currentUser?.id)
                  IconButton(
                    tooltip: 'Message',
                    icon: const Icon(Icons.chat_bubble_outline, size: 20),
                    onPressed: () => _messagePostAuthor(post),
                  ),
                PopupMenuButton<String>(
                  tooltip: 'Post options',
                  icon: const Icon(Icons.more_horiz),
                  onSelected: (value) {
                    if (value == 'delete') _confirmDeletePost(post);
                    if (value == 'report') {
                      _showReportContentSheet(
                        churchId: post.placeId,
                        contentType: 'feed_post',
                        contentId: post.id,
                        reportedUserId: post.authorId,
                        preview: post.content,
                      );
                    }
                    if (value == 'block') {
                      _confirmBlockUser(
                        churchId: post.placeId,
                        userId: post.authorId,
                        displayName: post.authorName,
                      );
                    }
                  },
                  itemBuilder: (context) => [
                    if (canDelete)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    if (!canDelete) ...[
                      const PopupMenuItem(
                        value: 'report',
                        child: Row(
                          children: [
                            Icon(Icons.flag_outlined),
                            SizedBox(width: 8),
                            Text('Report'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'block',
                        child: Row(
                          children: [
                            Icon(Icons.block, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Block user'),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (post.content.isNotEmpty) Text(post.content),
            if (_showMediaPreviews &&
                post.mediaUrl != null &&
                post.mediaType == 'image') ...[
              const SizedBox(height: 12),
              AspectRatio(
                aspectRatio: 4 / 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: post.mediaUrl!,
                    placeholder: (context, url) => const AppSkeletonListItem(),
                    errorWidget: (context, url, error) =>
                        const Center(child: Icon(Icons.error)),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
            if (_showMediaPreviews &&
                post.mediaUrl != null &&
                post.mediaType == 'video') ...[
              const SizedBox(height: 12),
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.play_circle_fill,
                          color: Colors.white, size: 48),
                      SizedBox(height: 8),
                      Text('Video Attached',
                          style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              )
            ],
            if (!_showMediaPreviews && post.mediaUrl != null) ...[
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Media preview hidden'),
                subtitle: const Text('Enable previews in Community Settings.'),
                dense: true,
              ),
            ],
            const SizedBox(height: 12),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                TextButton.icon(
                  icon: Icon(
                    isLiked ? Icons.favorite : Icons.favorite_border,
                    color: isLiked ? Colors.red : Colors.grey,
                    size: 20,
                  ),
                  label: Text(
                    '${likes.length}',
                    style: TextStyle(color: isLiked ? Colors.red : Colors.grey),
                  ),
                  onPressed: () => _togglePostLike(post),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.comment_outlined,
                      size: 20, color: Colors.grey),
                  label: Text(
                    '${post.commentsCount}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => PostDetailScreen(post: post)),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStoriesSection(BuildContext context, String churchId) {
    final theme = Theme.of(context);
    final currentUser = context.watch<UserRoleProvider>().userProfile;
    final currentUid = _auth.currentUser?.id;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      color: theme.colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Text(
                  'Statuses',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(58, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _showCreateStorySheet,
                  icon: const Icon(Icons.add_circle_outline, size: 17),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 82,
            child: churchId.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<List<CommunityStory>>(
                    key: ValueKey('statuses-$churchId-$_storiesRefreshToken'),
                    stream: _communityService.getActiveStories(
                      churchId,
                      churchIds: _feedChurchIds(churchId),
                      includeShared: _feedScope != 'church',
                    ),
                    builder: (context, snapshot) {
                      final stories = (snapshot.data ?? [])
                          .where((story) =>
                              !_blockedUserIds.contains(story.authorId))
                          .toList();
                      final groups = _buildStoryGroups(stories);
                      _StoryGroup? ownGroup;
                      if (currentUid != null) {
                        for (final group in groups) {
                          if (group.authorId == currentUid) {
                            ownGroup = group;
                            break;
                          }
                        }
                      }
                      final otherGroups = groups
                          .where((group) => group.authorId != currentUid)
                          .toList();

                      return ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: otherGroups.length + 1,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            final currentUserGroup = ownGroup;
                            final thumbnail = ownGroup?.thumbnailFor(
                              _watchedStoryIds,
                            );
                            return _StoryBubble(
                              label: 'Your Story',
                              photoUrl: thumbnail?.authorPhoto ??
                                  currentUser?.photoUrl,
                              thumbnailUrl: thumbnail?.mediaType == 'image'
                                  ? thumbnail?.mediaUrl
                                  : null,
                              hasUnwatched: ownGroup?.hasUnwatched(
                                    _watchedStoryIds,
                                  ) ??
                                  false,
                              isAddButton: true,
                              statusCount: ownGroup?.stories.length ?? 0,
                              onTap: currentUserGroup == null
                                  ? _showCreateStorySheet
                                  : () => _openStoryViewer(currentUserGroup),
                            );
                          }

                          final group = otherGroups[index - 1];
                          final thumbnail = group.thumbnailFor(
                            _watchedStoryIds,
                          );
                          return _StoryBubble(
                            label: _shortStoryName(group.authorName),
                            thumbnailUrl: thumbnail.mediaType == 'image'
                                ? thumbnail.mediaUrl
                                : group.authorPhoto,
                            photoUrl: group.authorPhoto,
                            hasUnwatched: group.hasUnwatched(_watchedStoryIds),
                            statusCount: group.stories.length,
                            onTap: () => _openStoryViewer(group),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _shortStoryName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Member';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  List<_StoryGroup> _buildStoryGroups(List<CommunityStory> stories) {
    final activeStories = stories.where((story) => !story.isExpired).toList();
    final validStoryIds = activeStories.map((story) => story.id).toSet();
    if (validStoryIds.isNotEmpty &&
        _watchedStoryIds.any((id) => !validStoryIds.contains(id))) {
      final nextWatched =
          _watchedStoryIds.where((id) => validStoryIds.contains(id)).toSet();
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final uid = _auth.currentUser?.id ?? 'guest';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(
            'watched_status_ids_$uid', nextWatched.toList());
        if (mounted) setState(() => _watchedStoryIds = nextWatched);
      });
    }

    final groupsByAuthor = <String, List<CommunityStory>>{};
    for (final story in activeStories) {
      groupsByAuthor.putIfAbsent(story.authorId, () => []).add(story);
    }

    final groups = groupsByAuthor.entries.map((entry) {
      final groupedStories = entry.value
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return _StoryGroup(
        authorId: entry.key,
        authorName: groupedStories.first.authorName,
        authorPhoto: groupedStories.first.authorPhoto,
        stories: groupedStories,
      );
    }).toList();

    groups.sort((a, b) {
      final aUnwatched = a.hasUnwatched(_watchedStoryIds);
      final bUnwatched = b.hasUnwatched(_watchedStoryIds);
      if (aUnwatched != bUnwatched) return aUnwatched ? -1 : 1;
      return b.latestCreatedAt.compareTo(a.latestCreatedAt);
    });

    return groups;
  }

  Widget _buildComposer(
    BuildContext context, {
    VoidCallback? onMediaChanged,
    VoidCallback? onPosted,
  }) {
    final theme = Theme.of(context);
    final profile = context.watch<UserRoleProvider>().userProfile;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          if (_selectedMedia != null) ...[
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                height: 88,
                width: 88,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          image: _mediaType == 'image' &&
                                  _selectedImagePreviewBytes != null
                              ? DecorationImage(
                                  image:
                                      MemoryImage(_selectedImagePreviewBytes!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _mediaType == 'video'
                            ? const Center(
                                child: Icon(Icons.play_circle_fill, size: 34),
                              )
                            : null,
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton.filled(
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            setState(() {
                              _selectedMedia = null;
                              _selectedImagePreviewBytes = null;
                              _mediaType = null;
                            });
                            onMediaChanged?.call();
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: profile?.photoUrl.isNotEmpty == true
                    ? NetworkImage(profile!.photoUrl)
                    : null,
                child: profile?.photoUrl.isNotEmpty == true
                    ? null
                    : Icon(Icons.person, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _postController,
                  minLines: 1,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: _postVisibleToAllChurches
                        ? 'Share with all churches...'
                        : 'Share with your church...',
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.image_outlined),
                onPressed: () async {
                  await _pickImage();
                  onMediaChanged?.call();
                },
                tooltip: 'Attach image',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                icon: const Icon(Icons.videocam_outlined),
                onPressed: () async {
                  await _pickVideo();
                  onMediaChanged?.call();
                },
                tooltip: 'Attach video',
                visualDensity: VisualDensity.compact,
              ),
              SizedBox(
                width: 42,
                height: 42,
                child: IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: theme.colorScheme.onPrimary,
                    disabledBackgroundColor:
                        theme.colorScheme.surfaceContainerHighest,
                    disabledForegroundColor:
                        theme.colorScheme.onSurface.withValues(alpha: 0.38),
                  ),
                  tooltip: 'Post',
                  onPressed: _isPosting
                      ? null
                      : () async {
                          final posted = await _handlePost();
                          if (posted) onPosted?.call();
                        },
                  icon: _isPosting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _AudienceSelector(
            visibleToAllChurches: _postVisibleToAllChurches,
            onChanged: (value) {
              setState(() => _postVisibleToAllChurches = value);
              onMediaChanged?.call();
            },
          ),
        ],
      ),
    );
  }

  void _openStoryViewer(_StoryGroup group) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => _StatusViewerDialog(
        group: group,
        currentUserId: _auth.currentUser?.id ?? '',
        initialIndex: group.firstUnwatchedIndex(_watchedStoryIds),
        onViewed: _markStoryWatched,
        onToggleLike: _toggleStoryLike,
        onReply: _replyToStory,
      ),
    );
  }

  Future<CommunityStory?> _toggleStoryLike(CommunityStory story) async {
    try {
      final updated = await _communityService.toggleStoryLike(story.id);
      if (mounted) setState(() => _storiesRefreshToken++);
      return updated;
    } catch (error) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not like status: $error')),
      );
      return null;
    }
  }

  Future<void> _replyToStory(CommunityStory story, String text) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    final currentUser = context.read<UserRoleProvider>().userProfile;
    final currentAuthUser = _auth.currentUser;
    if (currentUser == null || currentAuthUser == null) return;

    if (story.authorId == currentAuthUser.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot reply to your own status.')),
      );
      return;
    }

    try {
      final conversation =
          await _messageService.getOrCreateConversationWithUserId(
        currentUser: currentUser,
        otherUserId: story.authorId,
      );
      final caption = story.caption?.trim();
      final statusLine = caption == null || caption.isEmpty
          ? 'your status'
          : 'your status: "$caption"';
      await _messageService.sendMessage(
        conversationId: conversation.id,
        text: 'Replied to $statusLine\n\n$cleanText',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Status reply sent securely.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send status reply: $error')),
      );
    }
  }
}

class _StoryGroup {
  const _StoryGroup({
    required this.authorId,
    required this.authorName,
    this.authorPhoto,
    required this.stories,
  });

  final String authorId;
  final String authorName;
  final String? authorPhoto;
  final List<CommunityStory> stories;

  DateTime get latestCreatedAt => stories.last.createdAt;

  bool hasUnwatched(Set<String> watchedStoryIds) {
    return stories.any((story) => !watchedStoryIds.contains(story.id));
  }

  int firstUnwatchedIndex(Set<String> watchedStoryIds) {
    final index = stories.indexWhere(
      (story) => !watchedStoryIds.contains(story.id),
    );
    return index < 0 ? 0 : index;
  }

  CommunityStory thumbnailFor(Set<String> watchedStoryIds) {
    final firstUnwatched = stories.where(
      (story) => !watchedStoryIds.contains(story.id),
    );
    return firstUnwatched.isEmpty ? stories.last : firstUnwatched.first;
  }
}

class _StatusViewerDialog extends StatefulWidget {
  const _StatusViewerDialog({
    required this.group,
    required this.currentUserId,
    required this.initialIndex,
    required this.onViewed,
    required this.onToggleLike,
    required this.onReply,
  });

  final _StoryGroup group;
  final String currentUserId;
  final int initialIndex;
  final Future<void> Function(CommunityStory story) onViewed;
  final Future<CommunityStory?> Function(CommunityStory story) onToggleLike;
  final Future<void> Function(CommunityStory story, String text) onReply;

  @override
  State<_StatusViewerDialog> createState() => _StatusViewerDialogState();
}

class _StatusViewerDialogState extends State<_StatusViewerDialog> {
  late final PageController _pageController;
  late final TextEditingController _replyController;
  late List<CommunityStory> _stories;
  late int _index;
  bool _isReplying = false;

  CommunityStory get _currentStory => _stories[_index];

  @override
  void initState() {
    super.initState();
    _stories = [...widget.group.stories];
    _index = widget.initialIndex.clamp(0, _stories.length - 1);
    _pageController = PageController(initialPage: _index);
    _replyController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _markCurrentViewed());
  }

  @override
  void dispose() {
    _pageController.dispose();
    _replyController.dispose();
    super.dispose();
  }

  void _markCurrentViewed() {
    if (!mounted || _stories.isEmpty) return;
    widget.onViewed(_currentStory);
  }

  void _goTo(int nextIndex) {
    if (nextIndex < 0) return;
    if (nextIndex >= _stories.length) {
      Navigator.pop(context);
      return;
    }

    _pageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _handleSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -120) {
      _goTo(_index + 1);
    } else if (velocity > 120) {
      _goTo(_index - 1);
    }
  }

  Future<void> _toggleLike() async {
    final uid = widget.currentUserId;
    if (uid.isEmpty) return;

    final story = _currentStory;
    final likes = [...story.likes];
    final isLiked = likes.contains(uid);
    if (isLiked) {
      likes.remove(uid);
    } else {
      likes.add(uid);
    }

    setState(() {
      _stories[_index] = story.copyWith(likes: likes);
    });

    final updated = await widget.onToggleLike(story);
    if (!mounted || updated == null) return;
    setState(() {
      _stories[_index] = updated;
    });
  }

  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _isReplying) return;

    setState(() => _isReplying = true);
    try {
      await widget.onReply(_currentStory, text);
      _replyController.clear();
    } finally {
      if (mounted) setState(() => _isReplying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canReply = _currentStory.authorId != widget.currentUserId;

    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: _stories.length,
              onPageChanged: (index) {
                setState(() => _index = index);
                _markCurrentViewed();
              },
              itemBuilder: (context, index) => _buildStatusContent(
                context,
                _stories[index],
              ),
            ),
            Positioned.fill(
              top: 92,
              bottom: canReply ? 96 : 56,
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _goTo(_index - 1),
                      onHorizontalDragEnd: _handleSwipe,
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _goTo(_index + 1),
                      onHorizontalDragEnd: _handleSwipe,
                    ),
                  ),
                ],
              ),
            ),
            _buildTopChrome(context),
            _buildBottomControls(context, canReply),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusContent(BuildContext context, CommunityStory story) {
    final hasImage = story.mediaUrl != null && story.mediaType == 'image';
    final caption = story.caption?.trim();

    if (hasImage) {
      return Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: story.mediaUrl!,
            fit: BoxFit.cover,
            placeholder: (context, url) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            errorWidget: (context, url, error) =>
                const Icon(Icons.error, color: Colors.white),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black54,
                  Colors.transparent,
                  Colors.black54,
                ],
                stops: [0, 0.35, 1],
              ),
            ),
          ),
          if (caption?.isNotEmpty == true)
            Positioned(
              left: 20,
              right: 20,
              bottom: 104,
              child: Text(
                caption!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10141C), Color(0xFF23324D)],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            caption?.isNotEmpty == true ? caption! : 'Status update',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopChrome(BuildContext context) {
    final story = _currentStory;

    return Positioned(
      left: 10,
      right: 10,
      top: 8,
      child: Column(
        children: [
          Row(
            children: [
              for (var index = 0; index < _stories.length; index++)
                Expanded(
                  child: Container(
                    height: 3,
                    margin: EdgeInsets.only(
                      right: index == _stories.length - 1 ? 0 : 4,
                    ),
                    decoration: BoxDecoration(
                      color: index <= _index ? Colors.white : Colors.white38,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 19,
                backgroundImage: widget.group.authorPhoto?.isNotEmpty == true
                    ? NetworkImage(widget.group.authorPhoto!)
                    : null,
                child: widget.group.authorPhoto?.isNotEmpty == true
                    ? null
                    : Text(_initialFor(widget.group.authorName)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.group.authorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      timeago.format(story.createdAt),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls(BuildContext context, bool canReply) {
    final story = _currentStory;
    final isLiked = story.likes.contains(widget.currentUserId);

    return Positioned(
      left: 12,
      right: 12,
      bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      child: Row(
        children: [
          IconButton(
            tooltip: isLiked ? 'Unlike status' : 'Like status',
            style: IconButton.styleFrom(
              backgroundColor: Colors.black54,
              foregroundColor: isLiked ? Colors.redAccent : Colors.white,
            ),
            onPressed: _toggleLike,
            icon: Icon(isLiked ? Icons.favorite : Icons.favorite_border),
          ),
          if (story.likes.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              '${story.likes.length}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (canReply) ...[
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _replyController,
                minLines: 1,
                maxLines: 2,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Reply securely...',
                  hintStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.black54,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF8CCBFF),
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.white24,
                disabledForegroundColor: Colors.white54,
              ),
              tooltip: 'Send reply',
              onPressed: _isReplying ? null : _sendReply,
              icon: _isReplying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
            ),
          ],
        ],
      ),
    );
  }

  String _initialFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }
}

class _AudienceSelector extends StatelessWidget {
  const _AudienceSelector({
    required this.visibleToAllChurches,
    required this.onChanged,
  });

  final bool visibleToAllChurches;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.18),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Icon(
              visibleToAllChurches
                  ? Icons.public_outlined
                  : Icons.church_outlined,
              color: theme.colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                visibleToAllChurches
                    ? 'Audience: all churches'
                    : 'Audience: my church',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Switch.adaptive(
              value: visibleToAllChurches,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedScopeChip extends StatelessWidget {
  const _FeedScopeChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      avatar: icon == null ? null : Icon(icon, size: 16),
      label: Text(label),
      onSelected: (_) => onSelected(),
    );
  }
}

class _ComposeActionButton extends StatelessWidget {
  const _ComposeActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.onSurface,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        minimumSize: const Size(132, 40),
        alignment: Alignment.centerRight,
      ),
      onPressed: onPressed,
      icon: Icon(icon, color: theme.colorScheme.primary),
      label: Text(label),
    );
  }
}

class _StoryBubble extends StatelessWidget {
  const _StoryBubble({
    required this.label,
    required this.onTap,
    this.photoUrl,
    this.thumbnailUrl,
    this.hasUnwatched = false,
    this.isAddButton = false,
    this.statusCount = 0,
  });

  final String label;
  final String? photoUrl;
  final String? thumbnailUrl;
  final bool hasUnwatched;
  final bool isAddButton;
  final int statusCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayUrl = thumbnailUrl?.isNotEmpty == true
        ? thumbnailUrl
        : photoUrl?.isNotEmpty == true
            ? photoUrl
            : null;

    return SizedBox(
      width: 62,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: hasUnwatched
                    ? const LinearGradient(
                        colors: [
                          Color(0xFFEF476F),
                          Color(0xFFFFD166),
                          Color(0xFF118AB2),
                        ],
                      )
                    : null,
                color: hasUnwatched
                    ? null
                    : theme.colorScheme.surfaceContainerHighest,
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 23,
                    backgroundColor: theme.colorScheme.surface,
                    backgroundImage: displayUrl != null
                        ? CachedNetworkImageProvider(displayUrl)
                        : null,
                    child: displayUrl != null
                        ? null
                        : Icon(
                            isAddButton ? Icons.person_outline : Icons.person,
                            color: theme.colorScheme.primary,
                          ),
                  ),
                  if (isAddButton)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 2,
                          ),
                        ),
                        child: Icon(
                          Icons.add,
                          size: 15,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  if (statusCount > 1)
                    Positioned(
                      left: -2,
                      top: -2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.surface,
                            width: 1.5,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: Text(
                            '$statusCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
