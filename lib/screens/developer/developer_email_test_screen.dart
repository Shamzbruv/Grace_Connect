import 'package:flutter/material.dart';
import '../../services/email_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_text_field.dart';
import '../../widgets/ui/app_button.dart';

class DeveloperEmailTestScreen extends StatefulWidget {
  const DeveloperEmailTestScreen({super.key});

  @override
  State<DeveloperEmailTestScreen> createState() =>
      _DeveloperEmailTestScreenState();
}

class _DeveloperEmailTestScreenState extends State<DeveloperEmailTestScreen> {
  final _emailController = TextEditingController();
  final _subjectController =
      TextEditingController(text: 'Test from Grace Connect');
  final _bodyController = TextEditingController(
      text: '<h1>Hello!</h1><p>This is a test email.</p>');

  final _emailService = EmailService();
  bool _isLoading = false;
  String? _statusMessage;

  Future<void> _sendTestEmail() async {
    if (_emailController.text.isEmpty) return;

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      await _emailService.sendEmail(
        to: [_emailController.text.trim()],
        subject: _subjectController.text,
        htmlBody: _bodyController.text,
      );

      if (mounted) {
        setState(() {
          _statusMessage =
              'Email sent successfully. Check your inbox (and spam).';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Email sent through the Grace Connect mailer.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Email Extension Test',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Grace Connect Email Test',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'This sends a branded test through the authenticated Grace Connect server mailer.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            AppTextField(
              controller: _emailController,
              label: 'To Email',
              hint: 'recipient@example.com',
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _subjectController,
              label: 'Subject',
            ),
            const SizedBox(height: 16),
            AppTextField(
              controller: _bodyController,
              label: 'HTML Body',
              maxLines: 5,
            ),
            const SizedBox(height: 24),
            AppButton(
              text: 'Send Test Email',
              isLoading: _isLoading,
              onPressed: _sendTestEmail,
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Text(
                  _statusMessage!,
                  style: const TextStyle(color: AppColors.primary),
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }
}
