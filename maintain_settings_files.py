import os

# 1. Update main.dart
main_path = 'lib/main.dart'
try:
    with open(main_path, 'r') as f:
        main_content = f.read()
    
    if '/settings': (context) => const SettingsScreen(),' not in main_content:
        # Add import
        settings_import = "import 'screens/settings/settings_screen.dart';"
        if settings_import not in main_content:
            main_content = settings_import + '\n' + main_content
            
        # Add route
        route_marker = 'routes: {'
        if route_marker in main_content:
            replacement = "routes: {\n        '/settings': (context) => const SettingsScreen(),"
            main_content = main_content.replace(route_marker, replacement)
            
            with open(main_path, 'w') as f:
                f.write(main_content)
            print("Updated main.dart with settings route")
        else:
            print("Could not find routes map in main.dart")

except Exception as e:
    print(f"Error updating main.dart: {e}")

# 2. Update app_drawer.dart
drawer_path = 'lib/widgets/app_drawer.dart'
try:
    with open(drawer_path, 'r') as f:
        drawer_content = f.read()

    # Avoid duplicate
    if "text: 'Settings'" not in drawer_content:
        # Insert before Help & Support or Logout
        target_marker = "_buildDrawerItem(\n            icon: Icons.help_outline,"
        
        settings_item = '''_buildDrawerItem(
            icon: Icons.settings,
            text: 'Settings',
            onTap: () => Navigator.pushNamed(context, '/settings'),
          ),
          
          '''
        
        if target_marker in drawer_content:
            drawer_content = drawer_content.replace(target_marker, settings_item + target_marker)
            with open(drawer_path, 'w') as f:
                f.write(drawer_content)
            print("Updated app_drawer.dart with Settings item")
        else:
             # Fallback: try inserting before Logout
             logout_marker = "icon: Icons.logout"
             if logout_marker in drawer_content:
                  # Need to find the _buildDrawerItem call containing logout
                  # This is riskier with string replacement. Let's try to find "const Divider()," before logout
                  # Based on previous file content, there is a Divider before logout.
                  
                  # Safer anchor: Help & Support is best. If not found, look for Profile.
                  profile_marker = "text: 'Profile',"
                  if profile_marker in drawer_content:
                      # Insert AFTER Profile (harder with replace).
                      pass
                  print("WARNING: Could not find anchor for Settings item in Drawer")

except Exception as e:
     print(f"Error updating app_drawer.dart: {e}")

