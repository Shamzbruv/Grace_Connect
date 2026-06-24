import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'providers/user_role_provider.dart';
import 'services/attendance_service.dart';
import 'services/auth_flow_service.dart';
import 'services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard/variants/admin_dashboard.dart';
import 'screens/admin/finance_dashboard_screen.dart';
import 'screens/admin/attendance_insights_screen.dart';
import 'screens/admin/role_management_screen.dart';
import 'screens/admin/schedule_management_screen.dart';
import 'screens/admin/admin_stream_settings_screen.dart';
import 'screens/admin/daily_motivation_admin_screen.dart';
import 'screens/admin/daily_bible_quiz_admin_screen.dart';
import 'screens/landing/landing_page.dart';
import 'screens/login screen/login_screen.dart';
import 'screens/login screen/auth_callback_screen.dart';
import 'screens/login screen/forgot_password_screen.dart';
import 'screens/login screen/reset_password_screen.dart';
import 'screens/membership/membership_gate_screen.dart';
import 'screens/signup screen/signup_screen.dart';
import 'screens/signup screen/church_signup_screen.dart';
import 'screens/signup screen/complete_profile_screen.dart';
import 'screens/members/members_list_screen.dart';
import 'screens/attendance/church_location_picker_screen.dart';
import 'screens/attendance/attendance_screen.dart';
import 'screens/donations/donations_screen.dart';
import 'screens/prayers/prayers_screen.dart';
import 'screens/analytics/analytics_screen.dart';
import 'screens/announcements/announcements_screen.dart';
import 'screens/counseling/counseling_intro_screen.dart';
import 'screens/daily_word/daily_word_screen.dart';
import 'screens/bible/bible_quiz_screen.dart';
import 'screens/live_streaming/live_streaming_screen.dart';
import 'screens/main/main_tabs_screen.dart';
import 'screens/members/member_dashboard_screen.dart';
import 'screens/dashboard/variants/member_dashboard.dart' as dashboard_variant;
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
import 'screens/settings/legal_document_screen.dart';
import 'screens/developer/developer_console_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/support_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/study_groups/study_group_list_screen.dart';
import 'screens/messages/inbox_screen.dart';
import 'screens/testimonies/testimonies_screen.dart';
import 'screens/ministries/ministries_screen.dart';
import 'screens/transfer/church_transfer_screen.dart';
import 'widgets/auth_required.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Start Firebase initialization (for Analytics/Crashlytics/Distribution)
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await _configureCrashReporting();

  await Supabase.initialize(
    url: 'https://nimgsgnkcvddomrgkawb.supabase.co',
    anonKey: 'sb_publishable_-lsEclVqaNPAlO4h7z3vtw_Q8xZY3cN',
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      detectSessionInUri: true,
    ),
  );

  if (!kIsWeb) {
    await NotificationService().init();
  }

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

