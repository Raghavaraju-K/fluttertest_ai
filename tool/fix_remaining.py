path = r'r:\FlutterUnitTestGenerator\test\unit\repairer_test.dart'

with open(path, 'r') as f:
    content = f.read()

# Fix line 89: runWith('...\\n...')
content = content.replace(
    "runWith('Expected: exactly one matching node\\\\n  found: 0')",
    "'Expected: exactly one matching node\\\\n  found: 0'"
)

# Fix line 117: runWith('...' '...')
content = content.replace(
    """runWith('BlocProvider.of() called with a context that does not '
          'contain a Bloc')""",
    """'BlocProvider.of() called with a context that does not contain a Bloc'"""
)

with open(path, 'w') as f:
    f.write(content)

print('Fixed remaining runWith calls')
