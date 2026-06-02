class Testimony {
  const Testimony({
    required this.id,
    required this.churchId,
    required this.authorId,
    required this.authorName,
    required this.content,
    required this.isAnonymous,
    required this.reactions,
    required this.createdAt,
  });

  final String id;
  final String churchId;
  final String authorId;
  final String authorName;
  final String content;
  final bool isAnonymous;
  final Map<String, List<String>> reactions;
  final DateTime createdAt;

  factory Testimony.fromMap(Map<String, dynamic> data) {
    final rawReactions = Map<String, dynamic>.from(data['reactions'] ?? {});

    return Testimony(
      id: data['id']?.toString() ?? '',
      churchId: data['church_id'] ?? data['churchId'] ?? '',
      authorId: data['author_id'] ?? data['authorId'] ?? '',
      authorName: data['author_name'] ?? data['authorName'] ?? 'Member',
      content: data['content'] ?? '',
      isAnonymous: data['is_anonymous'] ?? data['isAnonymous'] ?? false,
      reactions: rawReactions.map(
        (emoji, users) => MapEntry(
          emoji,
          List<String>.from(users ?? []),
        ),
      ),
      createdAt: _parseDate(data['created_at'] ?? data['createdAt']),
    );
  }

  String get displayName => isAnonymous ? 'Anonymous' : authorName;

  int reactionCount(String emoji) => reactions[emoji]?.length ?? 0;

  bool reactedWith(String emoji, String uid) {
    return reactions[emoji]?.contains(uid) == true;
  }

  static DateTime _parseDate(dynamic value) {
    if (value is String) {
      return DateTime.tryParse(value)?.toLocal() ?? DateTime.now();
    }
    return DateTime.now();
  }
}
