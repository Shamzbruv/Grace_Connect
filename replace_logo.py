
import sys

path = "lib/screens/login screen/login_screen.dart"

with open(path, 'r') as f:
    content = f.read()

# Target block (approximate, since we ran sed replacement already)
# We know it starts with Container( width: 100
# And ends with child: Icon( FontAwesomeIcons.handsPraying ... ) ... ),

start_marker = "Container(\n                  width: 100,\n                  height: 100,"
end_marker = "child: Icon(\n                    FontAwesomeIcons.handsPraying,"

# We can find the start index
start_idx = content.find(start_marker)
if start_idx == -1:
    print("Could not find start marker")
    # Try finding with altered spacing or just simple search
    start_marker = "width: 100,\n                  height: 100,"
    start_idx = content.find(start_marker)
    if start_idx != -1:
        # Move back to Container
        start_idx = content.rfind("Container", 0, start_idx)

if start_idx != -1:
    # Find the end of this container widget. Converting to balanced bracket finding is safer.
    # But let's look for the Icon part
    icon_idx = content.find("FontAwesomeIcons.handsPraying", start_idx)
    if icon_idx != -1:
        # scan for the closing parens of the Container.
        # It's roughly: Icon(...) -> child: -> ), -> decoration: -> ), -> Container(
        # We can just look for the closing of the child: Icon contents.
        # Let's replace the whole chunk blindly if we find enough context.
        
        # Simpler approach: Locate the distinct gradient lines we know exist
        # colors: [AppTheme.primaryGold, Color(0xFF3B7DDD)],
        
        # Let's construct a targeted replace based on what we see in the file now.
        pass

# Hard replace approach for the gradient background
content = content.replace("colors: [Color(0xFFF5F9FF), Color(0xFFE8F0FE)],", 
                          "colors: [Color(0xFFFFF8E1), Color(0xFFFFF3E0)],")

# Replace the logo block
# The block is roughly:
logo_block_SEARCH = """                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.primaryGold, Color(0xFF3B7DDD)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primaryGold.withAlpha(76),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    FontAwesomeIcons.handsPraying,
                    color: Colors.white,
                    size: 40,
                  ),
                ),"""

logo_block_REPLACE = """                Image.asset(
                    'assets/logo.png',
                    width: 150,
                    height: 150,
                    fit: BoxFit.contain,
                  ),"""

if logo_block_SEARCH in content:
    content = content.replace(logo_block_SEARCH, logo_block_REPLACE)
else:
    print("Exact block match failed. Attempting looser match.")
    # Fallback: regex or manual search
    # Let's just try to find the lines
    pass

with open(path, 'w') as f:
    f.write(content)