Future<void> _configureCrashReporting() async {
  if (kIsWeb) return;
  FlutterError.onError = (details) {
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  Widget _protected(Widget child) => AuthRequired(child: child);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    unawaited(_resumeAppServices());
  }

  Future<void> _resumeAppServices() async {
    try {
      await Supabase.instance.client.auth.refreshSession();
    } catch (error) {
      debugPrint('Session refresh on resume skipped: $error');
    }

    if (!mounted) return;
    try {
      final roleProvider = context.read<UserRoleProvider>();
      await roleProvider.refreshProfile();
      if (!kIsWeb) {
        await FirebaseCrashlytics.instance.setCustomKey(
          'church_id',
          roleProvider.user?.placeId ?? '',
        );
        await FirebaseCrashlytics.instance.setCustomKey(
          'is_admin',
          roleProvider.user?.isAdmin ?? false,
        );
        await FirebaseCrashlytics.instance.setCustomKey(
          'is_pastor',
          roleProvider.user?.isPastor ?? false,
        );
      }
    } catch (error) {
      debugPrint('Profile refresh on resume skipped: $error');
    }

    if (!kIsWeb) {
      try {
        await AttendanceService().initialize();
      } catch (error) {
        debugPrint('Attendance resume skipped: $error');
      }
    }
  }

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
            navigatorKey: NotificationService.navigatorKey,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const AuthWrapper(),
            routes: {
              '/login': (context) => const LoginScreen(),
              '/auth/callback': (context) => const AuthCallbackScreen(),
              '/forgot_password': (context) => const ForgotPasswordScreen(),
              '/reset_password': (context) => const ResetPasswordScreen(),
              '/signup': (context) => const SignupScreen(),
              '/church_signup': (context) => const ChurchSignupScreen(),
              '/complete_profile': (context) =>
                  _protected(const CompleteProfileScreen()),
              '/members': (context) => _protected(const MembersListScreen()),
              '/attendance': (context) => _protected(const AttendanceScreen()),
              '/attendance_insights': (context) =>
                  _protected(const AttendanceInsightsScreen()),
              '/attendance_location': (context) =>
                  _protected(const ChurchLocationPickerScreen()),
              '/donations': (context) => _protected(const DonationsScreen()),
              '/events': (context) =>
                  _protected(const MainTabsScreen(initialIndex: 1)),
              '/prayers': (context) => _protected(const PrayersScreen()),
              '/analytics': (context) => _protected(const AnalyticsScreen()),
              '/announcements': (context) =>
                  _protected(const AnnouncementsScreen()),
              '/counseling': (context) =>
                  _protected(const CounselingIntroScreen()),
              '/live_streaming': (context) =>
                  _protected(const LiveStreamingScreen()),
              '/admin/live_stream': (context) =>
                  _protected(const AdminStreamSettingsScreen()),
              '/daily_word': (context) => _protected(const DailyWordScreen()),
              '/daily_bible_quiz': (context) =>
                  _protected(const BibleQuizScreen()),
              '/community': (context) =>
                  _protected(const MainTabsScreen(initialIndex: 0)),
              '/bible': (context) =>
                  _protected(const MainTabsScreen(initialIndex: 3)),
              '/dashboard': (context) =>
                  _protected(const MainTabsScreen(initialIndex: 2)),
              '/admin_dashboard': (context) =>
                  _protected(const AdminDashboard()),
              '/role_management': (context) =>
                  _protected(const RoleManagementScreen()),
              '/schedule_management': (context) =>
                  _protected(const ScheduleManagementScreen()),
              '/admin/daily_word': (context) =>
                  _protected(const DailyMotivationAdminScreen()),
              '/admin/daily_quiz': (context) =>
                  _protected(const DailyBibleQuizAdminScreen()),
              '/finance': (context) =>
                  _protected(const FinanceDashboardScreen()),
              '/member_dashboard': (context) =>
                  _protected(const MemberDashboardScreen()),
              '/member_view': (context) =>
                  _protected(const dashboard_variant.MemberDashboard()),
              '/settings': (context) => _protected(const SettingsHomeScreen()),
              '/settings/account': (context) =>
                  _protected(const AccountSettingsScreen()),
              '/settings/privacy': (context) =>
                  _protected(const PrivacySettingsScreen()),
              '/settings/notifications': (context) =>
                  _protected(const NotificationSettingsScreen()),
              '/notifications': (context) =>
                  _protected(const NotificationsScreen()),
              '/inbox': (context) => _protected(const InboxScreen()),
              '/settings/attendance': (context) =>
                  _protected(const AttendanceSettingsScreen()),
              '/settings/community': (context) =>
                  _protected(const CommunitySettingsScreen()),
              '/settings/bible': (context) =>
                  _protected(const BibleSettingsScreen()),
              '/settings/church_admin': (context) =>
                  _protected(const ChurchAdminSettingsScreen()),
              '/settings/finance': (context) =>
                  _protected(const FinanceSettingsScreen()),
              '/settings/app_config': (context) =>
                  _protected(const AppSettingsScreen()),
              '/settings/feedback': (context) =>
                  _protected(const FeedbackScreen()),
              '/settings/terms': (context) => _protected(
                    const LegalDocumentScreen(
                      title: 'Terms of Service',
                      documentType: LegalDocumentType.terms,
                    ),
                  ),
              '/settings/privacy_policy': (context) =>
                  _protected(const LegalDocumentScreen(
                    title: 'Privacy Policy',
                    documentType: LegalDocumentType.privacy,
                  )),
              '/support': (context) => _protected(const SupportScreen()),
              '/settings/support': (context) =>
                  _protected(const SupportScreen()),
              '/developer_console': (context) =>
                  _protected(const DeveloperConsoleScreen()),
              '/profile': (context) => _protected(const ProfileScreen()),
              '/study_groups': (context) =>
                  _protected(const StudyGroupListScreen()),
              '/testimonies': (context) =>
                  _protected(const TestimoniesScreen()),
              '/ministries': (context) => _protected(const MinistriesScreen()),
              '/church_transfer': (context) =>
                  _protected(const ChurchTransferScreen()),
            },
            onGenerateRoute: (settings) {
              final uri = Uri.tryParse(settings.name ?? '');
              if (uri?.path == '/daily_word') {
                return MaterialPageRoute(
                  builder: (_) => _protected(
                    DailyWordScreen(
                      motivationId: uri?.queryParameters['id'],
                    ),
                  ),
                );
              }
              if (uri?.path == '/daily_bible_quiz') {
                return MaterialPageRoute(
                  builder: (_) => _protected(
                    BibleQuizScreen(
                      initialMonth: uri?.queryParameters['month'],
                    ),
                  ),
                );
              }
              return null;
            },
            onUnknownRoute: (settings) {
              final routeName = settings.name ?? '';
              if (AuthFlowService.isAuthCallbackRouteName(routeName)) {
                return MaterialPageRoute(
                  builder: (_) => const AuthCallbackScreen(),
                  settings: settings,
                );
              }

              return MaterialPageRoute(
                builder: (_) => const LandingPage(),
                settings: settings,
              );
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
  Timer? _bootstrapTimer;
  static const Duration _minSplashDuration = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    _bootstrapTimer = Timer(_minSplashDuration, () {
      if (mounted) {
        setState(() {
          _splashComplete = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _bootstrapTimer?.cancel();
    super.dispose();
  }

  Stream<AuthState> _safeAuthStateStream() {
    try {
      return Supabase.instance.client.auth.onAuthStateChange;
    } catch (error) {
      debugPrint(
          'Supabase not initialized; falling back to landing page: $error');
      return const Stream.empty();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_splashComplete) {
      return const SplashScreen();
    }

    if (kIsWeb && AuthFlowService.isAuthCallbackUri(Uri.base)) {
      return const AuthCallbackScreen();
    }

    // Auth state is driven ONLY by Supabase — no Firebase Auth dependency
    return StreamBuilder<AuthState>(
      stream: _safeAuthStateStream(),
      builder: (context, snapshot) {
        try {
          final supabaseUser = Supabase.instance.client.auth.currentUser;
          final authEvent = snapshot.data?.event;

          if (authEvent == AuthChangeEvent.passwordRecovery) {
            return const ResetPasswordScreen();
          }

          // Only let confirmed users through. Check the restored session
          // immediately so relaunching the app does not wait forever for a
          // fresh auth stream event.
          if (AuthFlowService.isConfirmedUser(supabaseUser)) {
            return const MembershipGate(child: MainTabsScreen());
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          return const LandingPage();
        } catch (error) {
          debugPrint(
              'Failed to read Supabase auth state; falling back to landing page: $error');
          return const LandingPage();
        }
      },
    );
  }
}
