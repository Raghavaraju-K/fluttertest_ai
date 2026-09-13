path = r'r:\FlutterUnitTestGenerator\test\unit\repairer_test.dart'

with open(path, 'r') as f:
    content = f.read()

# Replace all `runWith('...')` calls in repair() with the string directly
# Pattern: .repair(root.path, runWith('...'))
# Replace with: .repair(root.path, '...')
import re

def replace_run_with(match):
    string_content = match.group(1)
    # Unescape \' to '
    string_content = string_content.replace("\\'", "'")
    return f".repair(root.path, '{string_content}')"

content = re.sub(
    r"\.repair\(root\.path, runWith\('((?:[^'\\]|\\.)*)'\)\)",
    replace_run_with,
    content
)

with open(path, 'w') as f:
    f.write(content)

print('Fixed repairer_test.dart')
