class DailyMotivation {
  const DailyMotivation({
    required this.id,
    required this.publishDate,
    required this.title,
    required this.message,
    required this.scriptureReference,
    this.topic,
    required this.status,
    required this.isPublished,
    this.notificationSentAt,
    required this.createdAt,
  });

  final String id;
  final DateTime publishDate;
  final String title;
  final String message;
  final String scriptureReference;
  final String? topic;
  final String status;
  final bool isPublished;
  final DateTime? notificationSentAt;
  final DateTime createdAt;

  factory DailyMotivation.fromMap(Map<String, dynamic> data) {
    return DailyMotivation(
      id: data['id']?.toString() ?? '',
      publishDate: DateTime.tryParse(data['publish_date']?.toString() ?? '') ??
          DateTime.now(),
      title: data['title']?.toString() ?? 'Daily Word',
      message: data['message']?.toString() ?? '',
      scriptureReference: data['scripture_reference']?.toString() ?? '',
      topic: data['topic']?.toString(),
      status: data['status']?.toString() ?? 'draft',
      isPublished: data['is_published'] == true,
      notificationSentAt:
          DateTime.tryParse(data['notification_sent_at']?.toString() ?? ''),
      createdAt: DateTime.tryParse(data['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
