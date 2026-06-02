import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_scaffold.dart';
import 'counseling_form_screen.dart';
import 'counseling_history_screen.dart';
import 'counseling_requests_screen.dart';

class CounselingIntroScreen extends StatelessWidget {
  const CounselingIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final capabilities =
        context.watch<UserRoleProvider>().userProfile?.capabilities;
    final canAccessCareCases = capabilities?.canManageCareCases == true ||
        capabilities?.canViewAssignedCareCases == true;

    if (canAccessCareCases) {
      return const CounselingRequestsScreen();
    }

    return AppScaffold(
      title: 'Pastoral Care',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.favorite, size: 80, color: Colors.indigo),
            const SizedBox(height: 24),
            Text(
              'We Are Here For You',
              style: GoogleFonts.poppins(
                  fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              '"Carry each other’s burdens, and in this way you will fulfill the law of Christ." - Galatians 6:2',
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            AppCard(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.lock, color: Colors.green),
                    title: Text('Confidential',
                        style:
                            GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                        'Your request is secure and only seen by the pastoral care team.'),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.people, color: Colors.blue),
                    title: Text('Supportive',
                        style:
                            GoogleFonts.poppins(fontWeight: FontWeight.bold)),
                    subtitle: const Text(
                        'Whether you need spiritual guidance, marriage counseling, or just someone to listen.'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const CounselingFormScreen()),
                  );
                },
                icon: const Icon(Icons.edit_note),
                label: Text(
                  'Request Counseling',
                  style: GoogleFonts.poppins(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const CounselingHistoryScreen()),
                );
              },
              child: const Text('View My Previous Requests'),
            ),
          ],
        ),
      ),
    );
  }
}
