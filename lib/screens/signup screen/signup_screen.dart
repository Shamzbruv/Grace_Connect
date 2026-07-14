import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/auth_flow_service.dart';
import '../../services/membership_service.dart';
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
  final _membershipService = MembershipService();

  bool _isLoading = false;
  bool _isLoadingPolicies = true;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _policyLoadError;
  List<Map<String, dynamic>> _requiredPolicies = const [];
  Map<String, bool> _acceptedPolicies = {};

  @override
  void initState() {
    super.initState();
    _loadPolicies();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (_formKey.currentState!.validate()) {
      if (!_allPoliciesAccepted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please accept all required terms and policies.'),
          ),
        );
        return;
      }

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
            'acceptedPolicySnapshot': _policySnapshot(),
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

        await _recordPolicyAcceptanceIfPossible(res);

        // 3. Sign them out so they don't bypass email verification
        await supabase.auth.signOut();

        await _showVerificationDialog(
          title: 'Account Created!',
          message:
              'Welcome, ${_nameController.text.trim()}!\n\nA verification link has been sent to ${_emailController.text.trim()}.\n\nAfter verifying your email, you can finish your profile. If you already have a church, submit a membership request. If not, you can browse Grace Connect now and search approved churches later.',
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

  Future<void> _loadPolicies() async {
    setState(() {
      _isLoadingPolicies = true;
      _policyLoadError = null;
    });

    try {
      final policies =
          await _membershipService.getRequiredPolicies('member_signup');
      if (!mounted) return;
      setState(() {
        _requiredPolicies = policies;
        _acceptedPolicies = {
          for (final policy in policies)
            policy['document_key'] as String:
                _acceptedPolicies[policy['document_key'] as String] ?? false,
        };
        _isLoadingPolicies = false;
      });
    } catch (error) {
      debugPrint('Failed to load signup policies: $error');
      if (!mounted) return;
      setState(() {
        _policyLoadError =
            'Required policies could not be loaded. Please check your connection and try again.';
        _isLoadingPolicies = false;
      });
    }
  }

  bool get _allPoliciesAccepted {
    if (_isLoadingPolicies || _policyLoadError != null) return false;
    if (_requiredPolicies.isEmpty) return false;
    for (final policy in _requiredPolicies) {
      if (_acceptedPolicies[policy['document_key'] as String] != true) {
        return false;
      }
    }
    return true;
  }

  bool get _canSubmit => !_isLoading && _allPoliciesAccepted;

  List<Map<String, String>> _policySnapshot() {
    return _requiredPolicies
        .map(
          (policy) => {
            'key': policy['document_key']?.toString() ?? '',
            'version': policy['document_version']?.toString() ?? '',
          },
        )
        .where((policy) => policy['key']!.isNotEmpty)
        .toList();
  }

  Future<void> _recordPolicyAcceptanceIfPossible(AuthResponse response) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (response.user == null || currentUser == null) return;

    try {
      await _membershipService.acceptPolicies(
        _requiredPolicies,
        source: 'flutter_signup',
        metadata: {
          'isAdultConfirmed': _acceptedPolicies['age_policy'] == true,
          'signupSource': 'flutter_signup',
        },
      );
    } catch (error) {
      debugPrint(
          'Policy acceptance will be confirmed during membership: $error');
    }
  }

  Uri _resolvePolicyUrl(String rawUrl) {
    final uri = Uri.parse(rawUrl);
    if (uri.hasScheme) {
      if (uri.scheme != 'https') {
        throw ArgumentError('Only HTTPS policy URLs are allowed.');
      }
      return uri;
    }

    return Uri.https(
      'www.graceconnect.love',
      '/${rawUrl.replaceFirst(RegExp(r'^/'), '')}',
    );
  }

  Future<void> _openPolicyLink(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      final uri = _resolvePolicyUrl(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open policy link: $error')),
      );
    }
  }

  Widget _buildPolicyLink(String title, String? url) {
    return InkWell(
      onTap: () => _openPolicyLink(url),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Widget _buildPolicySection() {
    final theme = Theme.of(context);

    if (_policyLoadError != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _policyLoadError!,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _isLoadingPolicies ? null : _loadPolicies,
              icon: const Icon(Icons.refresh),
              label: const Text('Reload Policies'),
            ),
          ],
        ),
      );
    }

    if (_isLoadingPolicies) {
      return const LinearProgressIndicator();
    }

    if (_requiredPolicies.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Required policies are not available yet.',
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadPolicies,
              icon: const Icon(Icons.refresh),
              label: const Text('Reload Policies'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Terms & Policies',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ..._requiredPolicies.map((policy) {
          final key = policy['document_key'] as String;
          final title = policy['title'] as String? ?? 'Policy';
          final url = policy['content_url'] as String?;

          return CheckboxListTile(
            value: _acceptedPolicies[key] ?? false,
            onChanged: (value) {
              setState(() => _acceptedPolicies[key] = value ?? false);
            },
            title: Wrap(
              children: [
                const Text('I accept the '),
                _buildPolicyLink(title, url),
                const Text('.'),
              ],
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          );
        }),
      ],
    );
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
                      _buildPolicySection(),
                      const SizedBox(height: 24),
                      AppButton(
                        text: 'Sign Up',
                        onPressed: _canSubmit ? _handleSignup : null,
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
