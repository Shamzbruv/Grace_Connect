import 'user_profile.dart';

class SocialProfile {
  const SocialProfile({
    required this.userId,
    required this.displayName,
    this.bio = '',
    this.avatarUrl = '',
    this.churchId = '',
    this.churchName = '',
    this.visibility = 'public',
    this.searchable = true,
    this.acceptsMessages = true,
    this.followerCount = 0,
    this.followingCount = 0,
    this.updatedAt,
  });

  final String userId;
  final String displayName;
  final String bio;
  final String avatarUrl;
  final String churchId;
  final String churchName;
  final String visibility;
  final bool searchable;
  final bool acceptsMessages;
  final int followerCount;
  final int followingCount;
  final DateTime? updatedAt;

  bool get isPublic => visibility != 'private';

  factory SocialProfile.fromMap(Map<String, dynamic> data) {
    return SocialProfile(
      userId: data['user_id']?.toString() ??
          data['uid']?.toString() ??
          data['id']?.toString() ??
          '',
      displayName: data['display_name']?.toString() ??
          data['displayName']?.toString() ??
          data['fullName']?.toString() ??
          'Grace Connect Member',
      bio: data['public_bio']?.toString() ?? data['bio']?.toString() ?? '',
      avatarUrl:
          data['avatar_url']?.toString() ?? data['photoUrl']?.toString() ?? '',
      churchId:
          data['church_id']?.toString() ?? data['placeId']?.toString() ?? '',
      churchName: data['church_name']?.toString() ??
          data['placeName']?.toString() ??
          '',
      visibility: data['visibility']?.toString() ??
          (data['isProfilePrivate'] == true ? 'private' : 'public'),
      searchable: data['searchable'] != false,
      acceptsMessages:
          data['accepts_messages'] != false && data['allowMessages'] != false,
      followerCount: _intValue(data['follower_count']),
      followingCount: _intValue(data['following_count']),
      updatedAt: _dateValue(data['updated_at']),
    );
  }

  factory SocialProfile.fromUserProfile(UserProfile profile) {
    return SocialProfile(
      userId: profile.uid,
      displayName: profile.displayName?.trim().isNotEmpty == true
          ? profile.displayName!.trim()
          : profile.fullName.trim().isNotEmpty
              ? profile.fullName.trim()
              : 'Grace Connect Member',
      bio: profile.bio,
      avatarUrl: profile.photoUrl,
      churchId: profile.placeId,
      churchName: profile.placeName,
      visibility: profile.isProfilePrivate ? 'private' : 'public',
      acceptsMessages: profile.allowMessages,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'user_id': userId,
      'display_name': displayName,
      'public_bio': bio,
      'avatar_url': avatarUrl,
      'church_id': churchId.isEmpty ? null : churchId,
      'church_name': churchName,
      'visibility': visibility,
      'searchable': searchable,
      'accepts_messages': acceptsMessages,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  SocialProfile copyWith({
    String? displayName,
    String? bio,
    String? avatarUrl,
    String? churchId,
    String? churchName,
    String? visibility,
    bool? searchable,
    bool? acceptsMessages,
  }) {
    return SocialProfile(
      userId: userId,
      displayName: displayName ?? this.displayName,
      bio: bio ?? this.bio,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      churchId: churchId ?? this.churchId,
      churchName: churchName ?? this.churchName,
      visibility: visibility ?? this.visibility,
      searchable: searchable ?? this.searchable,
      acceptsMessages: acceptsMessages ?? this.acceptsMessages,
      followerCount: followerCount,
      followingCount: followingCount,
      updatedAt: updatedAt,
    );
  }

  static int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _dateValue(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value)?.toLocal();
    return null;
  }
}
