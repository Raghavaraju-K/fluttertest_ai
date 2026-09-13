import '../project/dart_symbols.dart';

/// Synthesizes conservative literal argument values for supported parameter
/// types so every generated call compiles and stays meaningful.
class ValueFixtures {
  const ValueFixtures();

  /// Whether a value can be synthesized for this parameter type at all.
  bool isSupported(ParameterInfo parameter) => typical(parameter) != null;

  /// A representative non-empty literal, e.g. `'sample'` for [String].
  String? typical(ParameterInfo parameter) =>
      _literal(parameter, typical: true);

  /// An empty or zero literal, e.g. `''` for [String], `null` for nullable.
  String? empty(ParameterInfo parameter) => _literal(parameter, typical: false);

  String? _literal(ParameterInfo parameter, {required bool typical}) {
    final type = parameter.typeSource;
    if (type == 'dynamic') return typical ? "'sample'" : 'null';
    if (type == 'String') return typical ? "'sample'" : "''";
    if (type == 'int' || type == 'num') return typical ? '1' : '0';
    if (type == 'double') return typical ? '1.0' : '0.0';
    if (type == 'bool') return typical ? 'true' : 'false';
    if (type == 'String?') return typical ? "'sample'" : 'null';
    if (type == 'int?' || type == 'num?') return typical ? '1' : 'null';
    if (type == 'double?') return typical ? '1.0' : 'null';
    if (type == 'bool?') return typical ? 'true' : 'null';
    if (type.startsWith('List<') || type.startsWith('Iterable<')) {
      return _list(type, typical);
    }
    if (type.startsWith('Set<')) return _set(type, typical);
    if (type.startsWith('Map<')) return _map(type, typical);
    return null;
  }

  String? _list(String type, bool typical) {
    final inner = _inner(type);
    if (inner == null) return null;
    return 'const <$inner>[${typical ? _innerLiteral(inner) : ''}]';
  }

  String? _set(String type, bool typical) {
    final inner = _inner(type);
    if (inner == null) return null;
    return 'const <$inner>{${typical ? _innerLiteral(inner) : ''}}';
  }

  String? _map(String type, bool typical) {
    final body = type.substring(type.indexOf('<') + 1, type.length - 1);
    final comma = body.indexOf(',');
    if (comma < 0) return null;
    final key = body.substring(0, comma).trim();
    final value = body.substring(comma + 1).trim();
    if (key.endsWith('?') || value.endsWith('?')) return null;
    return 'const <$body>{${typical ? "'k': 'v'" : ''}}';
  }

  String? _inner(String type) {
    final inner = type.substring(type.indexOf('<') + 1, type.length - 1);
    if (inner.contains(',') || inner.contains('<') || inner.endsWith('?')) {
      return null;
    }
    return inner;
  }

  String _innerLiteral(String inner) => switch (inner) {
        'String' => "'a'",
        'int' || 'num' => '1',
        'double' => '1.0',
        'bool' => 'true',
        // Unknown element types fall back to an empty collection, which is
        // still a valid, compiling literal.
        _ => '',
      };
}
