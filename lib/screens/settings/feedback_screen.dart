import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import '../../services/email_delivery_service.dart';
import '../../widgets/ui/app_button.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_feedback.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_text_field.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _feedbackController = TextEditingController();
  final _emailController = TextEditingController(); // Optional contact
  bool _isSubmitting = false;
  String _type = 'Bug Report'; // or 'Suggestion'

  @override
  void dispose() {
    _feedbackController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    final message = _feedbackController.text.trim();
    if (message.isEmpty) {
      AppFeedback.show(
        context,
        'Add a short description before submitting feedback.',
        type: AppFeedbackType.warning,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final user =
        Provider.of<UserRoleProvider>(context, listen: false).userProfile;
    final authUser = Supabase.instance.client.auth.currentUser;

    try {
      final response = await Supabase.instance.client.rpc(
        'submit_support_ticket',
        params: {
          'p_issue_type': _type,
          'p_app_section': 'Beta Feedback',
          'p_summary': _type,
          'p_description': message,
          'p_impact': _type == 'Bug Report' ? 'Medium' : 'Low',
          'p_device_info': {
            'contactEmail': _emailController.text.trim(),
            'platform': Theme.of(context).platform.toString(),
            'churchId': user?.placeId,
            'userId': user?.uid,
            'authEmail': authUser?.email,
          },
          'p_attachment_urls': <String>[],
        },
      );
      final ticketId = response is Map
          ? (response['id'] ?? response['ticketId'])?.toString()
          : null;
      final emailSent = ticketId == null
          ? false
          : await EmailDeliveryService().flushSupportTicketEmails(ticketId);

      if (mounted) {
        AppFeedback.show(
          context,
          emailSent
              ? 'Thank you. Your report was submitted and a confirmation email was sent.'
              : 'Thank you. Your report was submitted. The confirmation email is queued.',
          type: AppFeedbackType.success,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppFeedback.show(
          context,
          'Error sending feedback: $e',
          type: AppFeedbackType.error,
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Beta Feedback',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Help us improve Grace Connect!',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Found a bug or have a suggestion? Let us know below.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            AppCard(
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: _type,
                    items: ['Bug Report', 'Suggestion', 'Other']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (val) => setState(() => _type = val!),
                    decoration: const InputDecoration(
                      labelText: 'Feedback Type',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppTextField(
                    controller: _feedbackController,
                    label: 'Description',
                    hint: 'Describe the issue or idea...',
                    maxLines: 5,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppCard(
              child: AppTextField(
                controller: _emailController,
                label: 'Contact Email (Optional)',
                hint: 'If you want us to follow up',
                keyboardType: TextInputType.emailAddress,
              ),
            ),
            const SizedBox(height: 32),
            AppButton(
              text: 'Submit Feedback',
              onPressed: _submitFeedback,
              isLoading: _isSubmitting,
            ),
          ],
        ),
      ),
    );
  }
}
