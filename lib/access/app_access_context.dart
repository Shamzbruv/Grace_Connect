import '../services/church_subscription_service.dart';
import '../services/membership_service.dart';
import 'app_feature.dart';

class AppAccessContext {
  const AppAccessContext({
    required this.membership,
    this.subscription,
  });

  final MembershipContext membership;
  final ChurchSubscriptionContext? subscription;

  bool get hasUsableAccount =>
      membership.authenticated &&
      membership.hasProfile &&
      !membership.isAccountRestricted &&
      !membership.hasLoadError;

  bool get hasActiveChurchMembership => membership.hasActiveMembership;

  bool get hasActiveChurchSubscription =>
      hasActiveChurchMembership && subscription?.isActive == true;

  bool get hasKnownInactiveSubscription =>
      hasActiveChurchMembership &&
      subscription != null &&
      !subscription!.isActive;

  String? get churchId => membership.churchId;

  String? get churchName => membership.churchName;

  bool canUse(AppFeature feature) {
    if (!hasUsableAccount) return false;

    switch (feature) {
      case AppFeature.appShell:
      case AppFeature.communityRead:
      case AppFeature.communityPost:
      case AppFeature.communityInteract:
      case AppFeature.socialProfile:
      case AppFeature.socialFollowing:
      case AppFeature.publicChurchDirectory:
      case AppFeature.publicEvents:
      case AppFeature.eventRsvp:
      case AppFeature.bibleReading:
      case AppFeature.dailyWord:
      case AppFeature.notifications:
      case AppFeature.savedItems:
      case AppFeature.graceCircles:
      case AppFeature.graceRooms:
      case AppFeature.socialConnectionRequests:
      case AppFeature.directMessages:
      case AppFeature.churchTransfer:
      case AppFeature.churchPublicPage:
        return true;

      case AppFeature.churchHome:
      case AppFeature.churchTestimonies:
        return hasActiveChurchMembership;

      case AppFeature.memberDirectory:
      case AppFeature.attendance:
      case AppFeature.announcements:
      case AppFeature.ministryManagement:
      case AppFeature.studyGroups:
      case AppFeature.privatePrayerCare:
      case AppFeature.counseling:
      case AppFeature.scheduling:
      case AppFeature.roleManagement:
      case AppFeature.churchFinance:
      case AppFeature.churchAnalytics:
      case AppFeature.liveManagement:
        return hasActiveChurchSubscription;
    }
  }

  String unavailableMessageFor(AppFeature feature) {
    if (!hasActiveChurchMembership) {
      return '${feature.label} is connected to a church workspace. You can keep using Community, Bible, public events, Grace Rooms, Grace Circles, Saved, and church discovery while you connect with a church.';
    }

    if (!hasActiveChurchSubscription) {
      final name = churchName?.trim().isNotEmpty == true
          ? churchName!.trim()
          : 'your church';
      return '$name does not currently have an active Grace Connect subscription. Community, public events, Bible, Grace Rooms, Grace Circles, Saved, profile, notifications, and church transfer remain available, but church workspace tools are paused.';
    }

    return '${feature.label} is not available for this account right now.';
  }
}
