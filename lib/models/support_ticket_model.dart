class SupportTicket {
  final String ticketId;
  final String uid;
  final String reporterEmail;
  final String? churchId;
  final List<String> roles;

  final String issueType;
  final String appSection;
  final String summary;
  final String description;
  final String impact;

  final Map<String, dynamic> deviceInfo;
  final List<String> attachmentUrls;

  final String status; // open, in_progress, resolved
  final DateTime createdAt;

  SupportTicket({
    required this.ticketId,
    required this.uid,
    required this.reporterEmail,
    this.churchId,
    required this.roles,
    required this.issueType,
    required this.appSection,
    required this.summary,
    required this.description,
    required this.impact,
    required this.deviceInfo,
    required this.attachmentUrls,
    required this.status,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': ticketId,
      'userId': uid,
      'subject': summary,
      'uid': uid,
      'reporterEmail': reporterEmail,
      'churchId': churchId,
      'roles': roles,
      'issueType': issueType,
      'appSection': appSection,
      'summary': summary,
      'description': description,
      'impact': impact,
      'priority': impact.toLowerCase(),
      'deviceInfo': deviceInfo,
      'attachmentUrls': attachmentUrls,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
