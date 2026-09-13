path = r'r:\FlutterUnitTestGenerator\test\unit\repairer_test.dart'

with open(path, 'rb') as f:
    raw = f.read()

# Replace: runWith('Expected: exactly one matching node\n  found: 0')
# With:     'Expected: exactly one matching node\n  found: 0'
old = b"runWith('Expected: exactly one matching node\\n  found: 0')"
new = b"'Expected: exactly one matching node\\n  found: 0'"

if old in raw:
    raw = raw.replace(old, new)
    with open(path, 'wb') as f:
        f.write(raw)
    print('Fixed')
else:
    print('Not found')
    # Show what's around line 89
    lines = raw.decode('utf-8').split('\n')
    for i, line in enumerate(lines[85:95], start=86):
        print(f'{i}: {line}')
