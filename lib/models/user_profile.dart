import 'role_system/permission_flags.dart';

class UserProfile {
  final String uid;
  final String email;
  final String fullName;
  final String? displayName;
  final String phoneNumber;
  final String address;
  final String parish;
  final String city;
  final String placeId;
  final String placeName;
  final List<String> roles;
  final DateTime joinDate;
  final String photoUrl;
  final String coverPhotoUrl;
  final String bio;
  final List<String> appPrivileges;
  final DateTime? dateOfBirth;
  final String gender;
  final String occupation;
  final String emergencyContactName;
  final String emergencyContactPhone;

  // Social Links
  final String? instagramLink;
  final String? facebookLink;
  final String? whatsappLink;

  // Pastor public profile
  final String pastoralTitle;
  final String pastorPublicBio;
  final DateTime? ordinationDate;
  final String publicEmail;
  final String publicPhone;
  final bool showPastorPublicContact;

  // Settings
  final bool isProfilePrivate;
  final bool allowMessages;
  final bool notifyAttendance;
  final bool notifyDailyMotivation;
  final bool notifyDailyQuiz;
  final bool showContactInfo;
  final String contactInfoVisibility;
  final bool showFamilyTree;
  final bool showFamilyRelationshipTypes;
  final bool allowFamilyLinkRequests;
  final String familyTreeVisibility;

  // Family & Dev
  final String? fatherId;
  final String? motherId;
  final String? spouseId;
  final List<String> childrenIds;
  final bool isDeveloper;
  final String accountState;

  // --- CAPABILITIES (Computed) ---
  late final UserCapabilities capabilities;

  UserProfile({
    required this.uid,
    required this.email,
    required this.fullName,
    this.displayName,
    required this.phoneNumber,
    this.address = '',
    this.parish = '',
    this.city = '',
    required this.placeId,
    required this.placeName,
    required this.roles,
    required this.joinDate,
    this.photoUrl = '',
    this.coverPhotoUrl = '',
    this.bio = '',
    this.appPrivileges = const [],
    this.dateOfBirth,
    this.gender = '',
    this.occupation = '',
    this.emergencyContactName = '',
    this.emergencyContactPhone = '',
    this.instagramLink,
    this.facebookLink,
    this.whatsappLink,
    this.pastoralTitle = '',
    this.pastorPublicBio = '',
    this.ordinationDate,
    this.publicEmail = '',
    this.publicPhone = '',
    this.showPastorPublicContact = true,
    this.isProfilePrivate = false,
    this.allowMessages = true,
    this.notifyAttendance = true,
    this.notifyDailyMotivation = true,
    this.notifyDailyQuiz = true,
    this.showContactInfo = true,
    this.contactInfoVisibility = 'church',
    this.showFamilyTree = true,
    this.showFamilyRelationshipTypes = true,
    this.allowFamilyLinkRequests = true,
    this.familyTreeVisibility = 'church',
    this.fatherId,
    this.motherId,
    this.spouseId,
    this.childrenIds = const [],
    this.isDeveloper = false,
    this.accountState = 'active',
  }) {
    // Initialize capabilities based on roles
    capabilities = UserCapabilities.fromRoleIdsAndPrivileges(
      roles,
      appPrivileges,
    );
  }

