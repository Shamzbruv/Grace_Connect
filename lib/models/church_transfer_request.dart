class ChurchTransferRequest {
  const ChurchTransferRequest({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.currentChurchId,
    required this.currentChurchName,
    required this.targetChurchId,
    required this.targetChurchName,
    required this.reason,
    required this.contactPhone,
    required this.status,
    required this.pastorNotes,
    required this.targetPastorNotes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String userName;
  final String userEmail;
  final String currentChurchId;
  final String currentChurchName;
  final String targetChurchId;
  final String targetChurchName;
  final String reason;
  final String contactPhone;
  final String status;
  final String pastorNotes;
  final String targetPastorNotes;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ChurchTransferRequest.fromMap(Map<String, dynamic> data) {
    return ChurchTransferRequest(
      id: data['id']?.toString() ?? '',
      userId: data['user_id']?.toString() ?? '',
      userName: data['user_name'] ?? 'Member',
      userEmail: data['user_email'] ?? '',
      currentChurchId: data['current_church_id'] ?? '',
      currentChurchName: data['current_church_name'] ?? '',
      targetChurchId: data['target_church_id'] ?? '',
      targetChurchName: data['target_church_name'] ?? '',
      reason: data['reason'] ?? '',
      contactPhone: data['contact_phone'] ?? '',
      status: data['status'] ?? 'submitted',
      pastorNotes: data['pastor_notes'] ?? '',
      targetPastorNotes: data['target_pastor_notes'] ?? '',
      createdAt: DateTime.tryParse(data['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(data['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  String get statusLabel {
    return switch (status) {
      'submitted' => 'Submitted to pastor',
      'pastor_review' => 'Pastor reviewing',
      'sent_to_target_pastor' => 'Sent to receiving pastor',
      'approved' => 'Approved',
      'declined' => 'Declined',
      'completed' => 'Completed',
      'cancelled' => 'Cancelled',
      _ => status.replaceAll('_', ' '),
    };
  }
}
