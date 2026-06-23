import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/community_story.dart';
import '../models/post.dart';

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

  Future<List<Post>> fetchPosts(String churchId) async {
    late final List<dynamic> data;
    try {
      data = await _supabase
          .from(_postsTable)
          .select()
          .eq('place_id', churchId)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
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
      var query = _supabase.from(_postsTable).select().gt('expires_at', now);
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
      if (!_isMissingMediaDisplayColumn(error)) rethrow;
      final fallbackData = Map<String, dynamic>.from(data)
        ..remove('media_fit')
        ..remove('media_aspect_ratio');
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

  Stream<List<Map<String, dynamic>>> getComments(String postId) {
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
      final canShow = viewerChurchId == null ||
          viewerChurchId.isEmpty ||
          (filterIds != null && filterIds.isNotEmpty
              ? filterIds.contains(post.placeId) &&
                  (isOwnChurch || (includeShared && post.visibleToAllChurches))
              : isOwnChurch || (includeShared && post.visibleToAllChurches));

      if (post.id.isNotEmpty && !isExpired && canShow) {
        postsById[post.id] = post;
      }
    }
    final posts = postsById.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return posts;
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

  bool _isMissingMediaDisplayColumn(PostgrestException error) {
    final message = error.message.toLowerCase();
    return message.contains('media_fit') ||
        message.contains('media_aspect_ratio') ||
        message.contains('schema cache') ||
        error.code == 'PGRST204' ||
        error.code == '42703';
  }
}
