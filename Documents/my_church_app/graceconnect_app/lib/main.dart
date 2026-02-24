import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'providers/user_role_provider.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard/variants/admin_dashboard.dart';
import 'screens/admin/member_management_screen.dart';
import 'screens/admin/finance_dashboard_screen.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/landing/landing_page.dart';
import 'screens/login screen/login_screen.dart';
import 'screens/login screen/forgot_password_screen.dart';
import 'screens/signup screen/signup_screen.dart';
import 'screens/signup screen/church_signup_screen.dart';
import 'screens/signup screen/complete_profile_screen.dart';
import 'screens/members/members_list_screen.dart';
import 'screens/attendance/attendance_screen.dart';
import 'screens/donations/donations_screen.dart';
import 'screens/events/events_screen.dart';
import 'screens/prayers/prayers_screen.dart';
import 'screens/analytics/analytics_screen.dart';
import 'screens/counseling/counseling_intro_screen.dart';
import 'screens/live_streaming/live_streaming_screen.dart';
import 'screens/community/community_feed_screen.dart';
import 'screens/bible/bible_home_screen.dart';
import 'screens/members/member_dashboard_screen.dart';
import 'screens/settings/settings_home_screen.dart';
import 'screens/settings/account_settings_screen.dart';
import 'screens/settings/privacy_settings_screen.dart';
import 'screens/settings/notification_settings_screen.dart';
import 'screens/settings/attendance_settings_screen.dart';
import 'screens/settings/community_settings_screen.dart';
import 'screens/settings/bible_settings_screen.dart';
import 'screens/settings/church_admin_settings_screen.dart';
import 'screens/settings/finance_settings_screen.dart';
import 'screens/settings/app_settings_screen.dart';
import 'screens/settings/feedback_screen.dart';
import 'screens/profile/support_screen.dart';
import 'screens/developer/developer_console_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/study_groups/study_group_list_screen.dart';

// Firebase is still initialized for non-auth features (attendance, events, etc.)
late final Future<FirebaseApp> _initialization;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start Firebase initialization (used for non-auth Firestore features)
  _initialization = Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await Supabase.initialize(
    url: 'https://nimgsgnkcvddomrgkawb.supabase.co',
    anonKey: 'sb_publishable_-lsEclVqaNPAlO4h7z3vtw_Q8xZY3cN',
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => UserRoleProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Grace Connect',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const AuthWrapper(),
            routes: {
              '/login': (context) => const LoginScreen(),
              '/forgot_password': (context) => const ForgotPasswordScreen(),
              '/signup': (context) => const SignupScreen(),
              '/church_signup': (context) => const ChurchSignupScreen(),
              '/complete_profile': (context) => const CompleteProfileScreen(),
              '/members': (context) => const MembersListScreen(),
              '/attendance': (context) => const AttendanceScreen(),
              '/donations': (context) => const DonationsScreen(),
              '/events': (context) => const EventsScreen(),
              '/prayers': (context) => const PrayersScreen(),
              '/analytics': (context) => const AnalyticsScreen(),
              '/counseling': (context) => const CounselingIntroScreen(),
              '/live_streaming': (context) => const LiveStreamingScreen(),
              '/community': (context) => const CommunityFeedScreen(),
              '/bible': (context) => const BibleHomeScreen(),
              '/admin_dashboard': (context) => const AdminDashboard(),
              '/finance': (context) => const FinanceDashboardScreen(),
              '/member_dashboard': (context) => const MemberDashboardScreen(),
              '/settings': (context) => const SettingsHomeScreen(),
              '/settings/account': (context) => const AccountSettingsScreen(),
              '/settings/privacy': (context) => const PrivacySettingsScreen(),
              '/settings/notifications': (context) =>
                  const NotificationSettingsScreen(),
              '/settings/attendance': (context) =>
                  const AttendanceSettingsScreen(),
              '/settings/community': (context) =>
                  const CommunitySettingsScreen(),
              '/settings/bible': (context) => const BibleSettingsScreen(),
              '/settings/church_admin': (context) =>
                  const ChurchAdminSettingsScreen(),
              '/settings/finance': (context) => const FinanceSettingsScreen(),
              '/settings/app_config': (context) => const AppSettingsScreen(),
              '/settings/feedback': (context) => const FeedbackScreen(),
              '/developer_console': (context) => const DeveloperConsoleScreen(),
              '/profile': (context) => const ProfileScreen(),
              '/study_groups': (context) => const StudyGroupListScreen(),
            },
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _splashComplete = false;
  static const Duration _minSplashDuration = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    // Wait for Firebase init (for Firestore features) AND minimum splash duration
    await Future.wait([
      _initialization,
      Future.delayed(_minSplashDuration),
    ]);

    if (mounted) {
      setState(() {
        _splashComplete = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_splashComplete) {
      return const SplashScreen();
    }

    // Auth state is driven ONLY by Supabase — no Firebase Auth dependency
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final supabaseUser = Supabase.instance.client.auth.currentUser;

        // Only let confirmed users through
        if (supabaseUser != null && supabaseUser.emailConfirmedAt != null) {
          return const DashboardScreen();
        }

        return const LandingPage();
      },
    );
  }
}
