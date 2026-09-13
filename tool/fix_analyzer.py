path = r'r:\FlutterUnitTestGenerator\lib\src\analysis\dart_source_analyzer.dart'

with open(path, 'r') as f:
    content = f.read()

old = "p.type?.toString() ?? 'dynamic'"
new = "p.toString()"

count = content.count(old)
print(f'Found {count} occurrences')

content = content.replace(old, new)

with open(path, 'w') as f:
    f.write(content)

print('Done')
