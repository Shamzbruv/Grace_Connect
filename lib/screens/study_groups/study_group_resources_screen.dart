import 'package:flutter/material.dart';

import '../../models/study_group_model.dart';
import '../../models/study_group_resource.dart';
import '../../services/study_group_resource_service.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_scaffold.dart';

class StudyGroupResourcesScreen extends StatelessWidget {
  final StudyGroup group;
  const StudyGroupResourcesScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final service = StudyGroupResourceService();
    return AppScaffold(
      title: 'Resources',
      body: FutureBuilder<List<StudyGroupResource>>(
        future: service.fetchResources(group.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final resources = snapshot.data ?? const [];
          if (resources.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'No study resources have been added yet.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: resources.length,
            itemBuilder: (context, index) {
              final resource = resources[index];
              return AppCard(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.attach_file_outlined),
                  title: Text(resource.title),
                  subtitle: Text(resource.category),
                  trailing: const Icon(Icons.chevron_right),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
