import os

def replace_in_file(filepath):
    with open(filepath, 'r') as f:
        content = f.read()
    
    if '.withOpacity(' in content:
        new_content = content.replace('.withOpacity(', '.withValues(alpha: ')
        with open(filepath, 'w') as f:
            f.write(new_content)

for root, dirs, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart'):
            replace_in_file(os.path.join(root, file))
