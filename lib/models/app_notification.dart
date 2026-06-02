class AppNotification {
  final String id;
  final String userId;
  final String? actorId;
  final String actorName;
  final String type;
  final String title;
  final String body;
  final String? placeId;
  final String? entityTable;
  final String? entityId;
  final String? route;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.actorId,
    required this.actorName,
    required this.type,
    required this.title,
    required this.body,
    required this.placeId,
    required this.entityTable,
    required this.entityId,
    required this.route,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> data) {
    return AppNotification(
      id: data['id'] ?? '',
      userId: data['user_id'] ?? '',
      actorId: data['actor_id'],
      actorName: data['actor_name'] ?? 'Grace Connect',
      type: data['type'] ?? 'general',
      title: data['title'] ?? 'Notification',
      body: data['body'] ?? '',
      placeId: data['place_id'],
      entityTable: data['entity_table'],
      entityId: data['entity_id'],
      route: data['route'],
      isRead: data['is_read'] == true,
      createdAt: DateTime.tryParse(data['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
