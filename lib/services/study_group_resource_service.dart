import '../models/study_group_resource.dart';
import 'study_group_service.dart';

class StudyGroupResourceService {
  final StudyGroupService _groups = StudyGroupService();

  Future<List<StudyGroupResource>> fetchResources(String groupId) {
    return _groups.fetchResources(groupId);
  }
}
