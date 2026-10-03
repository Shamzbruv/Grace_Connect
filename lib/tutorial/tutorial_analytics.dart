import '../services/analytics_service.dart';
import 'tutorial_definition.dart';

class TutorialAnalytics {
  void event(String name,
      {TutorialDefinition? definition, int? step, int? count}) {
    // All labels originate in the fixed registry. No account, church or content data.
    Analytics.log(name, {
      if (definition != null) 'screen_id': definition.screenId,
      if (definition != null) 'tutorial_version': definition.version,
      if (step != null) 'step_number': step,
      if (count != null) 'step_count': count,
    });
  }
}
