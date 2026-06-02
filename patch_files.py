import os

# 1. UserRoleProvider
user_role_path = 'lib/providers/user_role_provider.dart'
user_role_content = """import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_profile.dart';

class UserRoleProvider with ChangeNotifier {
  UserProfile? _userProfile;
  bool _isLoading = true;

  UserProfile? get userProfile => _userProfile;
  UserProfile? get user => _userProfile;
  bool get isLoading => _isLoading;
  bool get isDeveloper => _userProfile?.isDeveloper ?? false;

  // Legacy accessor - returns the first role or 'Member'
  // Updated to use the new role list
  String get role => _userProfile?.roles.isNotEmpty == true ? _userProfile!.roles.first : "Member";

  UserRoleProvider() {
    _init();
  }

  void _init() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user != null) {
        fetchUserProfile();
      } else {
        _userProfile = null;
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  Future<void> fetchUserProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    _isLoading = true;
    notifyListeners();

    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        _userProfile = UserProfile.fromMap(doc.data() as Map<String, dynamic>);
      }
    } catch (e) {
      print("Error fetching user profile: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setUserProfile(UserProfile profile) {
    _userProfile = profile;
    notifyListeners();
  }

  bool hasRole(String role) {
    if (_userProfile == null) return false;
    return _userProfile!.roles.contains(role);
  }
  
  // Use Capabilities instead of string matching
  bool get canManageEvents => _userProfile?.capabilities.canCreateEvents ?? false;
}
"""

with open(user_role_path, 'w') as f:
    f.write(user_role_content)
    print(f"Patched {user_role_path}")


# 2. AppColors
app_colors_path = 'lib/theme/app_colors.dart'
app_colors_content = """import 'package:flutter/material.dart';

class AppColors {
  // --- CORE PALETTE ---
  
  // Primary (Deep Navy - from logo)
  static const Color primary = Color(0xFF10141C); 
  static const Color primaryVariant = Color(0xFF1E2430); // Slightly lighter navy/charcoal
  
  // Secondary (Warm Gold - from logo)
  static const Color secondary = Color(0xFFD2982C);
  static const Color goldHighlight = Color(0xFFFFBF00);
  
  // Neutral / Surface
  static const Color background = Color(0xFFF8F9FA); // Off-white/Light Gray for background
  static const Color surface = Color(0xFFFFFFFF); // Pure white for cards
  
  static const Color backgroundDark = Color(0xFF10141C); // Dark Navy background
  static const Color surfaceDark = Color(0xFF1E2430); // Lighter Navy for cards
  
  // Text
  static const Color textPrimary = Color(0xFF1A1A1A); // Near Black
  static const Color textSecondary = Color(0xFF757575); // Muted Gray
  
  static const Color textPrimaryDark = Color(0xFFFFFFFF);
  static const Color textSecondaryDark = Color(0xFFB0B0B0);

  // Functional
  static const Color error = Color(0xFFB00020);
  static const Color success = Color(0xFF4CAF50);
  static const Color warning = Color(0xFFFFC107);

  // --- GRADIENTS ---
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, Color(0xFF2C3E50)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [secondary, goldHighlight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  static const LinearGradient darkSurfaceGradient = LinearGradient(
    colors: [Color(0xFF1E2430), Color(0xFF10141C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  
  // --- LEGACY ALIASES (Mappings to new palette) ---
  static const Color gold = secondary;
  static const Color amber = goldHighlight;
  static const Color deepCharcoal = textPrimary;
  static const Color darkNavy = primary;
  static const Color warmGray = background;
  static const Color pureWhite = surface;
  static const Color burntOrange = Color(0xFFC45427); // Keeping original accent as tertiary option
  static const Color softBrown = Color(0xFFD26A4F);
  static const Color tertiary = burntOrange;
  
  static const Color glassBlack = Color(0x99000000); 
  static const Color glassWhite = Color(0x99FFFFFF);
}
"""

with open(app_colors_path, 'w') as f:
    f.write(app_colors_content)
    print(f"Patched {app_colors_path}")


# 3. UserProfile
user_profile_path = 'lib/models/user_profile.dart'
try:
    with open(user_profile_path, 'r') as f:
        content = f.read()

    if 'bool get isPrayerWarrior' not in content:
        # Find the last closing brace
        last_brace_index = content.rfind('}')
        if last_brace_index != -1:
            new_content = content[:last_brace_index] + """
  bool get isPrayerWarrior => roles.contains('Prayer Warrior');
  bool get isActingPastor => roles.contains('Acting Pastor');
  bool get isAssistantPastor => roles.contains('Assistant Pastor');
}
"""
            with open(user_profile_path, 'w') as f:
                f.write(new_content)
                print(f"Patched {user_profile_path}")
        else:
            print(f"Could not patch {user_profile_path}, closing brace not found")
    else:
        print(f"{user_profile_path} already has getters")
except Exception as e:
    print(f"Error accessing {user_profile_path}: {e}")

# 4. AppDrawer
app_drawer_path = 'lib/widgets/app_drawer.dart'
# We will use string replacement for the constructor because rewriting the whole file is risky if I missed something in cat output
# But since cat output was complete, let's try to overwrite carefully or use precise replacement.
# Precise replacement is safer for potentially large files where I might have missed scroll buffer, but here I saw the whole file.
# Wait, I can just replace the constructor line!
try:
    with open(app_drawer_path, 'r') as f:
        drawer_content = f.read()
    
    # Check if already patched
    if 'this.userProfile' in drawer_content:
        print(f"{app_drawer_path} already patched")
    else:
        # Add field
        drawer_content = drawer_content.replace('class AppDrawer extends StatelessWidget {', 'class AppDrawer extends StatelessWidget {\\n  final UserProfile? userProfile;')
        # Update constructor
        drawer_content = drawer_content.replace('const AppDrawer({super.key});', 'const AppDrawer({super.key, this.userProfile});')
        
        with open(app_drawer_path, 'w') as f:
            f.write(drawer_content)
            print(f"Patched {app_drawer_path}")
except Exception as e:
    print(f"Error accessing {app_drawer_path}: {e}")

