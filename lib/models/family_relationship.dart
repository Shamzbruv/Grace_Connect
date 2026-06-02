class FamilyRelationship {
  final String id;
  final String requesterId;
  final String relatedUserId;
  final String requesterName;
  final String relatedName;
  final String relationshipType;
  final String requesterPlaceId;
  final String relatedPlaceId;
  final String status;
  final String note;
  final DateTime requestedAt;
  final DateTime? respondedAt;

  const FamilyRelationship({
    required this.id,
    required this.requesterId,
    required this.relatedUserId,
    required this.requesterName,
    required this.relatedName,
    required this.relationshipType,
    required this.requesterPlaceId,
    required this.relatedPlaceId,
    required this.status,
    required this.note,
    required this.requestedAt,
    this.respondedAt,
  });

  factory FamilyRelationship.fromMap(Map<String, dynamic> data) {
    return FamilyRelationship(
      id: data['id'] ?? '',
      requesterId: data['requester_id'] ?? '',
      relatedUserId: data['related_user_id'] ?? '',
      requesterName: data['requester_name'] ?? '',
      relatedName: data['related_name'] ?? '',
      relationshipType: data['relationship_type'] ?? 'other',
      requesterPlaceId: data['requester_place_id'] ?? '',
      relatedPlaceId: data['related_place_id'] ?? '',
      status: data['status'] ?? 'pending',
      note: data['note'] ?? '',
      requestedAt: DateTime.tryParse(data['requested_at']?.toString() ?? '') ??
          DateTime.now(),
      respondedAt: DateTime.tryParse(data['responded_at']?.toString() ?? ''),
    );
  }

  bool get isPending => status == 'pending';
  bool get isAccepted => status == 'accepted';

  String labelForRequester() {
    return switch (relationshipType) {
      'father' => 'Father',
      'mother' => 'Mother',
      'husband' => 'Husband',
      'wife' => 'Wife',
      'spouse' => 'Spouse',
      'child' => 'Child',
      'sibling' => 'Sibling',
      'guardian' => 'Guardian',
      _ => 'Family',
    };
  }
}

class FamilyMemberSummary {
  final String uid;
  final String fullName;
  final String photoUrl;
  final String placeId;

  const FamilyMemberSummary({
    required this.uid,
    required this.fullName,
    required this.photoUrl,
    required this.placeId,
  });

  factory FamilyMemberSummary.fromMap(Map<String, dynamic> data) {
    final name = (data['fullName'] as String?)?.trim();
    return FamilyMemberSummary(
      uid: data['uid'] ?? data['id'] ?? '',
      fullName: name == null || name.isEmpty ? 'Member' : name,
      photoUrl: data['photoUrl'] ?? '',
      placeId: data['placeId'] ?? '',
    );
  }
}
