import '../models/study_group_announcement.dart';
import 'study_group_service.dart';

class StudyGroupAnnouncementService {
  final StudyGroupService _groups = StudyGroupService();

  Future<List<StudyGroupAnnouncement>> fetchAnnouncements(String groupId) {
    return _groups.fetchAnnouncements(groupId);
  }
}
