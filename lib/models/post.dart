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
  final DateTime? expiresAt;
  final bool visibleToAllChurches;

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
    this.expiresAt,
    this.visibleToAllChurches = false,
  });

  factory Post.fromMap(Map<String, dynamic> data) {
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
      expiresAt: _nullableDate(data['expires_at'] ?? data['expiresAt']),
      visibleToAllChurches: data['visible_to_all_churches'] == true ||
          data['visibleToAllChurches'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'author_name': authorName,
      'author_id': authorId,
      'author_photo': authorPhoto,
      'content': content,
      'likes': likes,
      'comments_count': commentsCount,
      'place_id': placeId,
      'media_url': mediaUrl,
      'media_path': mediaPath,
      'media_type': mediaType,
      'expires_at': (expiresAt ?? DateTime.now().add(const Duration(days: 30)))
          .toUtc()
          .toIso8601String(),
      'visible_to_all_churches': visibleToAllChurches,
      // 'id' and 'created_at' are typically handled by Supabase DB defaults
    };
  }

  static DateTime? _nullableDate(dynamic value) {
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}
