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

  Future<List<CommunityStory>> fetchActiveStories(String churchId) async {
    final data = await _supabase
        .from(_storiesTable)
        .select()
        .eq('church_id', churchId)
        .order('created_at', ascending: false)
        .limit(100);

    return _normalizeStories(data);
  }

  Stream<List<CommunityStory>> getActiveStories(String churchId) async* {
    var lastKnown = <CommunityStory>[];

    try {
      lastKnown = await fetchActiveStories(churchId);
      yield lastKnown;
    } catch (error) {
      debugPrint('Could not load statuses before realtime: $error');
    }

    try {
      await for (final stories in _activeStoriesRealtime(churchId).timeout(
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

  Stream<List<CommunityStory>> _activeStoriesRealtime(String churchId) {
    return _supabase
        .from(_storiesTable)
        .stream(primaryKey: ['id'])
        .eq('church_id', churchId)
        .order('created_at', ascending: false)
        .map(_normalizeStories);
  }

  Future<void> addStory(CommunityStory story) async {
    await _supabase.from(_storiesTable).insert(story.toMap());
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

  Stream<List<Post>> _postsRealtime(String churchId) {
    return _supabase
        .from(_postsTable)
        .stream(primaryKey: ['id'])
        .eq('place_id', churchId)
        .order('created_at', ascending: false)
        .limit(50)
        .map(_normalizePosts);
  }

  Stream<Post?> getPost(String postId) {
    return _supabase
        .from(_postsTable)
        .stream(primaryKey: ['id'])
        .eq('id', postId)
        .limit(1)
        .map((data) => data.isEmpty ? null : Post.fromMap(data.first));
  }

  Future<void> addPost(Post post) async {
    await _supabase.from(_postsTable).insert(post.toMap());
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

  Future<void> toggleLike(String postId, String userId) async {
    if (userId.isEmpty) return;

    try {
      await _supabase.rpc(
        'toggle_community_post_like',
        params: {'post_id': postId},
      );
    } catch (e) {
      debugPrint('Error toggling like: $e');
    }
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
        .map((data) => data.map((e) => Map<String, dynamic>.from(e)).toList());
  }

  List<CommunityStory> _normalizeStories(List<dynamic> data) {
    final stories = data
        .map((map) => CommunityStory.fromMap(Map<String, dynamic>.from(map)))
        .where((story) => !story.isExpired)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return stories;
  }

  List<Post> _normalizePosts(List<dynamic> data) {
    final postsById = <String, Post>{};
    for (final map in data) {
      final post = Post.fromMap(Map<String, dynamic>.from(map));
      final expiresAt = post.expiresAt;
      final isExpired = expiresAt != null && expiresAt.isBefore(DateTime.now());
      if (post.id.isNotEmpty && !isExpired) {
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
}
