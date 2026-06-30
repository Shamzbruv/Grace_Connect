import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

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
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _attachments = [];
  bool _isSubmitting = false;
  String _type = 'Bug Report'; // or 'Suggestion'

  @override
  void dispose() {
    _feedbackController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final files = await _picker.pickMultiImage();
    if (files.isEmpty || !mounted) return;

    setState(() {
      final remainingSlots = 5 - _attachments.length;
      _attachments.addAll(files.take(remainingSlots));
    });
  }

  Future<Map<String, dynamic>> _getDeviceInfo({
    required String? contactEmail,
    required String? churchId,
    required String? userId,
    required String? authEmail,
  }) async {
    final platform = Theme.of(context).platform.toString();
    final packageInfo = await PackageInfo.fromPlatform();
    final deviceInfo = DeviceInfoPlugin();

    final details = <String, dynamic>{
      'contactEmail': contactEmail,
      'churchId': churchId,
      'userId': userId,
      'authEmail': authEmail,
      'platform': platform,
      'appVersion': packageInfo.version,
      'buildNumber': packageInfo.buildNumber,
      'source': 'Beta Feedback',
    };

    if (kIsWeb) {
      details.addAll({'os': 'Web', 'device': 'Browser'});
    } else if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      details.addAll({
        'os': 'Android',
        'version': androidInfo.version.release,
        'model': androidInfo.model,
        'brand': androidInfo.brand,
      });
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      details.addAll({
        'os': 'iOS',
        'version': iosInfo.systemVersion,
        'model': iosInfo.model,
        'name': iosInfo.name,
      });
    }

    return details;
  }

  Future<List<String>> _uploadAttachments({
    required String userId,
    required String draftTicketId,
  }) async {
    final urls = <String>[];
    final storage =
        Supabase.instance.client.storage.from('support_attachments');

    for (final entry in _attachments.indexed) {
      final index = entry.$1;
      final file = entry.$2;
      final safeName = file.name
          .trim()
          .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final fileName = safeName.isEmpty ? 'beta_feedback_$index.jpg' : safeName;
      final path =
          'support_tickets/$userId/$draftTicketId/beta_feedback/$index-$fileName';

      if (kIsWeb) {
        await storage.uploadBinary(path, await file.readAsBytes());
      } else {
        await storage.upload(path, File(file.path));
      }

      urls.add(storage.getPublicUrl(path));
    }

    return urls;
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
      if (authUser == null) throw Exception('User not logged in');
      final draftTicketId = const Uuid().v4();
      final attachmentUrls = await _uploadAttachments(
        userId: authUser.id,
        draftTicketId: draftTicketId,
      );
      final deviceInfo = await _getDeviceInfo(
        contactEmail: _emailController.text.trim(),
        churchId: user?.placeId,
        userId: user?.uid,
        authEmail: authUser.email,
      );

      final response = await Supabase.instance.client.rpc(
        'submit_support_ticket',
        params: {
          'p_issue_type': _type,
          'p_app_section': 'Beta Feedback',
          'p_summary': _type,
          'p_description': message,
          'p_impact': _type == 'Bug Report' ? 'Medium' : 'Low',
          'p_device_info': deviceInfo,
          'p_attachment_urls': attachmentUrls,
        },
      );
      final supportTicketId =
          response is Map ? response['id']?.toString() : null;
      final publicTicketId =
          response is Map ? response['ticketId']?.toString() : null;
      final emailTarget = supportTicketId ?? publicTicketId;
      final emailSent = emailTarget == null
          ? false
          : await EmailDeliveryService().flushSupportTicketEmails(emailTarget);

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
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Attachments',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Attach screenshots',
                        onPressed:
                            _attachments.length >= 5 ? null : _pickImages,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                      ),
                    ],
                  ),
                  Text(
                    'Add up to 5 screenshots so the developer portal has context.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_attachments.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 100,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _attachments.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          return Stack(
                            children: [
                              _AttachmentPreview(file: _attachments[index]),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: () => setState(
                                    () => _attachments.removeAt(index),
                                  ),
                                  child: CircleAvatar(
                                    radius: 11,
                                    backgroundColor: theme.colorScheme.error,
                                    child: Icon(
                                      Icons.close,
                                      size: 14,
                                      color: theme.colorScheme.onError,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ],
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

class _AttachmentPreview extends StatelessWidget {
  const _AttachmentPreview({required this.file});

  final XFile file;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: 100,
      height: 100,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const CircularProgressIndicator(strokeWidth: 2),
    );

    if (kIsWeb) {
      return FutureBuilder<Uint8List>(
        future: file.readAsBytes(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return placeholder;
          return _PreviewFrame(
            child: Image.memory(
              snapshot.data!,
              width: 100,
              height: 100,
              fit: BoxFit.cover,
            ),
          );
        },
      );
    }

    return _PreviewFrame(
      child: Image.file(
        File(file.path),
        width: 100,
        height: 100,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(width: 100, height: 100, child: child),
    );
  }
}
