import 'package:flutter/material.dart';

import '../../models/study_group_model.dart';
import '../../widgets/ui/app_scaffold.dart';

class StudyGroupInvitationScreen extends StatelessWidget {
  final StudyGroup group;
  const StudyGroupInvitationScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Invitations',
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(
            'Invitations for ${group.name} will appear here as church member selection is connected.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
