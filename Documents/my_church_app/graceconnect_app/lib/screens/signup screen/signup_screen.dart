import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import '../../services/church_service.dart';
import '../../services/email_service.dart';
import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../widgets/app_scaffold.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/app_card.dart';
import '../../theme/app_colors.dart';

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
      if (_selectedChurchId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a church from the dropdown')));
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

        // 1. Check if this church is already registered in Supabase
        final churchQuery = await supabase
            .from('churches')
            .select('id')
            .eq('place_id', _selectedChurchId!)
            .maybeSingle();

        final bool churchExists = churchQuery != null;
        final String accountState =
            churchExists ? 'active' : 'awaiting_church_signup';

        // 2. Create User in Supabase Auth
        //    emailRedirectTo: null → no localhost redirect; user confirms then logs in manually
        final AuthResponse res = await supabase.auth.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          data: {
            'full_name': _nameController.text.trim(),
          },
        );

        final user = res.user;

        // 3. Write user profile to Supabase `users` table
        if (user != null) {
          await supabase.from('users').upsert({
            'uid': user.id,
            'email': _emailController.text.trim(),
            'fullName': _nameController.text.trim(),
            'phone': _phoneController.text.trim(),
            'placeId': _selectedChurchId!,
            'placeName': _selectedChurchName,
            'roles': ['Member'],
            'joinDate': DateTime.now().toIso8601String(),
            'photoUrl': '',
            'bio': '',
            'isDeveloper': false,
            'accountState': accountState,
          });

          // 4. Send welcome email via Resend
          try {
            await EmailService().sendMemberWelcomeEmail(
              toEmail: _emailController.text.trim(),
              name: _nameController.text.trim(),
              churchName: _selectedChurchName,
            );
          } catch (e) {
            debugPrint('Failed to send welcome email: $e');
          }

          // 5. Sign them out so they don't bypass email verification
          await supabase.auth.signOut();

          if (mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Account Created!'),
                content: Text(
                    'Welcome, ${_nameController.text.trim()}!\n\nA verification link has been sent to ${_emailController.text.trim()}.\n\nPlease check your inbox AND Spam/Junk folder to verify your account before logging in.'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context); // Close dialog
                      Navigator.pop(context); // Go back to login screen
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
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

                      // Church search — searches local list + Supabase, no Firestore
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
                              'Church not found. Try a different spelling or register a new church below.'),
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
