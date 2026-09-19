/// Which feed the Feed tab is currently showing. Reel Grace is a mode of the
/// existing Feed destination, not a sixth tab.
enum PrimaryFeedMode { community, reelGrace }

enum ReelVisibility {
  public('public', 'Public', 'Anyone on Grace Connect'),
  followers('followers', 'Followers', 'People who follow you'),
  church('church', 'My Church', 'Members of your church');

  const ReelVisibility(this.wireName, this.label, this.description);

  final String wireName;
  final String label;
  final String description;

  static ReelVisibility fromName(String? value) => ReelVisibility.values
      .firstWhere((v) => v.wireName == (value ?? '').trim().toLowerCase(),
          orElse: () => ReelVisibility.public);
}

/// A reel as the feed returns it. Note there is no playback URL here: the
/// feed deliberately returns object keys, and URLs are signed separately,
/// held in memory, and never persisted. See docs/launch_reel_grace_plan.md.
class Reel {
  const Reel({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.caption,
    required this.visibility,
    this.authorAvatarUrl,
    this.authorChurchId,
    this.category,
    this.videoObjectKey,
    this.posterObjectKey,
    this.durationMs,
    this.aspectRatio,
    this.audioLabel = 'Original audio',
    this.commentsEnabled = true,
    this.publishedAt,
    this.rankingScore = 0,
    this.likeCount = 0,
    this.commentCount = 0,
    this.saveCount = 0,
    this.viewerLiked = false,
    this.viewerSaved = false,
    this.viewerFollowsAuthor = false,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String? authorAvatarUrl;
  final String? authorChurchId;
  final String caption;
  final String? category;
  final ReelVisibility visibility;
  final String? videoObjectKey;
  final String? posterObjectKey;
  final int? durationMs;
  final double? aspectRatio;
  final String audioLabel;
  final bool commentsEnabled;
  final DateTime? publishedAt;
  final double rankingScore;
  final int likeCount;
  final int commentCount;
  final int saveCount;
  final bool viewerLiked;
  final bool viewerSaved;
  final bool viewerFollowsAuthor;

  factory Reel.fromMap(Map<String, dynamic> data) {
    return Reel(
      id: data['id']?.toString() ?? '',
      authorId: data['author_id']?.toString() ?? '',
      authorName: data['author_name']?.toString() ?? 'Member',
      authorAvatarUrl: data['author_avatar_url']?.toString(),
      authorChurchId: data['author_church_id']?.toString(),
      caption: data['caption']?.toString() ?? '',
      category: data['category']?.toString(),
      visibility: ReelVisibility.fromName(data['visibility']?.toString()),
      videoObjectKey: data['video_object_key']?.toString(),
      posterObjectKey: data['poster_object_key']?.toString(),
      durationMs: (data['duration_ms'] as num?)?.toInt(),
      aspectRatio: (data['aspect_ratio'] as num?)?.toDouble(),
      audioLabel: data['audio_label']?.toString() ?? 'Original audio',
      commentsEnabled: data['comments_enabled'] != false,
      publishedAt: DateTime.tryParse(data['published_at']?.toString() ?? ''),
      rankingScore: (data['ranking_score'] as num?)?.toDouble() ?? 0,
      likeCount: (data['like_count'] as num?)?.toInt() ?? 0,
      commentCount: (data['comment_count'] as num?)?.toInt() ?? 0,
      saveCount: (data['save_count'] as num?)?.toInt() ?? 0,
      viewerLiked: data['viewer_liked'] == true,
      viewerSaved: data['viewer_saved'] == true,
      viewerFollowsAuthor: data['viewer_follows_author'] == true,
    );
  }

  Reel copyWith({
    int? likeCount,
    int? saveCount,
    int? commentCount,
    bool? viewerLiked,
    bool? viewerSaved,
    bool? viewerFollowsAuthor,
  }) {
    return Reel(
      id: id,
      authorId: authorId,
      authorName: authorName,
      authorAvatarUrl: authorAvatarUrl,
      authorChurchId: authorChurchId,
      caption: caption,
      category: category,
      visibility: visibility,
      videoObjectKey: videoObjectKey,
      posterObjectKey: posterObjectKey,
      durationMs: durationMs,
      aspectRatio: aspectRatio,
      audioLabel: audioLabel,
      commentsEnabled: commentsEnabled,
      publishedAt: publishedAt,
      rankingScore: rankingScore,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      saveCount: saveCount ?? this.saveCount,
      viewerLiked: viewerLiked ?? this.viewerLiked,
      viewerSaved: viewerSaved ?? this.viewerSaved,
      viewerFollowsAuthor: viewerFollowsAuthor ?? this.viewerFollowsAuthor,
    );
  }
}

/// Signed playback URLs for one reel. Held in memory only -- never written to
/// disk, never stored on the Reel, never persisted anywhere. A signed URL is
/// a bearer capability until it expires.
class ReelMedia {
  const ReelMedia({
    required this.videoUrl,
    required this.posterUrl,
    required this.expiresAt,
  });

  final String? videoUrl;
  final String? posterUrl;
  final DateTime expiresAt;

  /// Refreshed before it actually lapses, so a long watch or a seek does not
  /// fail on an expiry that was predictable.
  static const Duration refreshMargin = Duration(minutes: 5);

  bool get needsRefresh =>
      DateTime.now().isAfter(expiresAt.subtract(refreshMargin));

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class ReelPage {
  const ReelPage({required this.reels, this.nextCursor});

  final List<Reel> reels;
  final Map<String, dynamic>? nextCursor;

  bool get hasMore => nextCursor != null;
}