  /// Parses a date from either a Firestore Timestamp or an ISO 8601 string (Supabase).
  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    // ISO string from Supabase
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  static DateTime? _parseOptionalDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  factory UserProfile.fromMap(Map<String, dynamic> data) {
    return UserProfile(
      uid: data['uid'] ?? data['id'] ?? '',
      email: data['email'] ?? '',
      fullName: data['fullName'] ?? '',
      displayName: data['displayName'],
      phoneNumber: data['phone'] ?? data['phoneNumber'] ?? '',
      address: data['address'] ?? '',
      parish: data['parish'] ?? '',
      city: data['city'] ?? '',
      placeId: data['placeId'] ?? '',
      placeName: data['placeName'] ?? '',
      roles: List<String>.from(data['roles'] ?? ['member']),
      joinDate: _parseDate(data['joinDate']),
      photoUrl: data['photoUrl'] ?? '',
      coverPhotoUrl: data['coverPhotoUrl'] ?? '',
      bio: data['bio'] ?? '',
      appPrivileges: List<String>.from(data['appPrivileges'] ?? const []),
      dateOfBirth: _parseOptionalDate(data['dateOfBirth']),
      gender: data['gender'] ?? '',
      occupation: data['occupation'] ?? '',
      emergencyContactName: data['emergencyContactName'] ?? '',
      emergencyContactPhone: data['emergencyContactPhone'] ?? '',
      instagramLink: data['instagramLink'],
      facebookLink: data['facebookLink'],
      whatsappLink: data['whatsappLink'],
      pastoralTitle: data['pastoralTitle'] ?? '',
      pastorPublicBio: data['pastorPublicBio'] ?? '',
      ordinationDate: _parseOptionalDate(data['ordinationDate']),
      publicEmail: data['publicEmail'] ?? '',
      publicPhone: data['publicPhone'] ?? '',
      showPastorPublicContact: data['showPastorPublicContact'] ?? true,
      isProfilePrivate: data['isProfilePrivate'] ?? false,
      allowMessages: data['allowMessages'] ?? true,
      notifyAttendance: data['notifyAttendance'] ?? true,
      notifyDailyMotivation: data['notifyDailyMotivation'] ?? true,
      notifyDailyQuiz: data['notifyDailyQuiz'] ?? true,
      showContactInfo: data['showContactInfo'] ?? true,
      contactInfoVisibility: data['contactInfoVisibility'] ??
          (data['showContactInfo'] == false ? 'private' : 'church'),
      showFamilyTree: data['showFamilyTree'] ?? true,
      showFamilyRelationshipTypes: data['showFamilyRelationshipTypes'] ?? true,
      allowFamilyLinkRequests: data['allowFamilyLinkRequests'] ?? true,
      familyTreeVisibility: data['familyTreeVisibility'] ?? 'church',
      fatherId: data['fatherId'],
      motherId: data['motherId'],
      spouseId: data['spouseId'],
      childrenIds: List<String>.from(data['childrenIds'] ?? []),
      isDeveloper: data['isDeveloper'] ?? false,
      accountState: data['accountState'] ?? 'active',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': uid,
      'uid': uid,
      'email': email,
      'fullName': fullName,
      'displayName': displayName,
      'phone': phoneNumber,
      'address': address,
      'parish': parish,
      'city': city,
      'placeId': placeId,
      'placeName': placeName,
      'roles': roles,
      'joinDate': joinDate.toIso8601String(),
      'photoUrl': photoUrl,
      'coverPhotoUrl': coverPhotoUrl,
      'bio': bio,
      'appPrivileges': appPrivileges,
      'dateOfBirth': dateOfBirth?.toIso8601String(),
      'gender': gender,
      'occupation': occupation,
      'emergencyContactName': emergencyContactName,
      'emergencyContactPhone': emergencyContactPhone,
      'instagramLink': instagramLink,
      'facebookLink': facebookLink,
      'whatsappLink': whatsappLink,
      'pastoralTitle': pastoralTitle,
      'pastorPublicBio': pastorPublicBio,
      'ordinationDate': ordinationDate?.toIso8601String(),
      'publicEmail': publicEmail,
      'publicPhone': publicPhone,
      'showPastorPublicContact': showPastorPublicContact,
      'isProfilePrivate': isProfilePrivate,
      'allowMessages': allowMessages,
      'notifyAttendance': notifyAttendance,
      'notifyDailyMotivation': notifyDailyMotivation,
      'notifyDailyQuiz': notifyDailyQuiz,
      'showContactInfo': showContactInfo,
      'contactInfoVisibility': contactInfoVisibility,
      'showFamilyTree': showFamilyTree,
      'showFamilyRelationshipTypes': showFamilyRelationshipTypes,
      'allowFamilyLinkRequests': allowFamilyLinkRequests,
      'familyTreeVisibility': familyTreeVisibility,
      'fatherId': fatherId,
      'motherId': motherId,
      'spouseId': spouseId,
      'childrenIds': childrenIds,
      'isDeveloper': isDeveloper,
      'accountState': accountState,
    };
  }

  // Alias for legacy support
  String get phone => phoneNumber;

