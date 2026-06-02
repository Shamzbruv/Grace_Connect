import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../widgets/app_scaffold.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../services/auth_flow_service.dart';
import '../../services/email_service.dart';
import '../../services/church_service.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';

class ChurchSignupScreen extends StatefulWidget {
  final Map<String, String>? initialData; // For prefilling from invite link

  const ChurchSignupScreen({super.key, this.initialData});

  @override
  State<ChurchSignupScreen> createState() => _ChurchSignupScreenState();
}

class _ChurchSignupScreenState extends State<ChurchSignupScreen> {
  final _formKey = GlobalKey<FormState>();

  // Church Details
  final _churchSearchController = TextEditingController();
  final _churchNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _denominationController = TextEditingController();
  String? _selectedChurchId;
  bool _isCreatingNewChurch = false;

  // Admin/Pastor Details
  final _adminNameController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _adminPhoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _churchNameController.text = widget.initialData!['name'] ?? '';
      _churchSearchController.text = widget.initialData!['name'] ?? '';
      _addressController.text = widget.initialData!['address'] ?? '';
      _isCreatingNewChurch = true;
    }
  }

  @override
  void dispose() {
    _churchSearchController.dispose();
    _churchNameController.dispose();
    _addressController.dispose();
    _denominationController.dispose();
    _adminNameController.dispose();
    _adminEmailController.dispose();
    _adminPhoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _registerChurch() async {
    if (!_formKey.currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passwords do not match')));
      return;
    }

    setState(() => _isLoading = true);

    final supabase = Supabase.instance.client;

    try {
      final placeId = _selectedChurchId ??
          'church_${DateTime.now().millisecondsSinceEpoch}';

      // 1. Create Admin User in Supabase Auth
      final AuthResponse res = await AuthFlowService.signUpWithEmail(
        email: _adminEmailController.text.trim(),
        password: _passwordController.text,
        data: {
          'full_name': _adminNameController.text.trim(),
          'phone': _adminPhoneController.text.trim(),
          'phoneNumber': _adminPhoneController.text.trim(),
          'placeId': placeId,
          'placeName': _churchNameController.text.trim(),
          'address': _addressController.text.trim(),
          'denomination': _denominationController.text.trim(),
          'roles': ['Admin', 'Pastor'],
          'accountState': 'active',
          'joinDate': DateTime.now().toIso8601String(),
          'bio': 'Church Admin',
        },
      );
      final createdUser = res.user;
      if (createdUser == null) {
        throw Exception('Could not create the church admin account.');
      }

      // The Supabase auth trigger creates the pastor profile and church row.
      // Keeping this off the client avoids false RLS errors after signup.
      debugPrint(
        'Church signup accepted for ${createdUser.id}; database trigger will sync rows.',
      );

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

      await _showVerificationDialog(
        title: 'Church Registered!',
        message:
            'A verification link has been sent to ${_adminEmailController.text.trim()}.\n\nPlease check your inbox/spam and verify your email before logging in.',
      );
    } on AuthException catch (e) {
      if (mounted) {
        if (AuthFlowService.isExistingAccount(e) ||
            AuthFlowService.isEmailNotConfirmed(e)) {
          try {
            await _resendAndShowVerificationDialog();
          } catch (error) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not resend email: $error')),
            );
          }
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
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

  Future<void> _resendAndShowVerificationDialog() async {
    final email = _adminEmailController.text.trim();
    await AuthFlowService.resendConfirmationEmail(email);
    await _showVerificationDialog(
      title: 'Verification Email Sent',
      message:
          'That admin email already has an account waiting for verification.\n\nA fresh verification link has been sent to $email.',
    );
  }

  Future<void> _showVerificationDialog({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pop();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
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
                    // Church search — searches local list + Supabase
                    if (!_isCreatingNewChurch)
                      TypeAheadField<Map<String, String>>(
                        controller: _churchSearchController,
                        builder: (context, controller, focusNode) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'Search Existing Church',
                              hintText: 'Search by name or address',
                              prefixIcon: Icon(Icons.search),
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.all(Radius.circular(12)),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                            ),
                          );
                        },
                        suggestionsCallback: (pattern) async {
                          return await ChurchService.searchChurches(pattern);
                        },
                        itemBuilder: (context, suggestion) {
                          return ListTile(
                            leading: Icon(Icons.church,
                                color: Theme.of(context).colorScheme.primary),
                            title: Text(suggestion['name']!),
                            subtitle: Text(suggestion['address']!,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          );
                        },
                        onSelected: (suggestion) {
                          setState(() {
                            _selectedChurchId = suggestion['id'];
                            _churchNameController.text = suggestion['name']!;
                            _churchSearchController.text = suggestion['name']!;
                            _addressController.text = suggestion['address']!;
                            // Auto-assume New Testament Church of God for early database entries
                            _denominationController.text =
                                'New Testament Church of God';
                            _isCreatingNewChurch =
                                true; // Open the rest of the form to fill in remaining details
                          });
                        },
                        emptyBuilder: (context) => Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Church not found.'),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _isCreatingNewChurch = true;
                                    _selectedChurchId = null;
                                    _churchNameController.text =
                                        _churchSearchController.text;
                                  });
                                },
                                child: const Text('Create New Church Instead'),
                              )
                            ],
                          ),
                        ),
                      ),

                    if (_isCreatingNewChurch)
                      Column(
                        children: [
                          if (_selectedChurchId != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Claiming "${_churchNameController.text}"',
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onPrimaryContainer,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _isCreatingNewChurch = false;
                                        _selectedChurchId = null;
                                        _churchNameController.clear();
                                        _churchSearchController.clear();
                                      });
                                    },
                                    child: const Text('Change'),
                                  )
                                ],
                              ),
                            ),
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
                        obscureText: _obscurePassword,
                        suffixIcon: IconButton(
                            icon: Icon(_obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword))),
                    const SizedBox(height: 12),
                    AppTextField(
                        controller: _confirmPasswordController,
                        label: 'Confirm Password',
                        obscureText: _obscureConfirmPassword,
                        suffixIcon: IconButton(
                            icon: Icon(_obscureConfirmPassword
                                ? Icons.visibility_off
                                : Icons.visibility),
                            onPressed: () => setState(() =>
                                _obscureConfirmPassword =
                                    !_obscureConfirmPassword))),
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
