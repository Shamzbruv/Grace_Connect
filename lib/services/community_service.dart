import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/community_feed_mode.dart';
import '../models/community_story.dart';
import '../models/post.dart';
import 'social_profile_service.dart';

class CommunityService {
  final _supabase = Supabase.instance.client;
  final String _postsTable = 'community_posts';
  final String _commentsTable = 'community_comments';
  final String _storiesTable = 'community_stories';
  final String _bucketName = 'community_media';
  static const Duration _realtimeQuietTimeout = Duration(seconds: 18);

  Future<void> cleanupExpiredStories() async {
    try {
      await _supabase.rpc('cleanup_expired_community_stories');
    } catch (error) {
      debugPrint('Story cleanup skipped: $error');
    }
  }

  Future<void> cleanupVanishingContent() async {
    try {
      await _supabase.rpc('cleanup_vanishing_content');
    } catch (error) {
      debugPrint('Vanishing content cleanup skipped: $error');
    }
  }

  Future<List<CommunityStory>> fetchActiveStories(
    String churchId, {
    List<String>? churchIds,
    bool includeShared = false,
  }) async {
    final data = await _supabase
        .from(_storiesTable)
        .select()
        .order('created_at', ascending: false)
        .limit(100);

    return _normalizeStories(
      data,
      viewerChurchId: churchId,
      churchIds: churchIds,
      includeShared: includeShared,
    );
  }

  Stream<List<CommunityStory>> getActiveStories(
    String churchId, {
    List<String>? churchIds,
    bool includeShared = false,
  }) async* {
    var lastKnown = <CommunityStory>[];

    try {
      lastKnown = await fetchActiveStories(
        churchId,
        churchIds: churchIds,
        includeShared: includeShared,
      );
      yield lastKnown;
    } catch (error) {
      debugPrint('Could not load statuses before realtime: $error');
    }

    try {
      await for (final stories in _activeStoriesRealtime(
        churchId,
        churchIds: churchIds,
        includeShared: includeShared,
      ).timeout(
        _realtimeQuietTimeout,
        onTimeout: (sink) {
          sink.add(lastKnown);
        },
      )) {
        lastKnown = stories;
        yield stories;
      }
    } catch (error) {
      debugPrint(
          'Status realtime unavailable, keeping last known data: $error');
      if (lastKnown.isNotEmpty) {
        yield lastKnown;
      }
    }
  }

  Stream<List<CommunityStory>> _activeStoriesRealtime(
    String churchId, {
    List<String>? churchIds,
    required bool includeShared,
  }) {
    return _supabase
        .from(_storiesTable)
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .map(
          (rows) => _normalizeStories(
            rows,
            viewerChurchId: churchId,
            churchIds: churchIds,
            includeShared: includeShared,
          ),
        );
  }

  Future<void> addStory(CommunityStory story) async {
    final data = story.toMap();
    try {
      await _supabase.from(_storiesTable).insert(data);
    } on PostgrestException catch (error) {
      if (!_isMissingMediaDisplayColumn(error)) rethrow;
      final fallbackData = Map<String, dynamic>.from(data)
        ..remove('media_fit')
        ..remove('media_aspect_ratio');
      await _supabase.from(_storiesTable).insert(fallbackData);
    }
  }

  Future<CommunityStory?> toggleStoryLike(String storyId) async {
    if (storyId.isEmpty) return null;

    final data = await _supabase.rpc(
      'toggle_community_story_like',
      params: {'target_story_id': storyId},
    );

    if (data is Map<String, dynamic>) {
      return CommunityStory.fromMap(data);
    }
    if (data is Map) {
      return CommunityStory.fromMap(Map<String, dynamic>.from(data));
    }
    return null;
  }

  Future<void> deleteStory(CommunityStory story) async {
    if (story.id.isEmpty) return;

    await _supabase.from(_storiesTable).delete().eq('id', story.id);

    final mediaPath =
        story.mediaPath ?? _storagePathFromPublicUrl(story.mediaUrl);
    if (mediaPath != null) {
      try {
        await _supabase.storage.from(_bucketName).remove([mediaPath]);
      } catch (error) {
        debugPrint('Status deleted, but media cleanup failed: $error');
      }
    }
  }

