import 'dart:io';

/// Repositorio donde se publican las reglas. El manifest solo puede apuntar
/// aquí.
const publishedRepo = 'DanielBarrientos12/netto-rules';

/// URL de `rules.json` en un commit fijo.
Uri rulesUrlFor(String commit) => Uri.parse(
  'https://raw.githubusercontent.com/$publishedRepo/$commit/rules.json',
);

/// Commit de una URL de [rulesUrlFor], o nulo si la URL no tiene esa forma.
String? commitOf(Uri url) {
  final match = RegExp(
    '^https://raw\\.githubusercontent\\.com/$publishedRepo/([0-9a-f]{40})/rules\\.json\$',
  ).firstMatch('$url');
  return match?.group(1);
}

/// Hash completo de [ref], o nulo si no es un commit de este repositorio.
String? resolveCommit(String ref) {
  final result = Process.runSync('git', [
    'rev-parse',
    '--verify',
    '--quiet',
    '$ref^{commit}',
  ]);
  return result.exitCode == 0 ? (result.stdout as String).trim() : null;
}

/// Bytes exactos de `rules.json` en [commit], tal como los sirve GitHub
/// (sin conversión de fin de línea), o nulo si no existe.
List<int>? rulesBlobAt(String commit) {
  final result = Process.runSync(
    'git',
    ['show', '$commit:rules.json'],
    stdoutEncoding: null,
  );
  return result.exitCode == 0 ? result.stdout as List<int> : null;
}
