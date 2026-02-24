import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widgets/app_scaffold.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_text_field.dart';
import '../../widgets/app_button.dart';

import '../../models/user_profile.dart';
import '../../providers/user_role_provider.dart';
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
      if (user != null && user.emailConfirmedAt == null) {
        await Supabase.instance.client.auth.signOut(); // Block unverified access
        if (mounted) {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Email Not Verified'),
              content: const Text(
                  'Please verify your email address to log in.\n\nCheck your email (including spam/junk folder).'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () async {
                    try {
                      await Supabase.instance.client.auth.resend(
                        type: OtpType.signup,
                        email: _emailController.text.trim(),
                      );
                      if (mounted) Navigator.pop(context);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Verification email resent!')));
                      }
                    } catch (e) {
                      if (mounted) Navigator.pop(context);
                      if (mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(SnackBar(content: Text('Error: $e')));
                      }
                    }
                  },
                  child: const Text('Resend Email'),
                ),
              ],
            ),
          );
        }
        setState(() => _isLoading = false);
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
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser != null) {
        final GoogleSignInAuthentication googleAuth =
            await googleUser.authentication;

        final AuthResponse res =
            await Supabase.instance.client.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: googleAuth.idToken!,
          accessToken: googleAuth.accessToken,
        );

        await _fetchUserProfile(res.user);
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Google Sign-In Error: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  /// Fetches the user profile from the Supabase `users` table.
  /// Falls back to complete_profile screen if no profile found (e.g. first Google sign-in).
  Future<void> _fetchUserProfile(User? user) async {
    if (user == null) return;
    try {
      final data = await Supabase.instance.client
          .from('users')
          .select()
          .eq('uid', user.id)
          .maybeSingle();

      if (data != null && mounted) {
        final userProfile = UserProfile.fromMap(data);

        final roleProvider =
            Provider.of<UserRoleProvider>(context, listen: false);
        roleProvider.setUserProfile(userProfile);

        if (mounted) {
          Navigator.of(context)
              .pushNamedAndRemoveUntil('/admin_dashboard', (route) => false);
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
                    const SizedBox(height: 16),
                    AppButton(
                      text: 'Sign in with Google',
                      isSecondary: true,
                      onPressed: _handleGoogleLogin,
                      icon: FontAwesomeIcons.google,
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