  Future<List<Post>> fetchPosts(String churchId) async {
    late final List<dynamic> data;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      data = await _supabase
          .from(_postsTable)
          .select()
          .eq('place_id', churchId)
          .or('expires_at.is.null,expires_at.gt.$now')
          .order('created_at', ascending: false)
          .limit(50);
    } catch (_) {
      data = await _supabase
          .from(_postsTable)
          .select()
          .eq('place_id', churchId)
          .order('created_at', ascending: false)
          .limit(50);
    }

    return _normalizePosts(data);
  }

  Future<List<Post>> fetchPostsForChurches(
    String viewerChurchId,
    List<String>? churchIds, {
    bool includeShared = false,
  }) async {
    final queryChurchIds = churchIds
        ?.where((churchId) => churchId.trim().isNotEmpty)
        .map((churchId) => churchId.trim())
        .toSet()
        .toList();

    late final List<dynamic> data;
    final now = DateTime.now().toUtc().toIso8601String();
    try {
      var query = _supabase
          .from(_postsTable)
          .select()
          .or('expires_at.is.null,expires_at.gt.$now');
      if (queryChurchIds != null && queryChurchIds.isNotEmpty) {
        query = query.inFilter('place_id', queryChurchIds);
      }
      data = await query.order('created_at', ascending: false).limit(75);
    } catch (_) {
      var query = _supabase.from(_postsTable).select();
      if (queryChurchIds != null && queryChurchIds.isNotEmpty) {
        query = query.inFilter('place_id', queryChurchIds);
      }
      data = await query.order('created_at', ascending: false).limit(75);
    }

    return _normalizePosts(
      data,
      viewerChurchId: viewerChurchId,
      churchIds: queryChurchIds,
      includeShared: includeShared,
    );
  }

  Future<List<Post>> fetchCommunityFeed({
    required CommunityFeedMode mode,
    String? viewerChurchId,
    String? circleId,
    int limit = 75,
  }) async {
    if (mode == CommunityFeedMode.church &&
        viewerChurchId?.trim().isNotEmpty == true) {
      return fetchPostsForChurches(
        viewerChurchId!.trim(),
        [viewerChurchId.trim()],
      );
    }

    try {
      final rows = await _supabase.rpc(
        'get_community_feed',
        params: {
          'feed_mode': mode.storageValue,
          'viewer_church_id': viewerChurchId?.trim().isEmpty == true
              ? null
              : viewerChurchId?.trim(),
          'target_circle_id':
              circleId?.trim().isEmpty == true ? null : circleId?.trim(),
          'result_limit': limit,
        },
      );
      if (rows is List) {
        final normalized = _normalizePosts(
          rows,
          viewerChurchId: viewerChurchId,
          includeShared: true,
        );
        if (mode == CommunityFeedMode.following) {
          final followingUserIds = await _acceptedFollowingIds();
          final followingCircleIds = await _activeCircleIds();
          return normalized
              .where((post) => _matchesFeedMode(
                    post,
                    mode,
                    circleId,
                    followingUserIds: followingUserIds,
                    followingCircleIds: followingCircleIds,
                  ))
              .take(limit)
              .toList();
        }
        return normalized.take(limit).toList();
      }
    } catch (error) {
      debugPrint('Community feed RPC unavailable, using fallback: $error');
    }

    return _fetchCommunityFeedFallback(
      mode: mode,
      viewerChurchId: viewerChurchId,
      circleId: circleId,
      limit: limit,
    );
  }

  Stream<List<Post>> getCommunityFeed({
    required CommunityFeedMode mode,
    String? viewerChurchId,
    String? circleId,
    int limit = 75,
  }) async* {
    var lastKnown = <Post>[];
    var followingUserIds = const <String>{};
    var followingCircleIds = const <String>{};

    if (mode == CommunityFeedMode.following) {
      followingUserIds = await _acceptedFollowingIds();
      followingCircleIds = await _activeCircleIds();
    }

    try {
      lastKnown = await fetchCommunityFeed(
        mode: mode,
        viewerChurchId: viewerChurchId,
        circleId: circleId,
        limit: limit,
      );
      yield lastKnown;
    } catch (error) {
      debugPrint('Could not load community feed before realtime: $error');
    }

    try {
      await for (final posts in _supabase
          .from(_postsTable)
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .limit(limit)
          .map(
            (rows) => _normalizePosts(
              rows,
              viewerChurchId: viewerChurchId,
              includeShared: true,
            )
                .where((post) => _matchesFeedMode(
                      post,
                      mode,
                      circleId,
                      followingUserIds: followingUserIds,
                      followingCircleIds: followingCircleIds,
                    ))
                .toList(),
          )
          .timeout(
            _realtimeQuietTimeout,
            onTimeout: (sink) {
              sink.add(lastKnown);
            },
          )) {
        lastKnown = posts;
        yield posts;
      }
    } catch (error) {
      debugPrint('Community feed realtime unavailable: $error');
      if (lastKnown.isNotEmpty) yield lastKnown;
    }
  }

  Future<List<Post>> _fetchCommunityFeedFallback({
    required CommunityFeedMode mode,
    String? viewerChurchId,
    String? circleId,
    required int limit,
  }) async {
    final followingUserIds = mode == CommunityFeedMode.following
        ? await _acceptedFollowingIds()
        : const <String>{};
    final followingCircleIds = mode == CommunityFeedMode.following
        ? await _activeCircleIds()
        : const <String>{};
    if (mode == CommunityFeedMode.following &&
        followingUserIds.isEmpty &&
        followingCircleIds.isEmpty) {
      return const [];
    }

    final now = DateTime.now().toUtc().toIso8601String();
    List<dynamic> data;
    try {
      var query = _supabase
          .from(_postsTable)
          .select()
          .or('expires_at.is.null,expires_at.gt.$now');
      if (mode == CommunityFeedMode.circle &&
          circleId?.trim().isNotEmpty == true) {
        query = query.eq('circle_id', circleId!.trim());
      } else if (mode == CommunityFeedMode.discover) {
        query = query.or('scope.eq.global,visible_to_all_churches.eq.true');
      }
      data = await query
          .order('created_at', ascending: false)
          .limit(mode == CommunityFeedMode.following ? 200 : limit);
    } on PostgrestException {
      var query = _supabase
          .from(_postsTable)
          .select()
          .or('expires_at.is.null,expires_at.gt.$now');
      if (mode == CommunityFeedMode.discover) {
        query = query.eq('visible_to_all_churches', true);
      }
      data = await query
          .order('created_at', ascending: false)
          .limit(mode == CommunityFeedMode.following ? 200 : limit);
    }

    return _normalizePosts(
      data,
      viewerChurchId: viewerChurchId,
      includeShared: true,
    )
        .where((post) => _matchesFeedMode(
              post,
              mode,
              circleId,
              followingUserIds: followingUserIds,
              followingCircleIds: followingCircleIds,
            ))
        .take(limit)
        .toList();
  }

  // Get stream of posts for a specific church. The feed is REST-first so
  // realtime subscription timeouts never blank the screen.
  Stream<List<Post>> getPosts(String churchId) async* {
    var lastKnown = <Post>[];

    try {
      lastKnown = await fetchPosts(churchId);
      yield lastKnown;
    } catch (error) {
      debugPrint('Could not load posts before realtime: $error');
    }

    try {
      await for (final posts in _postsRealtime(churchId).timeout(
        _realtimeQuietTimeout,
        onTimeout: (sink) {
          sink.add(lastKnown);
        },
      )) {
        lastKnown = posts;
        yield posts;
      }
    } catch (error) {
      debugPrint('Post realtime unavailable, keeping last known data: $error');
      if (lastKnown.isNotEmpty) {
        yield lastKnown;
      }
    }
  }

  Stream<List<Post>> getPostsForChurches(
    String viewerChurchId,
    List<String>? churchIds, {
    bool includeShared = false,
  }) async* {
    var lastKnown = <Post>[];
    final queryChurchIds = churchIds
        ?.where((churchId) => churchId.trim().isNotEmpty)
        .map((churchId) => churchId.trim())
        .toSet()
        .toList();

    try {
      lastKnown = await fetchPostsForChurches(
        viewerChurchId,
        queryChurchIds,
        includeShared: includeShared,
      );
      yield lastKnown;
    } catch (error) {
      debugPrint('Could not load filtered posts before realtime: $error');
    }

    try {
      await for (final posts in _postsRealtimeForChurches(
        viewerChurchId,
        queryChurchIds,
        includeShared: includeShared,
      ).timeout(
        _realtimeQuietTimeout,
        onTimeout: (sink) {
          sink.add(lastKnown);
        },
      )) {
        lastKnown = posts;
        yield posts;
      }
    } catch (error) {
      debugPrint(
          'Filtered post realtime unavailable, keeping last known data: $error');
      if (lastKnown.isNotEmpty) {
        yield lastKnown;
      }
    }
  }

  Stream<List<Post>> _postsRealtime(String churchId) {
    return _supabase
        .from(_postsTable)
        .stream(primaryKey: ['id'])
        .eq('place_id', churchId)
        .order('created_at', ascending: false)
        .limit(50)
        .map(_normalizePosts);
  }

  Stream<List<Post>> _postsRealtimeForChurches(
    String viewerChurchId,
    List<String>? churchIds, {
    required bool includeShared,
  }) {
    final query = _supabase
        .from(_postsTable)
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(75);
    return query.map((rows) {
      return _normalizePosts(
        rows,
        viewerChurchId: viewerChurchId,
        churchIds: churchIds,
        includeShared: includeShared,
      );
    });
  }

  Stream<Post?> getPost(String postId) {
    return _supabase
        .from(_postsTable)
        .stream(primaryKey: ['id'])
        .eq('id', postId)
        .limit(1)
        .map((data) => data.isEmpty ? null : Post.fromMap(data.first));
  }

  Future<Post?> fetchPostById(String postId) async {
    if (postId.trim().isEmpty) return null;

    final row = await _supabase
        .from(_postsTable)
        .select()
        .eq('id', postId)
        .maybeSingle();
    if (row == null) return null;

    final post = Post.fromMap(Map<String, dynamic>.from(row));
    final expiresAt = post.expiresAt;
    if (expiresAt != null && expiresAt.isBefore(DateTime.now())) {
      return null;
    }
    return post;
  }

  Future<List<Post>> fetchPublicPostsByAuthor(
    String authorId, {
    int limit = 30,
  }) async {
    final cleanAuthorId = authorId.trim();
    if (cleanAuthorId.isEmpty) return const [];

    final now = DateTime.now().toUtc().toIso8601String();
    List<dynamic> rows;
    try {
      rows = await _supabase
          .from(_postsTable)
          .select()
          .eq('author_id', cleanAuthorId)
          .or('expires_at.is.null,expires_at.gt.$now')
          .order('created_at', ascending: false)
          .limit(limit);
    } on PostgrestException {
      rows = await _supabase
          .from(_postsTable)
          .select()
          .eq('author_id', cleanAuthorId)
          .order('created_at', ascending: false)
          .limit(limit);
    }

    return _normalizePosts(rows, includeShared: true)
        .where((post) =>
            post.visibleToAllChurches ||
            post.scope == 'global' ||
            post.scope == 'discover' ||
            post.scope == 'public')
        .take(limit)
        .toList();
  }

  Future<List<Post>> fetchPublicPostsForChurch(
    String churchId, {
    int limit = 30,
  }) async {
    final cleanChurchId = churchId.trim();
    if (cleanChurchId.isEmpty) return const [];

    final now = DateTime.now().toUtc().toIso8601String();
    List<dynamic> rows;
    try {
      rows = await _supabase
          .from(_postsTable)
          .select()
          .eq('place_id', cleanChurchId)
          .or('expires_at.is.null,expires_at.gt.$now')
          .order('created_at', ascending: false)
          .limit(limit);
    } on PostgrestException {
      rows = await _supabase
          .from(_postsTable)
          .select()
          .eq('place_id', cleanChurchId)
          .order('created_at', ascending: false)
          .limit(limit);
    }

    return _normalizePosts(
      rows,
      viewerChurchId: cleanChurchId,
      churchIds: [cleanChurchId],
      includeShared: true,
    )
        .where((post) =>
            post.visibleToAllChurches ||
            post.scope == 'global' ||
            post.scope == 'discover' ||
            post.scope == 'public')
        .take(limit)
        .toList();
  }

  Future<Post?> fetchPostForNotification({
    required String? entityTable,
    required String? entityId,
  }) async {
    final id = entityId?.trim() ?? '';
    if (id.isEmpty) return null;

    if (entityTable == 'community_posts') {
      return fetchPostById(id);
    }

    if (entityTable == 'community_comments') {
      final row = await _supabase
          .from(_commentsTable)
          .select('post_id')
          .eq('id', id)
          .maybeSingle();
      final postId = row?['post_id']?.toString() ?? '';
      return fetchPostById(postId);
    }

    return null;
  }

  Future<void> addPost(Post post) async {
    final data = post.toMap();
    try {
      await _supabase.from(_postsTable).insert(data);
    } on PostgrestException catch (error) {
      if (!_isLegacyCommunityPostSchemaIssue(error)) rethrow;
      final fallbackData = _legacyPostInsertData(data, post);
      await _supabase.from(_postsTable).insert(fallbackData);
    }
  }

  Future<void> deletePost(Post post) async {
    await _supabase.from(_commentsTable).delete().eq('post_id', post.id);
    await _supabase.from(_postsTable).delete().eq('id', post.id);

    final mediaPath =
        post.mediaPath ?? _storagePathFromPublicUrl(post.mediaUrl);
    if (mediaPath != null) {
      try {
        await _supabase.storage.from(_bucketName).remove([mediaPath]);
      } catch (e) {
        debugPrint('Post deleted, but media cleanup failed: $e');
      }
    }
  }

  Future<String> uploadMediaFile(
    File file,
    String path, {
    String? contentType,
  }) async {
    await _supabase.storage.from(_bucketName).upload(
          path,
          file,
          fileOptions: FileOptions(
            cacheControl: '3600',
            contentType: contentType,
            upsert: false,
          ),
        );
    return _supabase.storage.from(_bucketName).getPublicUrl(path);
  }

  Future<String> uploadMediaBytes(
    Uint8List bytes,
    String path, {
    String? contentType,
  }) async {
    await _supabase.storage.from(_bucketName).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            contentType: contentType,
            upsert: false,
          ),
        );
    return _supabase.storage.from(_bucketName).getPublicUrl(path);
  }

  Future<Post?> toggleLike(String postId, String userId) async {
    if (userId.isEmpty) return null;

    final data = await _supabase.rpc(
      'toggle_community_post_like',
      params: {'post_id': postId},
    );

    if (data is Map<String, dynamic>) {
      return Post.fromMap(data);
    }
    if (data is Map) {
      return Post.fromMap(Map<String, dynamic>.from(data));
    }
    return null;
  }

  Future<void> addComment(
      String postId, Map<String, dynamic> commentData) async {
    final data = {
      'post_id': postId,
      ...commentData,
    };

    await _supabase.from(_commentsTable).insert(data);
    // The comments_count on the post will be automatically updated by our Postgres Trigger!
  }

  Future<void> deleteComment(String commentId) async {
    await _supabase.from(_commentsTable).delete().eq('id', commentId);
  }

  Future<List<Map<String, dynamic>>> fetchComments(String postId) async {
    final data = await _supabase
        .from(_commentsTable)
        .select()
        .eq('post_id', postId)
        .order('created_at', ascending: false)
        .limit(100);
    return _dedupeRowsById(
      data.map((e) => Map<String, dynamic>.from(e)).toList(),
    );
  }

  Stream<List<Map<String, dynamic>>> getComments(String postId) async* {
    var lastKnown = <Map<String, dynamic>>[];

    try {
      lastKnown = await fetchComments(postId);
      yield lastKnown;
    } catch (error) {
      debugPrint('Could not load comments before realtime: $error');
    }

    try {
      await for (final comments in _commentsRealtime(postId).timeout(
        _realtimeQuietTimeout,
        onTimeout: (sink) {
          sink.add(lastKnown);
        },
      )) {
        lastKnown = comments;
        yield comments;
      }
    } catch (error) {
      debugPrint(
          'Comment realtime unavailable, keeping last known data: $error');
      if (lastKnown.isNotEmpty) yield lastKnown;
    }
  }

  Stream<List<Map<String, dynamic>>> _commentsRealtime(String postId) {
    return _supabase
        .from(_commentsTable)
        .stream(primaryKey: ['id'])
        .eq('post_id', postId)
        .order('created_at', ascending: false)
        .map((data) => _dedupeRowsById(
              data.map((e) => Map<String, dynamic>.from(e)).toList(),
            ));
  }

  List<Map<String, dynamic>> _dedupeRowsById(List<Map<String, dynamic>> rows) {
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final row in rows) {
      final id = row['id']?.toString();
      final key = id == null || id.isEmpty ? row.toString() : id;
      if (seen.add(key)) unique.add(row);
    }
    return unique;
  }

  List<CommunityStory> _normalizeStories(
    List<dynamic> data, {
    String? viewerChurchId,
    List<String>? churchIds,
    bool includeShared = false,
  }) {
    final filterIds = churchIds
        ?.where((churchId) => churchId.trim().isNotEmpty)
        .map((churchId) => churchId.trim())
        .toSet();
    final stories = data
        .map((map) => CommunityStory.fromMap(Map<String, dynamic>.from(map)))
        .where((story) {
      if (story.isExpired) return false;
      if (viewerChurchId == null || viewerChurchId.isEmpty) return true;
      final isOwnChurch = story.churchId == viewerChurchId;
      if (filterIds != null && filterIds.isNotEmpty) {
        return filterIds.contains(story.churchId) &&
            (isOwnChurch || (includeShared && story.visibleToAllChurches));
      }
      return isOwnChurch || (includeShared && story.visibleToAllChurches);
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return stories;
  }

  List<Post> _normalizePosts(
    List<dynamic> data, {
    String? viewerChurchId,
    List<String>? churchIds,
    bool includeShared = false,
  }) {
    final filterIds = churchIds
        ?.where((churchId) => churchId.trim().isNotEmpty)
        .map((churchId) => churchId.trim())
        .toSet();
    final postsById = <String, Post>{};
    for (final map in data) {
      final post = Post.fromMap(Map<String, dynamic>.from(map));
      final expiresAt = post.expiresAt;
      final isExpired = expiresAt != null && expiresAt.isBefore(DateTime.now());
      final isOwnChurch = post.placeId == viewerChurchId;
      final isPublicPost = post.visibleToAllChurches ||
          post.scope == 'global' ||
          post.scope == 'discover' ||
          post.scope == 'public';
      final hasViewerChurch = viewerChurchId?.trim().isNotEmpty == true;
      final canShow = !hasViewerChurch
          ? isPublicPost
          : (filterIds != null && filterIds.isNotEmpty
              ? filterIds.contains(post.placeId) &&
                  (isOwnChurch || (includeShared && isPublicPost))
              : isOwnChurch || (includeShared && isPublicPost));

      if (post.id.isNotEmpty && !isExpired && canShow) {
        postsById[post.id] = post;
      }
    }
    final posts = postsById.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return posts;
  }

  bool _matchesFeedMode(
    Post post,
    CommunityFeedMode mode,
    String? circleId, {
    Set<String> followingUserIds = const {},
    Set<String> followingCircleIds = const {},
  }) {
    final expiresAt = post.expiresAt;
    if (expiresAt != null && expiresAt.isBefore(DateTime.now())) return false;
    return switch (mode) {
      CommunityFeedMode.circle =>
        circleId == null || circleId.isEmpty || post.circleId == circleId,
      CommunityFeedMode.discover => post.visibleToAllChurches ||
          post.scope == 'global' ||
          post.scope == 'discover' ||
          post.scope == 'public',
      CommunityFeedMode.following => followingUserIds.contains(post.authorId) ||
          (post.circleId != null && followingCircleIds.contains(post.circleId)),
      CommunityFeedMode.church => true,
    };
  }

  Future<Set<String>> _acceptedFollowingIds() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return const {};

    try {
      final rows = await _supabase
          .from('social_follows')
          .select('following_id')
          .eq('follower_id', userId)
          .eq('status', 'accepted');
      return rows
          .map((row) => row['following_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (error) {
      debugPrint('Following list unavailable: $error');
      final prefs = await SharedPreferences.getInstance();
      return (prefs
                  .getStringList(SocialProfileService.localFollowKey(userId)) ??
              const [])
          .where((id) => id.trim().isNotEmpty)
          .toSet();
    }
  }

  Future<Set<String>> _activeCircleIds() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) return const {};

    try {
      final rows = await _supabase
          .from('grace_circle_members')
          .select('circle_id')
          .eq('user_id', userId)
          .eq('status', 'active');
      return rows
          .map((row) => row['circle_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (error) {
      debugPrint('Followed circle list unavailable: $error');
      return const {};
    }
  }

  Map<String, dynamic> _legacyPostInsertData(
    Map<String, dynamic> data,
    Post post,
  ) {
    final fallbackData = Map<String, dynamic>.from(data)
      ..remove('media_fit')
      ..remove('media_aspect_ratio')
      ..remove('scope')
      ..remove('post_type')
      ..remove('origin_church_id')
      ..remove('circle_id')
      ..remove('metadata')
      ..remove('repost_of')
      ..remove('is_persistent');
    fallbackData['place_id'] ??= post.originChurchId ?? post.placeId;
    fallbackData['expires_at'] ??=
        DateTime.now().add(const Duration(days: 30)).toUtc().toIso8601String();
    return fallbackData;
  }

  String? _storagePathFromPublicUrl(String? mediaUrl) {
    if (mediaUrl == null || mediaUrl.isEmpty) return null;

    final uri = Uri.tryParse(mediaUrl);
    if (uri == null) return null;

    final bucketIndex = uri.pathSegments.indexOf(_bucketName);
    if (bucketIndex < 0 || bucketIndex == uri.pathSegments.length - 1) {
      return null;
    }

    return uri.pathSegments.sublist(bucketIndex + 1).join('/');
  }

  bool _isLegacyCommunityPostSchemaIssue(PostgrestException error) {
    final message = error.message.toLowerCase();
    return message.contains('media_fit') ||
        message.contains('media_aspect_ratio') ||
        message.contains('scope') ||
        message.contains('post_type') ||
        message.contains('origin_church_id') ||
        message.contains('circle_id') ||
        message.contains('metadata') ||
        message.contains('repost_of') ||
        message.contains('is_persistent') ||
        message.contains('schema cache') ||
        error.code == 'PGRST204' ||
        error.code == '42703';
  }

  bool _isMissingMediaDisplayColumn(PostgrestException error) {
    final message = error.message.toLowerCase();
    return message.contains('media_fit') ||
        message.contains('media_aspect_ratio') ||
        message.contains('schema cache') ||
        error.code == 'PGRST204' ||
        error.code == '42703';
  }
}
