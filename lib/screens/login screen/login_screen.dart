import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/app_scaffold.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/app_button.dart';

import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
import '../../services/auth_flow_service.dart';
import '../signup screen/signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedUser();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadRememberedUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _rememberMe = prefs.getBool('rememberMe') ?? false;
      if (_rememberMe) {
        _emailController.text = prefs.getString('email') ?? '';
      }
    });
  }

  Future<void> _handleLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final AuthResponse res =
          await Supabase.instance.client.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      final user = res.user;

      // EMAIL VERIFICATION CHECK
      if (user != null && !AuthFlowService.isConfirmedUser(user)) {
        await Supabase.instance.client.auth
            .signOut(); // Block unverified access
        await _showEmailNotConfirmedDialog(_emailController.text.trim());
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      if (_rememberMe) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('rememberMe', true);
        await prefs.setString('email', _emailController.text.trim());
      } else {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('rememberMe');
        await prefs.remove('email');
      }

      await _fetchUserProfile(user);
    } on AuthException catch (e) {
      if (mounted) {
        if (AuthFlowService.isEmailNotConfirmed(e)) {
          await _showEmailNotConfirmedDialog(_emailController.text.trim());
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showEmailNotConfirmedDialog(String email) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Email Not Verified'),
        content: Text(
          'Please verify your email address before signing in.\n\nWe can send another verification link to $email.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await AuthFlowService.resendConfirmationEmail(email);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Verification email sent again.')),
                );
              } on AuthException catch (error) {
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(error.message)),
                );
              } catch (error) {
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content:
                          Text('Could not resend verification email: $error')),
                );
              }
            },
            child: const Text('Resend Email'),
          ),
        ],
      ),
    );
  }

  /// Fetches the user profile from the Supabase `users` table.
  /// Falls back to complete_profile screen if no profile is found.
  Future<void> _fetchUserProfile(User? user) async {
    if (user == null) return;
    try {
      final roleProvider =
          Provider.of<UserRoleProvider>(context, listen: false);
      final data = await Supabase.instance.client
          .from('users')
          .select()
          .eq('uid', user.id)
          .maybeSingle();

      if (data != null && mounted) {
        final userProfile = UserProfile.fromMap(data);

        roleProvider.setUserProfile(userProfile);

        if (mounted) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/dashboard', (route) => false);
        }
      } else {
        // No profile found — redirect to complete profile (e.g. first Google sign-in)
        if (mounted) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/complete_profile', (route) => false);
        }
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      await Supabase.instance.client.auth.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching profile: $e')),
        );
        setState(() => _isLoading = false);
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Image.asset(
                'assets/logo.png',
                height: 120,
                width: 120,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 16),
              Text(
                'Welcome Back',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to your spiritual journey',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(),
              ),
              const SizedBox(height: 32),

              AppCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    AppTextField(
                      controller: _emailController,
                      label: 'Email',
                      hint: 'Enter your email',
                      prefixIcon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    AppTextField(
                      controller: _passwordController,
                      label: 'Password',
                      hint: 'Enter your password',
                      prefixIcon: Icons.lock_outline,
                      obscureText: _obscurePassword,
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (value) =>
                              setState(() => _rememberMe = value ?? false),
                          activeColor: Theme.of(context).colorScheme.primary,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4)),
                        ),
                        Text(
                          'Remember me',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    AppButton(
                      text: 'Sign In',
                      onPressed: _handleLogin,
                      isLoading: _isLoading,
                      icon: Icons.arrow_forward,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, '/forgot_password'),
                    child: const Text('Forgot Password?'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const SignupScreen()),
                    ),
                    child: const Text('Create Account',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
