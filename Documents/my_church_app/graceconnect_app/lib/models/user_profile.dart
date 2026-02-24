import 'package:cloud_firestore/cloud_firestore.dart';
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

  // Social Links
  final String? instagramLink;
  final String? facebookLink;
  final String? whatsappLink;

  // Settings
  final bool isProfilePrivate;
  final bool allowMessages;
  final bool notifyAttendance;

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
    this.instagramLink,
    this.facebookLink,
    this.whatsappLink,
    this.isProfilePrivate = false,
    this.allowMessages = true,
    this.notifyAttendance = true,
    this.fatherId,
    this.motherId,
    this.spouseId,
    this.childrenIds = const [],
    this.isDeveloper = false,
    this.accountState = 'active',
  }) {
    // Initialize capabilities based on roles
    capabilities = UserCapabilities.fromRoleIds(roles);
  }

  /// Parses a date from either a Firestore Timestamp or an ISO 8601 string (Supabase).
  static DateTime _parseDate(dynamic value) {
    if (value == null) return DateTime.now();
    // Firestore Timestamp
    if (value is Timestamp) return value.toDate();
    // ISO string from Supabase
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    return DateTime.now();
  }

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserProfile.fromMap(data);
  }

  factory UserProfile.fromMap(Map<String, dynamic> data) {
    return UserProfile(
      uid: data['uid'] ?? '',
      email: data['email'] ?? '',
      fullName: data['fullName'] ?? '',
      displayName: data['displayName'],
      phoneNumber: data['phone'] ?? '',
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
      instagramLink: data['instagramLink'],
      facebookLink: data['facebookLink'],
      whatsappLink: data['whatsappLink'],
      isProfilePrivate: data['isProfilePrivate'] ?? false,
      allowMessages: data['allowMessages'] ?? true,
      notifyAttendance: data['notifyAttendance'] ?? true,
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
      'instagramLink': instagramLink,
      'facebookLink': facebookLink,
      'whatsappLink': whatsappLink,
      'isProfilePrivate': isProfilePrivate,
      'allowMessages': allowMessages,
      'notifyAttendance': notifyAttendance,
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
    String? instagramLink,
    String? facebookLink,
    String? whatsappLink,
    bool? isProfilePrivate,
    bool? allowMessages,
    bool? notifyAttendance,
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
      instagramLink: instagramLink ?? this.instagramLink,
      facebookLink: facebookLink ?? this.facebookLink,
      whatsappLink: whatsappLink ?? this.whatsappLink,
      isProfilePrivate: isProfilePrivate ?? this.isProfilePrivate,
      allowMessages: allowMessages ?? this.allowMessages,
      notifyAttendance: notifyAttendance ?? this.notifyAttendance,
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

  bool get isPrayerWarrior => roles.contains('Prayer Warrior');
  bool get isActingPastor => roles.contains('Acting Pastor');
  bool get isAssistantPastor => roles.contains('Assistant Pastor');

  String get churchId => placeId;
}
