class PrivacySettings {
  final String
      profileVisibility; // 'public', 'church', 'connections', 'private'
  final bool showFamilyTree;
  final bool allowDiscovery;
  final String defaultPostVisibility; // 'public', 'church', 'connections'
  final List<String> blockedUserIds;

  PrivacySettings({
    this.profileVisibility = 'church',
    this.showFamilyTree = true,
    this.allowDiscovery = true,
    this.defaultPostVisibility = 'church',
    this.blockedUserIds = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'profileVisibility': profileVisibility,
      'showFamilyTree': showFamilyTree,
      'allowDiscovery': allowDiscovery,
      'defaultPostVisibility': defaultPostVisibility,
      'blockedUserIds': blockedUserIds,
    };
  }

  factory PrivacySettings.fromMap(Map<String, dynamic> map) {
    return PrivacySettings(
      profileVisibility: map['profileVisibility'] ?? 'church',
      showFamilyTree: map['showFamilyTree'] ?? true,
      allowDiscovery: map['allowDiscovery'] ?? true,
      defaultPostVisibility: map['defaultPostVisibility'] ?? 'church',
      blockedUserIds: List<String>.from(map['blockedUserIds'] ?? []),
    );
  }
}
