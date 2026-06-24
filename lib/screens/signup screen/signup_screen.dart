import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../../services/auth_flow_service.dart';
import '../../services/church_service.dart';
import '../../models/user_profile.dart'; // Needed to save the model
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/app_card.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _churchSearchController = TextEditingController();

  String? _selectedChurchId;
  String _selectedChurchName = '';
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _churchSearchController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (_formKey.currentState!.validate()) {
      if (_passwordController.text != _confirmPasswordController.text) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Passwords do not match')));
        return;
      }

      setState(() => _isLoading = true);

      try {
        final supabase = Supabase.instance.client;

        // 2. Create User in Supabase Auth
        final AuthResponse res = await AuthFlowService.signUpWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          data: {
            'full_name': _nameController.text.trim(),
            'phone': _phoneController.text.trim(),
            'phoneNumber': _phoneController.text.trim(),
            'signupSource': 'flutter_signup',
          },
        );

        final user = res.user;

        // Save initial profile data to Firestore so CompleteProfile doesn't ask again
        if (user != null) {
          final userProfile = UserProfile(
            uid: user.id,
            email: user.email ?? '',
            fullName: _nameController.text.trim(),
            phoneNumber: _phoneController.text.trim(),
            placeId: '',
            placeName: '',
            roles: ['Member'],
            joinDate: DateTime.now(),
            photoUrl: '', // Will be added in CompleteProfileScreen
            bio: '', // Will be added in CompleteProfileScreen
            isDeveloper: false,
            accountState: 'active',
          );

          try {
            await supabase
                .from('users')
                .upsert(userProfile.toMap(), onConflict: 'uid');
          } catch (e) {
            debugPrint('Failed to sync initial profile to database: $e');
          }
        }

        // 3. Sign them out so they don't bypass email verification
        await supabase.auth.signOut();

        await _showVerificationDialog(
          title: 'Account Created!',
          message:
              'Welcome, ${_nameController.text.trim()}!\n\nA verification link has been sent to ${_emailController.text.trim()}.\n\nAfter verifying your email, you can submit a church membership request for approval.',
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
  }

  Future<void> _resendAndShowVerificationDialog() async {
    final email = _emailController.text.trim();
    await AuthFlowService.resendConfirmationEmail(email);
    await _showVerificationDialog(
      title: 'Verification Email Sent',
      message:
          'That email already has an account waiting for verification.\n\nA fresh verification link has been sent to $email.',
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
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.mark_email_read_outlined,
                size: 64,
                color: Theme.of(dialogContext).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(dialogContext)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(dialogContext).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: AppButton(
                  text: 'Back to Login',
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      withBackground: true,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.person_add_outlined,
                    size: 60, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Join Grace Connect',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                AppCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      AppTextField(
                          controller: _nameController,
                          label: 'Full Name',
                          hint: 'John Doe'),
                      const SizedBox(height: 16),
                      AppTextField(
                          controller: _phoneController,
                          label: 'Phone',
                          hint: '+1 234...',
                          keyboardType: TextInputType.phone),
                      const SizedBox(height: 16),
                      AppTextField(
                          controller: _emailController,
                          label: 'Email',
                          hint: 'john@example.com',
                          keyboardType: TextInputType.emailAddress),
                      const SizedBox(height: 16),

                      // Church search only returns approved public churches.
                      TypeAheadField<Map<String, String>>(
                        controller: _churchSearchController,
                        builder: (context, controller, focusNode) {
                          return TextField(
                            controller: controller,
                            focusNode: focusNode,
                            decoration: const InputDecoration(
                              labelText: 'Find Your Church',
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
                            _selectedChurchName = suggestion['name']!;
                            _churchSearchController.text = suggestion['name']!;
                          });
                        },
                        emptyBuilder: (context) => const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                              'No approved churches match that search. You can still create an account and request a church later.'),
                        ),
                      ),

                      const SizedBox(height: 16),

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
                      const SizedBox(height: 16),

                      AppTextField(
                          controller: _confirmPasswordController,
                          label: 'Confirm Pwd',
                          obscureText: _obscureConfirmPassword,
                          suffixIcon: IconButton(
                              icon: Icon(_obscureConfirmPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setState(() =>
                                  _obscureConfirmPassword =
                                      !_obscureConfirmPassword))),

                      const SizedBox(height: 16),

                      const SizedBox(height: 16),

                      const SizedBox(height: 24),

                      AppButton(
                        text: 'Sign Up',
                        onPressed: _handleSignup,
                        isLoading: _isLoading,
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Already have an account? Sign In'),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.pushNamed(context, '/church_signup'),
                  child: Text('Register a New Church instead?',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.primary)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalLink extends StatelessWidget {
  const _LegalLink({
    required this.label,
    required this.routeName,
  });

  final String label;
  final String routeName;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.pushNamed(context, routeName),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
