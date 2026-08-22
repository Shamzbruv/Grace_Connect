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

/// Resolves the member's initial feed without silently falling back to a
/// church-only view. Discover is the product default; a valid saved choice is
/// still respected after the member deliberately changes it.
String resolveInitialCommunityFeedScope({
  String? savedScope,
  List<String>? customChurchIds,
  bool forceDiscover = false,
}) {
  if (forceDiscover) return CommunityFeedMode.discover.storageValue;

  final normalized = savedScope == 'all' ? 'discover' : savedScope;
  if (normalized == 'custom') {
    return customChurchIds?.isNotEmpty == true
        ? 'custom'
        : CommunityFeedMode.discover.storageValue;
  }
  if (normalized == CommunityFeedMode.church.storageValue ||
      normalized == CommunityFeedMode.following.storageValue ||
      normalized == CommunityFeedMode.discover.storageValue) {
    return normalized!;
  }
  return CommunityFeedMode.discover.storageValue;
}
