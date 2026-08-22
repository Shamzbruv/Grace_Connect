import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/direct_message_service.dart';
import 'ui/app_feedback.dart';

Future<bool> showMessageRequestComposer(
  BuildContext context, {
  required UserProfile recipient,
  String initialMessage = '',
  DirectMessageService? messageService,
}) async {
  final service = messageService ?? DirectMessageService();
  final reasonController = TextEditingController();
  final messageController = TextEditingController(text: initialMessage.trim());
  var saving = false;
  String? validationMessage;

  final displayName = recipient.fullName.trim().isNotEmpty
      ? recipient.fullName.trim()
      : recipient.email.trim().isNotEmpty
          ? recipient.email.trim()
          : 'this person';

  final sent = await showDialog<bool>(
    context: context,
    barrierDismissible: !saving,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        Future<void> submit() async {
          final reason = reasonController.text.trim();
          final firstMessage = messageController.text.trim();
          if (reason.length < 3 || firstMessage.isEmpty) {
            setDialogState(() {
              validationMessage = reason.length < 3
                  ? 'Tell $displayName why you would like to message.'
                  : 'Write the first message you want delivered.';
            });
            return;
          }

          setDialogState(() {
            saving = true;
            validationMessage = null;
          });
          try {
            await service.sendMessageRequest(
              recipient: recipient,
              reason: reason,
              intendedMessage: firstMessage,
            );
            if (dialogContext.mounted) Navigator.pop(dialogContext, true);
          } catch (error) {
            if (!dialogContext.mounted) return;
            setDialogState(() {
              saving = false;
              validationMessage =
                  error.toString().replaceFirst('Exception: ', '');
            });
          }
        }

        return AlertDialog(
          title: const Text('Send a message request'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$displayName must approve before a private conversation can begin.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  enabled: !saving,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 500,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Why do you want to message?',
                    hintText: 'Introduce yourself and explain the reason.',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: messageController,
                  enabled: !saving,
                  minLines: 3,
                  maxLines: 7,
                  maxLength: 4000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'First message',
                    hintText: 'This is delivered only if they accept.',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'If declined, you cannot request this person again for 30 days. Bible Nudges remain separate and never bypass approval.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (validationMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    validationMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  saving ? null : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: saving ? null : submit,
              icon: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.outgoing_mail),
              label: Text(saving ? 'Sending…' : 'Send request'),
            ),
          ],
        );
      },
    ),
  );

  reasonController.dispose();
  messageController.dispose();

  if (sent == true && context.mounted) {
    AppFeedback.show(
      context,
      'Message request sent to $displayName.',
      type: AppFeedbackType.success,
    );
  }
  return sent ?? false;
}
