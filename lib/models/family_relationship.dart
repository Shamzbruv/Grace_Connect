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

  static const List<FamilyRelationshipOption> relationshipOptions = [
    FamilyRelationshipOption(
      value: 'father',
      label: 'Father',
      inverseLabel: 'Child',
      category: 'Immediate family',
      description: 'Parent and child connection.',
    ),
    FamilyRelationshipOption(
      value: 'mother',
      label: 'Mother',
      inverseLabel: 'Child',
      category: 'Immediate family',
      description: 'Parent and child connection.',
    ),
    FamilyRelationshipOption(
      value: 'parent',
      label: 'Parent',
      inverseLabel: 'Child',
      category: 'Immediate family',
      description: 'Parent and child connection.',
    ),
    FamilyRelationshipOption(
      value: 'son',
      label: 'Son',
      inverseLabel: 'Parent',
      category: 'Immediate family',
      description: 'Child and parent connection.',
    ),
    FamilyRelationshipOption(
      value: 'daughter',
      label: 'Daughter',
      inverseLabel: 'Parent',
      category: 'Immediate family',
      description: 'Child and parent connection.',
    ),
    FamilyRelationshipOption(
      value: 'child',
      label: 'Child',
      inverseLabel: 'Parent',
      category: 'Immediate family',
      description: 'Child and parent connection.',
    ),
    FamilyRelationshipOption(
      value: 'brother',
      label: 'Brother',
      inverseLabel: 'Sibling',
      category: 'Immediate family',
      description: 'Brother or sibling connection.',
    ),
    FamilyRelationshipOption(
      value: 'sister',
      label: 'Sister',
      inverseLabel: 'Sibling',
      category: 'Immediate family',
      description: 'Sister or sibling connection.',
    ),
    FamilyRelationshipOption(
      value: 'sibling',
      label: 'Sibling',
      inverseLabel: 'Sibling',
      category: 'Immediate family',
      description: 'Brother, sister, or sibling connection.',
    ),
    FamilyRelationshipOption(
      value: 'husband',
      label: 'Husband',
      inverseLabel: 'Spouse',
      category: 'Marriage',
      description: 'Marriage relationship.',
    ),
    FamilyRelationshipOption(
      value: 'wife',
      label: 'Wife',
      inverseLabel: 'Spouse',
      category: 'Marriage',
      description: 'Marriage relationship.',
    ),
    FamilyRelationshipOption(
      value: 'spouse',
      label: 'Spouse',
      inverseLabel: 'Spouse',
      category: 'Marriage',
      description: 'Marriage relationship.',
    ),
    FamilyRelationshipOption(
      value: 'grandfather',
      label: 'Grandfather',
      inverseLabel: 'Grandchild',
      category: 'Extended family',
      description: 'Grandparent and grandchild connection.',
    ),
    FamilyRelationshipOption(
      value: 'grandmother',
      label: 'Grandmother',
      inverseLabel: 'Grandchild',
      category: 'Extended family',
      description: 'Grandparent and grandchild connection.',
    ),
    FamilyRelationshipOption(
      value: 'grandparent',
      label: 'Grandparent',
      inverseLabel: 'Grandchild',
      category: 'Extended family',
      description: 'Grandparent and grandchild connection.',
    ),
    FamilyRelationshipOption(
      value: 'grandson',
      label: 'Grandson',
      inverseLabel: 'Grandparent',
      category: 'Extended family',
      description: 'Grandchild and grandparent connection.',
    ),
    FamilyRelationshipOption(
      value: 'granddaughter',
      label: 'Granddaughter',
      inverseLabel: 'Grandparent',
      category: 'Extended family',
      description: 'Grandchild and grandparent connection.',
    ),
    FamilyRelationshipOption(
      value: 'grandchild',
      label: 'Grandchild',
      inverseLabel: 'Grandparent',
      category: 'Extended family',
      description: 'Grandchild and grandparent connection.',
    ),
    FamilyRelationshipOption(
      value: 'uncle',
      label: 'Uncle',
      inverseLabel: 'Niece/Nephew',
      category: 'Extended family',
      description: 'Aunt, uncle, niece, or nephew connection.',
    ),
    FamilyRelationshipOption(
      value: 'aunt',
      label: 'Aunt',
      inverseLabel: 'Niece/Nephew',
      category: 'Extended family',
      description: 'Aunt, uncle, niece, or nephew connection.',
    ),
    FamilyRelationshipOption(
      value: 'nephew',
      label: 'Nephew',
      inverseLabel: 'Aunt/Uncle',
      category: 'Extended family',
      description: 'Aunt, uncle, niece, or nephew connection.',
    ),
    FamilyRelationshipOption(
      value: 'niece',
      label: 'Niece',
      inverseLabel: 'Aunt/Uncle',
      category: 'Extended family',
      description: 'Aunt, uncle, niece, or nephew connection.',
    ),
    FamilyRelationshipOption(
      value: 'cousin',
      label: 'Cousin',
      inverseLabel: 'Cousin',
      category: 'Extended family',
      description: 'Cousin connection.',
    ),
    FamilyRelationshipOption(
      value: 'father_in_law',
      label: 'Father-in-law',
      inverseLabel: 'Child-in-law',
      category: 'In-law family',
      description: 'Family connection through marriage.',
    ),
    FamilyRelationshipOption(
      value: 'mother_in_law',
      label: 'Mother-in-law',
      inverseLabel: 'Child-in-law',
      category: 'In-law family',
      description: 'Family connection through marriage.',
    ),
    FamilyRelationshipOption(
      value: 'brother_in_law',
      label: 'Brother-in-law',
      inverseLabel: 'Sibling-in-law',
      category: 'In-law family',
      description: 'Family connection through marriage.',
    ),
    FamilyRelationshipOption(
      value: 'sister_in_law',
      label: 'Sister-in-law',
      inverseLabel: 'Sibling-in-law',
      category: 'In-law family',
      description: 'Family connection through marriage.',
    ),
    FamilyRelationshipOption(
      value: 'son_in_law',
      label: 'Son-in-law',
      inverseLabel: 'Parent-in-law',
      category: 'In-law family',
      description: 'Family connection through marriage.',
    ),
    FamilyRelationshipOption(
      value: 'daughter_in_law',
      label: 'Daughter-in-law',
      inverseLabel: 'Parent-in-law',
      category: 'In-law family',
      description: 'Family connection through marriage.',
    ),
    FamilyRelationshipOption(
      value: 'step_father',
      label: 'Stepfather',
      inverseLabel: 'Stepchild',
      category: 'Step and adoptive family',
      description: 'Step-family connection.',
    ),
    FamilyRelationshipOption(
      value: 'step_mother',
      label: 'Stepmother',
      inverseLabel: 'Stepchild',
      category: 'Step and adoptive family',
      description: 'Step-family connection.',
    ),
    FamilyRelationshipOption(
      value: 'step_parent',
      label: 'Step-parent',
      inverseLabel: 'Stepchild',
      category: 'Step and adoptive family',
      description: 'Step-family connection.',
    ),
    FamilyRelationshipOption(
      value: 'step_son',
      label: 'Stepson',
      inverseLabel: 'Step-parent',
      category: 'Step and adoptive family',
      description: 'Step-family connection.',
    ),
    FamilyRelationshipOption(
      value: 'step_daughter',
      label: 'Stepdaughter',
      inverseLabel: 'Step-parent',
      category: 'Step and adoptive family',
      description: 'Step-family connection.',
    ),
    FamilyRelationshipOption(
      value: 'step_child',
      label: 'Stepchild',
      inverseLabel: 'Step-parent',
      category: 'Step and adoptive family',
      description: 'Step-family connection.',
    ),
    FamilyRelationshipOption(
      value: 'adoptive_father',
      label: 'Adoptive father',
      inverseLabel: 'Adopted child',
      category: 'Step and adoptive family',
      description: 'Adoptive family connection.',
    ),
    FamilyRelationshipOption(
      value: 'adoptive_mother',
      label: 'Adoptive mother',
      inverseLabel: 'Adopted child',
      category: 'Step and adoptive family',
      description: 'Adoptive family connection.',
    ),
    FamilyRelationshipOption(
      value: 'adoptive_parent',
      label: 'Adoptive parent',
      inverseLabel: 'Adopted child',
      category: 'Step and adoptive family',
      description: 'Adoptive family connection.',
    ),
    FamilyRelationshipOption(
      value: 'adopted_son',
      label: 'Adopted son',
      inverseLabel: 'Adoptive parent',
      category: 'Step and adoptive family',
      description: 'Adoptive family connection.',
    ),
    FamilyRelationshipOption(
      value: 'adopted_daughter',
      label: 'Adopted daughter',
      inverseLabel: 'Adoptive parent',
      category: 'Step and adoptive family',
      description: 'Adoptive family connection.',
    ),
    FamilyRelationshipOption(
      value: 'adopted_child',
      label: 'Adopted child',
      inverseLabel: 'Adoptive parent',
      category: 'Step and adoptive family',
      description: 'Adoptive family connection.',
    ),
    FamilyRelationshipOption(
      value: 'guardian',
      label: 'Guardian',
      inverseLabel: 'Ward',
      category: 'Care relationship',
      description: 'Guardian or care relationship.',
    ),
    FamilyRelationshipOption(
      value: 'ward',
      label: 'Ward',
      inverseLabel: 'Guardian',
      category: 'Care relationship',
      description: 'Guardian or care relationship.',
    ),
    FamilyRelationshipOption(
      value: 'godfather',
      label: 'Godfather',
      inverseLabel: 'Godchild',
      category: 'Spiritual/church family',
      description: 'Spiritual family connection.',
    ),
    FamilyRelationshipOption(
      value: 'godmother',
      label: 'Godmother',
      inverseLabel: 'Godchild',
      category: 'Spiritual/church family',
      description: 'Spiritual family connection.',
    ),
    FamilyRelationshipOption(
      value: 'godparent',
      label: 'Godparent',
      inverseLabel: 'Godchild',
      category: 'Spiritual/church family',
      description: 'Spiritual family connection.',
    ),
    FamilyRelationshipOption(
      value: 'godson',
      label: 'Godson',
      inverseLabel: 'Godparent',
      category: 'Spiritual/church family',
      description: 'Spiritual family connection.',
    ),
    FamilyRelationshipOption(
      value: 'goddaughter',
      label: 'Goddaughter',
      inverseLabel: 'Godparent',
      category: 'Spiritual/church family',
      description: 'Spiritual family connection.',
    ),
    FamilyRelationshipOption(
      value: 'godchild',
      label: 'Godchild',
      inverseLabel: 'Godparent',
      category: 'Spiritual/church family',
      description: 'Spiritual family connection.',
    ),
    FamilyRelationshipOption(
      value: 'spiritual_father',
      label: 'Spiritual father',
      inverseLabel: 'Spiritual child',
      category: 'Spiritual/church family',
      description: 'Church family mentorship connection.',
    ),
    FamilyRelationshipOption(
      value: 'spiritual_mother',
      label: 'Spiritual mother',
      inverseLabel: 'Spiritual child',
      category: 'Spiritual/church family',
      description: 'Church family mentorship connection.',
    ),
    FamilyRelationshipOption(
      value: 'spiritual_parent',
      label: 'Spiritual parent',
      inverseLabel: 'Spiritual child',
      category: 'Spiritual/church family',
      description: 'Church family mentorship connection.',
    ),
    FamilyRelationshipOption(
      value: 'mentor',
      label: 'Mentor',
      inverseLabel: 'Mentee',
      category: 'Spiritual/church family',
      description: 'Church family mentorship connection.',
    ),
    FamilyRelationshipOption(
      value: 'mentee',
      label: 'Mentee',
      inverseLabel: 'Mentor',
      category: 'Spiritual/church family',
      description: 'Church family mentorship connection.',
    ),
    FamilyRelationshipOption(
      value: 'other',
      label: 'Other family',
      inverseLabel: 'Other family',
      category: 'Other family',
      description: 'Use the note field to describe this connection clearly.',
    ),
  ];

  static FamilyRelationshipOption optionFor(String relationshipType) {
    return relationshipOptions.firstWhere(
      (option) => option.value == relationshipType,
      orElse: () => relationshipOptions.last,
    );
  }

  FamilyRelationshipOption get option => optionFor(relationshipType);

  String labelForRequester() {
    return option.label;
  }

  String labelForViewer(String? viewerUserId) {
    if (viewerUserId == null || viewerUserId == requesterId) {
      return option.label;
    }
    return option.inverseLabel;
  }

  String categoryForViewer(String? viewerUserId) {
    return option.category;
  }
}

class FamilyRelationshipOption {
  final String value;
  final String label;
  final String inverseLabel;
  final String category;
  final String description;

  const FamilyRelationshipOption({
    required this.value,
    required this.label,
    required this.inverseLabel,
    required this.category,
    required this.description,
  });

  String get menuLabel => '$category - $label';
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
