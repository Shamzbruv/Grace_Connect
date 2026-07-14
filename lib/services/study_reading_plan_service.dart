import '../models/study_reading_assignment.dart';
import '../models/study_reading_plan.dart';
import 'study_group_service.dart';

class StudyReadingPlanService {
  final StudyGroupService _groups = StudyGroupService();

  Future<List<StudyReadingPlan>> fetchPlans(String groupId) {
    return _groups.fetchReadingPlans(groupId);
  }

  Future<List<StudyReadingAssignment>> fetchAssignments(String planId) {
    return _groups.fetchReadingAssignments(planId);
  }

  Future<String> createPlan({
    required String groupId,
    required String title,
    String description = '',
    String translation = 'KJV',
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return _groups.createReadingPlan(
      groupId: groupId,
      title: title,
      description: description,
      translation: translation,
      startDate: startDate,
      endDate: endDate,
    );
  }

  Future<void> markComplete(String assignmentId, {String reflection = ''}) {
    return _groups.markAssignmentComplete(
      assignmentId,
      reflection: reflection,
    );
  }
}
