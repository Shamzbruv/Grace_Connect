import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// Optional or use ImagePicker
import 'package:image_picker/image_picker.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../providers/user_role_provider.dart';
import '../../theme/app_colors.dart';
import '../../widgets/ui/app_scaffold.dart';
import '../../widgets/ui/app_card.dart';
import '../../widgets/ui/app_button.dart';
import '../../widgets/ui/app_text_field.dart';
import '../../models/support_ticket_model.dart';
import '../../services/email_service.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _formKey = GlobalKey<FormState>();
  final _summaryController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _issueType = 'Bug / Something isn’t working';
  String _appSection = 'Other';
  String _impact = 'Medium';
  bool _isLoading = false;

  final List<XFile> _attachments = [];
  final ImagePicker _picker = ImagePicker();

  final List<String> _issueTypes = [
    'Bug / Something isn’t working',
    'Account/Login issue',
    'Attendance/Auto check-in problem',
    'Community/Posts problem',
    'Events/Announcements problem',
    'Giving/Finance problem',
    'Bible/Study Partner problem',
    'Notifications problem',
    'Church Signup / Membership approval problem',
    'Other',
  ];

  final List<String> _appSections = [
    'Login / Signup',
    'Church Signup',
    'Home Dashboard',
    'Attendance',
    'Sunday School',
    'Community Feed',
    'Announcements',
    'Events',
    'Giving / Finance',
    'Livestream',
    'Bible',
    'Study Partner / Study Groups',
    'Profile / Family Tree',
    'Notifications',
    'Admin Tools / Role Management',
    'Other',
  ];

  final List<String> _impactLevels = ['Low', 'Medium', 'High', 'Critical'];

  @override
  void dispose() {
    _summaryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() => _attachments.add(image));
    }
  }

  Future<Map<String, dynamic>> _getDeviceInfo() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();

    Map<String, dynamic> deviceData = {};
    if (kIsWeb) {
      deviceData = {
        'os': 'Web',
        'platform': 'Browser',
      };
    } else if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      deviceData = {
        'os': 'Android',
        'version': androidInfo.version.release,
        'model': androidInfo.model,
        'brand': androidInfo.brand,
      };
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      deviceData = {
        'os': 'iOS',
        'version': iosInfo.systemVersion,
        'model': iosInfo.model,
        'name': iosInfo.name,
      };
    }

    deviceData['appVersion'] = packageInfo.version;
    deviceData['buildNumber'] = packageInfo.buildNumber;
    return deviceData;
  }

  Future<void> _submitTicket() async {
    if (!_formKey.currentState!.validate()) return;
    if (_summaryController.text.trim().isEmpty ||
        _descriptionController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a summary and description.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User not logged in');

      final roleProvider =
          Provider.of<UserRoleProvider>(context, listen: false);
      final profile = roleProvider.userProfile; // Assumes populated

      // 1. Upload Attachments
      List<String> attachmentUrls = [];
      final ticketId = const Uuid().v4();

      for (var file in _attachments) {
        final path =
            'support_tickets/${user.id}/$ticketId/attachments/${file.name}';
        if (kIsWeb) {
          await Supabase.instance.client.storage
              .from('support_attachments')
              .uploadBinary(path, await file.readAsBytes());
        } else {
          await Supabase.instance.client.storage
              .from('support_attachments')
              .upload(path, File(file.path));
        }
        final url = Supabase.instance.client.storage
            .from('support_attachments')
            .getPublicUrl(path);
        attachmentUrls.add(url);
      }

      // 2. Gather Info
      final deviceInfo = await _getDeviceInfo();

      // 3. Create Model
      final ticket = SupportTicket(
        ticketId: ticketId,
        uid: user.id,
        reporterEmail: user.email ?? 'unknown',
        churchId: profile?.placeId,
        roles: profile?.roles ?? [],
        issueType: _issueType,
        appSection: _appSection,
        summary: _summaryController.text.trim(),
        description: _descriptionController.text.trim(),
        impact: _impact,
        deviceInfo: deviceInfo,
        attachmentUrls: attachmentUrls,
        status: 'open',
        createdAt: DateTime.now(),
      );

      // 4. Save to Firestore
      await Supabase.instance.client
          .from('support_tickets')
          .insert(ticket.toMap());

      // Send email to support using Resend
      try {
        await EmailService().sendSupportReportEmail(
          reporterEmail: user.email ?? 'unknown',
          issueType: _issueType,
          summary: _summaryController.text.trim(),
          description: _descriptionController.text.trim(),
          ticketId: ticketId,
        );
      } catch (e) {
        debugPrint('Failed to send support email: $e');
      }

      // 5. Success
      if (mounted) {
        _summaryController.clear();
        _descriptionController.clear();
        _attachments.clear();
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Report Sent ✅'),
            content: Text(
                'Your ticket ID is:\n$ticketId\n\nOur support team has been notified via email.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context); // Dialog
                  Navigator.pop(context); // Screen
                },
                child: const Text('Close'),
              )
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error submitting report: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Help & Support',
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('About the Issue',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _issueType,
                      decoration: const InputDecoration(
                          labelText: 'Issue Type',
                          border: OutlineInputBorder()),
                      items: _issueTypes
                          .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t,
                                  style: const TextStyle(fontSize: 14),
                                  overflow: TextOverflow.ellipsis)))
                          .toList(),
                      isExpanded: true,
                      onChanged: (v) => setState(() => _issueType = v!),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _appSection,
                      decoration: const InputDecoration(
                          labelText: 'Where did it happen?',
                          border: OutlineInputBorder()),
                      items: _appSections
                          .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(s,
                                  style: const TextStyle(fontSize: 14))))
                          .toList(),
                      isExpanded: true,
                      onChanged: (v) => setState(() => _appSection = v!),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _impact,
                      decoration: const InputDecoration(
                          labelText: 'Impact Level',
                          border: OutlineInputBorder()),
                      items: _impactLevels
                          .map(
                              (i) => DropdownMenuItem(value: i, child: Text(i)))
                          .toList(),
                      onChanged: (v) => setState(() => _impact = v!),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Details',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    AppTextField(
                        controller: _summaryController,
                        label: 'Summary',
                        hint: 'e.g. Attendance not saving'),
                    const SizedBox(height: 12),
                    AppTextField(
                      controller: _descriptionController,
                      label: 'Description',
                      hint: 'Steps to reproduce...',
                      maxLines: 5,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Attachments (Optional)',
                            style: Theme.of(context).textTheme.titleMedium),
                        IconButton(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.add_a_photo,
                                color: AppColors.primary)),
                      ],
                    ),
                    if (_attachments.isNotEmpty)
                      SizedBox(
                        height: 100,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _attachments.length,
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: Stack(
                                children: [
                                  _AttachmentPreview(
                                    file: _attachments[index],
                                  ),
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: GestureDetector(
                                      onTap: () => setState(
                                          () => _attachments.removeAt(index)),
                                      child: CircleAvatar(
                                          radius: 10,
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .error,
                                          child: Icon(Icons.close,
                                              size: 12,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onError)),
                                    ),
                                  )
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              AppButton(
                text: 'Submit Report',
                onPressed: _submitTicket,
                isLoading: _isLoading,
                isFullWidth: true,
              ),
            ],
          ),
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
    if (kIsWeb) {
      return FutureBuilder<Uint8List>(
        future: file.readAsBytes(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const SizedBox(
              width: 100,
              height: 100,
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return Image.memory(
            snapshot.data!,
            width: 100,
            height: 100,
            fit: BoxFit.cover,
          );
        },
      );
    }

    return Image.file(
      File(file.path),
      width: 100,
      height: 100,
      fit: BoxFit.cover,
    );
  }
}
