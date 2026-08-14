class Post {
  final String id;
  final String authorName;
  final String authorId;
  final String? authorPhoto;
  final String content;
  final DateTime timestamp;
  final List<String> likes;
  final int commentsCount;
  final String placeId;
  final String? mediaUrl;
  final String? mediaPath;
  final String? mediaType;
  final String? mediaThumbnailUrl;
  final String? mediaThumbnailPath;
  final String mediaFit;
  final double? mediaAspectRatio;
  final DateTime? expiresAt;
  final bool visibleToAllChurches;
  final String scope;
  final String postType;
  final String? originChurchId;
  final Map<String, dynamic> metadata;
  final String? repostOf;
  final bool isPersistent;

  Post({
    required this.id,
    required this.authorName,
    required this.authorId,
    this.authorPhoto,
    required this.content,
    required this.timestamp,
    required this.likes,
    this.commentsCount = 0,
    required this.placeId,
    this.mediaUrl,
    this.mediaPath,
    this.mediaType,
    this.mediaThumbnailUrl,
    this.mediaThumbnailPath,
    this.mediaFit = 'cover',
    this.mediaAspectRatio,
    this.expiresAt,
    this.visibleToAllChurches = false,
    this.scope = 'church',
    this.postType = 'post',
    this.originChurchId,
    this.metadata = const {},
    this.repostOf,
    bool? isPersistent,
  }) : isPersistent = isPersistent ?? expiresAt == null;

  factory Post.fromMap(Map<String, dynamic> data) {
    final metadataValue = data['metadata'];
    return Post(
      id: data['id'] as String,
      authorName: data['author_name'] ?? '',
      authorId: data['author_id'] ?? '',
      authorPhoto: data['author_photo'],
      content: data['content'] ?? '',
      timestamp: data['created_at'] != null
          ? DateTime.parse(data['created_at'] as String).toLocal()
          : DateTime.now(),
      likes: List<String>.from(data['likes'] ?? []),
      commentsCount: data['comments_count'] ?? 0,
      placeId: data['place_id'] ?? data['placeId'] ?? '',
      mediaUrl: data['media_url'],
      mediaPath: data['media_path'] ?? data['mediaPath'],
      mediaType: data['media_type'],
      mediaThumbnailUrl:
          data['media_thumbnail_url'] ?? data['mediaThumbnailUrl'],
      mediaThumbnailPath:
          data['media_thumbnail_path'] ?? data['mediaThumbnailPath'],
      mediaFit: (data['media_fit'] ?? data['mediaFit'] ?? 'cover').toString(),
      mediaAspectRatio: _nullableDouble(
          data['media_aspect_ratio'] ?? data['mediaAspectRatio']),
      expiresAt: _nullableDate(data['expires_at'] ?? data['expiresAt']),
      visibleToAllChurches: data['visible_to_all_churches'] == true ||
          data['visibleToAllChurches'] == true,
      scope: data['scope']?.toString() ??
          (data['visible_to_all_churches'] == true ? 'global' : 'church'),
      postType: data['post_type']?.toString() ?? 'post',
      originChurchId: data['origin_church_id']?.toString(),
      metadata: metadataValue is Map
          ? Map<String, dynamic>.from(metadataValue)
          : const {},
      repostOf: data['repost_of']?.toString(),
      isPersistent: data['is_persistent'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    final cleanPlaceId = placeId.trim();
    return {
      'author_name': authorName,
      'author_id': authorId,
      'author_photo': authorPhoto,
      'content': content,
      'likes': likes,
      'comments_count': commentsCount,
      'place_id': cleanPlaceId.isEmpty ? null : cleanPlaceId,
      'media_url': mediaUrl,
      'media_path': mediaPath,
      'media_type': mediaType,
      'media_thumbnail_url': mediaThumbnailUrl,
      'media_thumbnail_path': mediaThumbnailPath,
      'media_fit': mediaFit,
      'media_aspect_ratio': mediaAspectRatio,
      'expires_at': expiresAt?.toUtc().toIso8601String(),
      'visible_to_all_churches': visibleToAllChurches,
      'scope': scope,
      'post_type': postType,
      'origin_church_id': originChurchId,
      'metadata': metadata,
      'repost_of': repostOf,
      'is_persistent': isPersistent || expiresAt == null,
      // 'id' and 'created_at' are typically handled by Supabase DB defaults
    };
  }

  static DateTime? _nullableDate(dynamic value) {
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }

  static double? _nullableDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
