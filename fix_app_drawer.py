
path = 'lib/widgets/app_drawer.dart'
with open(path, 'r') as f:
    content = f.read()

# Replace literal \n with actual newline
if '\\n' in content:
    content = content.replace('\\n', '\n')
    with open(path, 'w') as f:
        f.write(content)
    print(f"Fixed {path}")
else:
    print(f"No literal \\n found in {path}")
