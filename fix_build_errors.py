import os

def fix_community_screen():
    path = "lib/screens/community/community_feed_screen.dart"
    try:
        with open(path, 'r') as f:
            content = f.read()
        
        # specific bad pattern literal \n
        bad_pattern = r"final userProvider = Provider.of<UserRoleProvider>(context);\n    final churchId ="
        # Replace literal \n with actual newline
        new_pattern = "final userProvider = Provider.of<UserRoleProvider>(context);\n    final churchId ="
        
        if bad_pattern in content:
            new_content = content.replace(bad_pattern, new_pattern)
            with open(path, 'w') as f:
                f.write(new_content)
            print(f"Fixed {path}")
        else:
            print(f"Pattern not found in {path}")
            # Fallback: maybe it's just ;\\n
            if r";\n" in content:
                 print(f"Found ;\\n in {path}, attempting generic fix")
                 new_content = content.replace(r";\n", ";\n")
                 with open(path, 'w') as f:
                     f.write(new_content)
    except Exception as e:
        print(f"Error fixing {path}: {e}")

def fix_app_theme():
    path = "lib/theme/app_theme.dart"
    try:
        with open(path, 'r') as f:
            content = f.read()
        
        # Replace CardTheme( with CardThemeData(
        # Note: We must ensure we don't break import or other usages if logic differs.
        # But context is 'cardTheme: CardTheme('
        
        if "cardTheme: CardTheme(" in content:
            new_content = content.replace("cardTheme: CardTheme(", "cardTheme: CardThemeData(")
            with open(path, 'w') as f:
                f.write(new_content)
            print(f"Fixed {path}")
        else:
            print(f"Pattern 'cardTheme: CardTheme(' not found in {path}")
    except Exception as e:
        print(f"Error fixing {path}: {e}")

def fix_signup_screen():
    path = "lib/screens/signup screen/signup_screen.dart"
    try:
        with open(path, 'r') as f:
            content = f.read()
        
        if "isFullWidth: true," in content:
            new_content = content.replace("isFullWidth: true,", "")
            with open(path, 'w') as f:
                f.write(new_content)
            print(f"Fixed {path}")
        else:
            print(f"Pattern 'isFullWidth: true,' not found in {path}")
    except Exception as e:
        print(f"Error fixing {path}: {e}")

if __name__ == "__main__":
    fix_community_screen()
    fix_app_theme()
    fix_signup_screen()
