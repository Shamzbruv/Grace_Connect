import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:grace_connect/models/community_story.dart';
import 'package:grace_connect/models/post.dart';
import 'package:grace_connect/screens/community/community_feed_screen.dart';
import 'package:grace_connect/utils/media_display_format.dart';
import 'package:grace_connect/widgets/community_video_player.dart';

void main() {
  test('community feed and shared video player compile together', () {
    expect(const CommunityFeedScreen(), isA<CommunityFeedScreen>());
    expect(
      const CommunityVideoPlayer(mediaUrl: 'https://example.test/video.mp4'),
      isA<CommunityVideoPlayer>(),
    );
  });

  group('media orientation recommendation', () {
    test('wide flyers default to full media so edges are preserved', () {
      final recommendation = recommendMediaDisplayFormat(1.91);

      expect(recommendation.orientation, MediaOrientation.landscape);
      expect(recommendation.format, MediaDisplayFormat.full);
      expect(recommendation.summary, contains('no edge is cropped'));
    });

    test('long and square media are identified without forcing a crop', () {
      expect(
        recommendMediaDisplayFormat(0.56).orientation,
        MediaOrientation.portrait,
      );
      expect(
        recommendMediaDisplayFormat(1).orientation,
        MediaOrientation.square,
      );
      expect(
        recommendMediaDisplayFormat(0.56).format,
        MediaDisplayFormat.full,
      );
    });
  });

  test('post and status models preserve video poster metadata', () {
    final post = Post.fromMap({
      'id': 'post-1',
      'author_name': 'Member',
      'author_id': 'user-1',
      'content': '',
      'likes': const <String>[],
      'place_id': 'church-1',
      'media_type': 'video',
      'media_thumbnail_url': 'https://cdn.example/poster.jpg',
      'media_thumbnail_path': 'church-1/poster.jpg',
    });
    final story = CommunityStory.fromMap({
      'id': 'story-1',
      'church_id': 'church-1',
      'author_id': 'user-1',
      'author_name': 'Member',
      'media_type': 'video',
      'media_thumbnail_url': 'https://cdn.example/story-poster.jpg',
      'media_thumbnail_path': 'church-1/stories/poster.jpg',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'expires_at':
          DateTime.now().add(const Duration(hours: 24)).toIso8601String(),
    });

    expect(post.mediaThumbnailUrl, endsWith('poster.jpg'));
    expect(post.toMap()['media_thumbnail_path'], 'church-1/poster.jpg');
    expect(story.mediaThumbnailUrl, endsWith('story-poster.jpg'));
    expect(
      story.toMap()['media_thumbnail_path'],
      'church-1/stories/poster.jpg',
    );
  });

  test('composer optimizes photos and inspects videos before upload', () {
    final feed = File('lib/screens/community/community_feed_screen.dart')
        .readAsStringSync();
    final inspection =
        File('lib/utils/community_video_inspection.dart').readAsStringSync();

    expect(feed, contains('maxWidth: 2160'));
    expect(feed, contains('imageQuality: 88'));
    expect(feed, contains('inspectCommunityVideo('));
    expect(feed, contains('maxByteLength: _maxCommunityVideoBytes'));
    expect(feed, contains('50 * 1024 * 1024'));
    expect(feed, contains('selectedStoryVideoThumbnailBytes'));
    expect(feed, contains("mediaType: _mediaType ?? 'media'"));
    expect(inspection, contains('VideoThumbnail.thumbnailData'));
    expect(inspection, contains('maxWidth: 960'));
    expect(inspection, contains('byteLength > maxByteLength'));
  });

  test('feed is thumbnail-first and bounds decoder/network work', () {
    final player =
        File('lib/widgets/community_video_player.dart').readAsStringSync();
    final feed = File('lib/screens/community/community_feed_screen.dart')
        .readAsStringSync();
    final service =
        File('lib/services/community_service.dart').readAsStringSync();

    expect(player, contains('class _VideoPoster'));
    expect(player, contains('_VideoInitializationGate(maxConcurrent: 2)'));
    expect(player, contains('generation != _loadGeneration'));
    expect(player, contains('!_visible'));
    expect(player, contains('initializationStarted'));
    expect(player, contains('_offscreenReleaseDelay'));
    expect(player, contains('_VideoPlaybackCoordinator'));
    expect(player, contains('VideoViewType.textureView'));
    expect(feed, contains('thumbnailUrl: post.mediaThumbnailUrl'));
    expect(feed, contains('_queueVideoPosterPrefetch(posts)'));
    expect(feed, contains('CachedNetworkImageProvider(url)'));
    expect(feed, contains('cacheExtent: 480'));
    expect(service, contains("cacheControl: '31536000'"));
    expect(service, contains('removeUploadedMediaObjects'));
    expect(feed, contains('pendingThumbnailPath'));
    expect(feed, contains('if (!committed)'));
  });

  test('poster schema and app storage cleanup cover posts and statuses', () {
    final migration = File(
      'supabase/migrations/20260814153000_community_video_posters.sql',
    ).readAsStringSync();
    final service =
        File('lib/services/community_service.dart').readAsStringSync();

    expect(migration, contains('alter table public.community_posts'));
    expect(migration, contains('alter table public.community_stories'));
    expect(migration, contains('media_thumbnail_url'));
    expect(migration, contains('media_thumbnail_path'));
    expect(migration, contains("set media_fit = 'contain'"));
    expect(migration, contains('media_aspect_ratio is null'));
    // Supabase Storage objects are removed through its Storage API. A previous
    // migration deliberately disabled direct storage.objects triggers because
    // they made row-expiry cleanup transactions fail.
    expect(migration, isNot(contains('delete from storage.objects')));
    expect(service, contains('story.mediaThumbnailPath'));
    expect(service, contains('post.mediaThumbnailPath'));
    expect(service, contains('removeUploadedMediaObjects'));
  });
}
