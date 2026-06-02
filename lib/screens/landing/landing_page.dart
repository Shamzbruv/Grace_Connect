import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/app_colors.dart';
import '../../widgets/glass/glass_scaffold.dart';
import '../../widgets/glass/glass_container.dart';
import '../../widgets/animations/scale_button.dart';
import '../login screen/login_screen.dart';
import '../signup screen/signup_screen.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    // FIX: Block back navigation after logout
    return PopScope(
      canPop: false,
      child: GlassScaffold(
        body: Center(
          child: Column(
            children: [
              const Spacer(flex: 1),
              // Logo and branding
              Column(
                children: [
                  ScaleButton(
                    onTap: () {}, // Easter egg?
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/logo.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your Church, Always With You',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white70
                              : AppColors.softBrown,
                        ),
                  ).animate().fadeIn(delay: 200.ms, duration: 600.ms),
                ],
              ).animate().fadeIn(delay: 200.ms, duration: 600.ms),

              const Spacer(flex: 2),

              // Feature Highlights
              SizedBox(
                height: 220,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  physics: const BouncingScrollPhysics(),
                  children: const [
                    _FeatureCard(
                      icon: Icons.calendar_month_rounded,
                      title: 'Events',
                      description: 'Stay updated with upcoming church events.',
                      delay: 400,
                    ),
                    SizedBox(width: 16),
                    _FeatureCard(
                      icon: Icons.volunteer_activism_rounded,
                      title: 'Giving',
                      description: 'Support the mission with digital giving.',
                      delay: 500,
                    ),
                    SizedBox(width: 16),
                    _FeatureCard(
                      icon: Icons.people_rounded,
                      title: 'Community',
                      description: 'Connect with your church family groups.',
                      delay: 600,
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 2),

              // CTA Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Column(
                  children: [
                    ScaleButton(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const LoginScreen()),
                        );
                      },
                      child: Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: AppColors.primaryGradient,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            'Sign In',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                          ),
                        ),
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 700.ms)
                        .slideY(begin: 0.2, end: 0),
                    const SizedBox(height: 16),
                    ScaleButton(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const SignupScreen()),
                        );
                      },
                      child: GlassContainer(
                        height: 56,
                        width: double.infinity,
                        opacity: 0.1,
                        child: Center(
                          child: Text(
                            'Sign Up',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).brightness == Brightness.dark 
                                      ? Colors.white 
                                      : AppColors.primary,
                                ),
                          ),
                        ),
                      ),
                    )
                        .animate()
                        .fadeIn(delay: 800.ms)
                        .slideY(begin: 0.2, end: 0),
                  ],
                ),
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final int delay;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return ScaleButton(
      onTap: () {},
      child: GlassContainer(
        width: 160,
        opacity: 0.5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                // border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)), // Optional
              ),
              child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    height: 1.4,
                  ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(delay: Duration(milliseconds: delay))
        .slideX(begin: 0.2, end: 0);
  }
}
