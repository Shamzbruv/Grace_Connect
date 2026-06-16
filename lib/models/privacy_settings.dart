class PrivacySettings {
  final String
      profileVisibility; // 'public', 'church', 'connections', 'private'
  final bool showFamilyTree;
  final bool showFamilyRelationshipTypes;
  final bool showContactInfo;
  final String contactInfoVisibility; // 'everyone', 'church', 'private'
  final bool allowFamilyLinkRequests;
  final String familyTreeVisibility; // 'church', 'family', 'private'
  final bool allowDiscovery;
  final String defaultPostVisibility; // 'public', 'church', 'connections'
  final List<String> blockedUserIds;

  PrivacySettings({
    this.profileVisibility = 'church',
    this.showFamilyTree = true,
    this.showFamilyRelationshipTypes = true,
    this.showContactInfo = true,
    this.contactInfoVisibility = 'church',
    this.allowFamilyLinkRequests = true,
    this.familyTreeVisibility = 'church',
    this.allowDiscovery = true,
    this.defaultPostVisibility = 'church',
    this.blockedUserIds = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'profileVisibility': profileVisibility,
      'showFamilyTree': showFamilyTree,
      'showFamilyRelationshipTypes': showFamilyRelationshipTypes,
      'showContactInfo': showContactInfo,
      'contactInfoVisibility': contactInfoVisibility,
      'allowFamilyLinkRequests': allowFamilyLinkRequests,
      'familyTreeVisibility': familyTreeVisibility,
      'allowDiscovery': allowDiscovery,
      'defaultPostVisibility': defaultPostVisibility,
      'blockedUserIds': blockedUserIds,
    };
  }

  factory PrivacySettings.fromMap(Map<String, dynamic> map) {
    return PrivacySettings(
      profileVisibility: map['profileVisibility'] ?? 'church',
      showFamilyTree: map['showFamilyTree'] ?? true,
      showFamilyRelationshipTypes: map['showFamilyRelationshipTypes'] ?? true,
      showContactInfo: map['showContactInfo'] ?? true,
      contactInfoVisibility: map['contactInfoVisibility'] ??
          (map['showContactInfo'] == false ? 'private' : 'church'),
      allowFamilyLinkRequests: map['allowFamilyLinkRequests'] ?? true,
      familyTreeVisibility: map['familyTreeVisibility'] ?? 'church',
      allowDiscovery: map['allowDiscovery'] ?? true,
      defaultPostVisibility: map['defaultPostVisibility'] ?? 'church',
      blockedUserIds: List<String>.from(map['blockedUserIds'] ?? []),
    );
  }
}
