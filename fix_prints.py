import os

def replace_print_in_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
    
    # We only want to replace print( if it's used as a function call.
    # We shouldn't replace it if it's already debugPrint or part of another word.
    import re
    
    # Add import if we are replacing
    if re.search(r'\bprint\(', content):
        new_content = re.sub(r'\bprint\(', 'debugPrint(', content)
        
        # Check if foundation is imported
        if 'package:flutter/foundation.dart' not in new_content:
            # Add it after the first import
            first_import = new_content.find('import ')
            if first_import != -1:
                end_of_line = new_content.find('\n', first_import)
                new_content = new_content[:end_of_line+1] + "import 'package:flutter/foundation.dart';\n" + new_content[end_of_line+1:]
            else:
                new_content = "import 'package:flutter/foundation.dart';\n" + new_content
                
        with open(filepath, 'w') as f:
            f.write(new_content)

for root, dirs, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart'):
            replace_print_in_file(os.path.join(root, file))
