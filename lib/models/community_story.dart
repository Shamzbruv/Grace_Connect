class CommunityStory {
  const CommunityStory({
    required this.id,
    required this.churchId,
    required this.authorId,
    required this.authorName,
    this.authorPhoto,
    this.caption,
    this.mediaUrl,
    this.mediaPath,
    this.mediaType,
    this.likes = const [],
    this.visibleToAllChurches = false,
    required this.createdAt,
    required this.expiresAt,
  });

  final String id;
  final String churchId;
  final String authorId;
  final String authorName;
  final String? authorPhoto;
  final String? caption;
  final String? mediaUrl;
  final String? mediaPath;
  final String? mediaType;
  final List<String> likes;
  final bool visibleToAllChurches;
  final DateTime createdAt;
  final DateTime expiresAt;

  bool get isExpired => expiresAt.isBefore(DateTime.now());

  factory CommunityStory.fromMap(Map<String, dynamic> data) {
    return CommunityStory(
      id: data['id']?.toString() ?? '',
      churchId: data['church_id'] ?? data['churchId'] ?? '',
      authorId: data['author_id'] ?? data['authorId'] ?? '',
      authorName: data['author_name'] ?? data['authorName'] ?? 'Member',
      authorPhoto: data['author_photo'] ?? data['authorPhoto'],
      caption: data['caption'],
      mediaUrl: data['media_url'] ?? data['mediaUrl'],
      mediaPath: data['media_path'] ?? data['mediaPath'],
      mediaType: data['media_type'] ?? data['mediaType'],
      likes: _parseStringList(data['likes']),
      visibleToAllChurches: data['visible_to_all_churches'] == true ||
          data['visibleToAllChurches'] == true,
      createdAt: _parseDate(data['created_at'] ?? data['createdAt']),
      expiresAt: _parseDate(data['expires_at'] ?? data['expiresAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'church_id': churchId,
      'author_id': authorId,
      'author_name': authorName,
      'author_photo': authorPhoto,
      'caption': caption,
      'media_url': mediaUrl,
      'media_path': mediaPath,
      'media_type': mediaType,
      'likes': likes,
      'visible_to_all_churches': visibleToAllChurches,
      'created_at': createdAt.toUtc().toIso8601String(),
      'expires_at': expiresAt.toUtc().toIso8601String(),
    };
  }

  CommunityStory copyWith({
    List<String>? likes,
  }) {
    return CommunityStory(
      id: id,
      churchId: churchId,
      authorId: authorId,
      authorName: authorName,
      authorPhoto: authorPhoto,
      caption: caption,
      mediaUrl: mediaUrl,
      mediaPath: mediaPath,
      mediaType: mediaType,
      likes: likes ?? this.likes,
      visibleToAllChurches: visibleToAllChurches,
      createdAt: createdAt,
      expiresAt: expiresAt,
    );
  }

  static DateTime _parseDate(dynamic value) {
    if (value is String) {
      return DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
    }
    return DateTime.now();
  }

  static List<String> _parseStringList(dynamic value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }
    return const [];
  }
}
