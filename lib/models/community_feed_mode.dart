enum CommunityFeedMode {
  church,
  following,
  discover,
}

extension CommunityFeedModeLabel on CommunityFeedMode {
  String get storageValue {
    return switch (this) {
      CommunityFeedMode.church => 'church',
      CommunityFeedMode.following => 'following',
      CommunityFeedMode.discover => 'discover',
    };
  }

  String get label {
    return switch (this) {
      CommunityFeedMode.church => 'My Church',
      CommunityFeedMode.following => 'Following',
      CommunityFeedMode.discover => 'Discover',
    };
  }
}