  UserProfile copyWith({
    String? uid,
    String? email,
    String? fullName,
    String? displayName,
    String? phoneNumber,
    String? address,
    String? parish,
    String? city,
    String? placeId,
    String? placeName,
    List<String>? roles,
    DateTime? joinDate,
    String? photoUrl,
    String? coverPhotoUrl,
    String? bio,
    List<String>? appPrivileges,
    DateTime? dateOfBirth,
    String? gender,
    String? occupation,
    String? emergencyContactName,
    String? emergencyContactPhone,
    String? instagramLink,
    String? facebookLink,
    String? whatsappLink,
    String? pastoralTitle,
    String? pastorPublicBio,
    DateTime? ordinationDate,
    String? publicEmail,
    String? publicPhone,
    bool? showPastorPublicContact,
    bool? isProfilePrivate,
    bool? allowMessages,
    bool? notifyAttendance,
    bool? notifyDailyMotivation,
    bool? notifyDailyQuiz,
    bool? showContactInfo,
    String? contactInfoVisibility,
    bool? showFamilyTree,
    bool? showFamilyRelationshipTypes,
    bool? allowFamilyLinkRequests,
    String? familyTreeVisibility,
    String? fatherId,
    String? motherId,
    String? spouseId,
    List<String>? childrenIds,
    bool? isDeveloper,
    String? accountState,
  }) {
    return UserProfile(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      displayName: displayName ?? this.displayName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      address: address ?? this.address,
      parish: parish ?? this.parish,
      city: city ?? this.city,
      placeId: placeId ?? this.placeId,
      placeName: placeName ?? this.placeName,
      roles: roles ?? this.roles,
      joinDate: joinDate ?? this.joinDate,
      photoUrl: photoUrl ?? this.photoUrl,
      coverPhotoUrl: coverPhotoUrl ?? this.coverPhotoUrl,
      bio: bio ?? this.bio,
      appPrivileges: appPrivileges ?? this.appPrivileges,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      gender: gender ?? this.gender,
      occupation: occupation ?? this.occupation,
      emergencyContactName: emergencyContactName ?? this.emergencyContactName,
      emergencyContactPhone:
          emergencyContactPhone ?? this.emergencyContactPhone,
      instagramLink: instagramLink ?? this.instagramLink,
      facebookLink: facebookLink ?? this.facebookLink,
      whatsappLink: whatsappLink ?? this.whatsappLink,
      pastoralTitle: pastoralTitle ?? this.pastoralTitle,
      pastorPublicBio: pastorPublicBio ?? this.pastorPublicBio,
      ordinationDate: ordinationDate ?? this.ordinationDate,
      publicEmail: publicEmail ?? this.publicEmail,
      publicPhone: publicPhone ?? this.publicPhone,
      showPastorPublicContact:
          showPastorPublicContact ?? this.showPastorPublicContact,
      isProfilePrivate: isProfilePrivate ?? this.isProfilePrivate,
      allowMessages: allowMessages ?? this.allowMessages,
      notifyAttendance: notifyAttendance ?? this.notifyAttendance,
      notifyDailyMotivation:
          notifyDailyMotivation ?? this.notifyDailyMotivation,
      notifyDailyQuiz: notifyDailyQuiz ?? this.notifyDailyQuiz,
      showContactInfo: showContactInfo ?? this.showContactInfo,
      contactInfoVisibility:
          contactInfoVisibility ?? this.contactInfoVisibility,
      showFamilyTree: showFamilyTree ?? this.showFamilyTree,
      showFamilyRelationshipTypes:
          showFamilyRelationshipTypes ?? this.showFamilyRelationshipTypes,
      allowFamilyLinkRequests:
          allowFamilyLinkRequests ?? this.allowFamilyLinkRequests,
      familyTreeVisibility: familyTreeVisibility ?? this.familyTreeVisibility,
      fatherId: fatherId ?? this.fatherId,
      motherId: motherId ?? this.motherId,
      spouseId: spouseId ?? this.spouseId,
      childrenIds: childrenIds ?? this.childrenIds,
      isDeveloper: isDeveloper ?? this.isDeveloper,
      accountState: accountState ?? this.accountState,
    );
  }

  // --- LEGACY HELPERS (Mapped to Capabilities where possible) ---
  // Keeping these for backward compatibility if code checks 'isPastor' elsewhere
  // But ideally we migrate to capabilities.

  bool get isPastor => capabilities.canAssignPrayers;
  bool get isAdmin => capabilities.canManageMembersBasic;
  bool get isStaff =>
      capabilities.canCreateEvents; // Very rough approximation for 'Staff'

  bool get canAssignPrayers => capabilities.canAssignPrayers;
  bool get canViewFinance => capabilities.canViewFinance;
  bool get canManageRoles => capabilities.canManageRoles;

  bool canShowContactInfoTo({required bool isSameChurch}) {
    if (!showContactInfo || isProfilePrivate) return false;
    return switch (contactInfoVisibility) {
      'everyone' => true,
      'church' => isSameChurch,
      'private' => false,
      _ => isSameChurch,
    };
  }

  bool get isPrayerWarrior => _normalizedRoles.any((role) =>
      role == 'prayer_warrior' ||
      role == 'intercessor' ||
      role == 'prayer_team_intercessor');
  bool get hasPastoralRole => _normalizedRoles.any((role) =>
      role == 'pastor' ||
      role == 'senior_pastor' ||
      role == 'assistant_pastor' ||
      role == 'acting_pastor');
  bool get isActingPastor => _normalizedRoles.contains('acting_pastor');
  bool get isAssistantPastor => _normalizedRoles.contains('assistant_pastor');

  String get churchId => placeId;

  List<String> get _normalizedRoles => roles.map(_normalizeRole).toList();

  static String _normalizeRole(String role) {
    return role
        .trim()
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
  }
}
