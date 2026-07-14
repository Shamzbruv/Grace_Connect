enum CommunityFeedMode {
  church,
  following,
  discover,
  circle,
}

extension CommunityFeedModeLabel on CommunityFeedMode {
  String get storageValue {
    return switch (this) {
      CommunityFeedMode.church => 'church',
      CommunityFeedMode.following => 'following',
      CommunityFeedMode.discover => 'discover',
      CommunityFeedMode.circle => 'circle',
    };
  }

  String get label {
    return switch (this) {
      CommunityFeedMode.church => 'My Church',
      CommunityFeedMode.following => 'Following',
      CommunityFeedMode.discover => 'Discover',
      CommunityFeedMode.circle => 'Circle',
    };
  }
}
