import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../models/church_model.dart';
import '../../models/user_profile.dart';
import 'package:provider/provider.dart';
import '../../providers/user_role_provider.dart';
import '../../services/email_service.dart';

class ChurchSignupScreen extends StatefulWidget {
  final Map<String, String>? initialData; // For prefilling from invite link

  const ChurchSignupScreen({super.key, this.initialData});

  @override
  State<ChurchSignupScreen> createState() => _ChurchSignupScreenState();
}

class _ChurchSignupScreenState extends State<ChurchSignupScreen> {
  final _formKey = GlobalKey<FormState>();

  // Church Details
  final _churchNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _denominationController = TextEditingController();

  // Admin/Pastor Details
  final _adminNameController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _adminPhoneController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _churchNameController.text = widget.initialData!['name'] ?? '';
      _addressController.text = widget.initialData!['address'] ?? '';
    }
  }

  @override
  void dispose() {
    _churchNameController.dispose();
    _addressController.dispose();
    _denominationController.dispose();
    _adminNameController.dispose();
    _adminEmailController.dispose();
    _adminPhoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _registerChurch() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final supabase = Supabase.instance.client;

    try {
      // 1. Create Admin User in Supabase Auth
      final AuthResponse res = await supabase.auth.signUp(
        email: _adminEmailController.text.trim(),
        password: _passwordController.text,
        data: {
          'full_name': _adminNameController.text.trim(),
        },
      );
      final uid = res.user!.id;

      // 2. Generate a unique placeId for this church (since we're not using Google Places)
      final placeId = 'church_${DateTime.now().millisecondsSinceEpoch}_$uid';

      // 3. Insert Church Record into Supabase
      final churchInsert = await supabase.from('churches').insert({
        'name': _churchNameController.text.trim(),
        'place_id': placeId,
        'address': _addressController.text.trim(),
        'denomination': _denominationController.text.trim(),
        'owner_user_id': uid,
        'timezone': 'UTC',
        'status': 'active',
        'created_at': DateTime.now().toIso8601String(),
        'members_count': 1,
      }).select('id').single();

      final churchDbId = churchInsert['id'] as String;

      // 4. Insert User Profile into Supabase
      await supabase.from('users').upsert({
        'uid': uid,
        'email': _adminEmailController.text.trim(),
        'fullName': _adminNameController.text.trim(),
        'phone': _adminPhoneController.text.trim(),
        'placeId': placeId,
        'placeName': _churchNameController.text.trim(),
        'roles': ['Admin', 'Pastor'],
        'joinDate': DateTime.now().toIso8601String(),
        'photoUrl': '',
        'bio': 'Church Admin',
        'isDeveloper': false,
        'accountState': 'active',
      });

      // 5. Update any pending members who were waiting for this church
      await supabase
          .from('users')
          .update({
            'accountState': 'active',
            'approvalStatus': 'pending',
          })
          .eq('placeId', placeId)
          .eq('accountState', 'awaiting_church_signup');

      // 6. Send welcome email
      try {
        await EmailService().sendChurchWelcomeEmail(
          toEmail: _adminEmailController.text.trim(),
          adminName: _adminNameController.text.trim(),
          churchName: _churchNameController.text.trim(),
        );
      } catch (e) {
        debugPrint('Failed to send church welcome email: $e');
      }

      // 7. Sign out so AuthWrapper forces email verification before dashboard access
      await supabase.auth.signOut();

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Church Registered!'),
            content: Text(
                'A verification link has been sent to ${_adminEmailController.text.trim()}.\n\nPlease check your inbox/spam and verify your email before logging in.'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop(); // Close dialog
                  Navigator.of(context).pop(); // Close church signup screen
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Register Your Church',
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
                    Text('Church Details',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    AppTextField(
                        controller: _churchNameController,
                        label: 'Church Name'),
                    const SizedBox(height: 12),
                    AppTextField(
                        controller: _denominationController,
                        label: 'Denomination'),
                    const SizedBox(height: 12),
                    AppTextField(
                        controller: _addressController, label: 'Address'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Primary Contact (Admin)',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    AppTextField(
                        controller: _adminNameController, label: 'Your Name'),
                    const SizedBox(height: 12),
                    AppTextField(
                        controller: _adminPhoneController,
                        label: 'Mobile Phone'),
                    const SizedBox(height: 12),
                    AppTextField(
                        controller: _adminEmailController,
                        label: 'Email',
                        keyboardType: TextInputType.emailAddress),
                    const SizedBox(height: 12),
                    AppTextField(
                        controller: _passwordController,
                        label: 'Password',
                        obscureText: true),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              AppButton(
                text: 'Create Church Account',
                onPressed: _registerChurch,
                isLoading: _isLoading,
                isFullWidth: true,
              )
            ],
          ),
        ),
      ),
    );
  }
}
