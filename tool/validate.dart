// Valida rules.json y manifest.json con el mismo cargador que usa la app.
// Corre en cada push (.github/workflows/validate.yml): si falla, el JSON no
// se publica.
//
//   dart run tool/validate.dart
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:netto_rules/netto_rules.dart';

import 'git_blob.dart';

void main() {
  var ok = true;
  void fail(String message) {
    stderr.writeln('✗ $message');
    ok = false;
  }

  // 1. rules.json: esquema, rangos, vigencias sin solapes ni huecos y
  //    provisionales (máximo 90 días, mismo valor que el año anterior).
  final rulesText = File('rules.json').readAsStringSync();
  RuleSet? rules;
  try {
    rules = RuleSet.fromJsonString(rulesText);
    print('✓ rules.json: versión ${rules.version}, esquema '
        '${rules.schemaVersion}');
  } on RulesFormatException catch (e) {
    fail('rules.json: ${e.message}');
  }

  // 2. manifest.json: lo que la app lee primero.
  final manifestFile = File('manifest.json');
  if (!manifestFile.existsSync()) {
    final history = Process.runSync('git', [
      'log',
      '--format=%H',
      '--',
      'manifest.json',
    ]);
    if ((history.stdout as String).trim().isEmpty) {
      print('· manifest.json aún no existe (primera publicación).');
    } else {
      fail('manifest.json fue borrado: la app ya no encontraría reglas.');
    }
    exit(ok ? 0 : 1);
  }

  RulesManifest manifest;
  try {
    manifest = RulesManifest.fromJsonString(manifestFile.readAsStringSync());
  } on RulesFormatException catch (e) {
    fail(e.message);
    exit(1);
  }
  if (manifest.schemaVersion > supportedRulesSchemaVersion) {
    fail('manifest: schema_version ${manifest.schemaVersion} es más nuevo '
        'que el del cargador ($supportedRulesSchemaVersion). Copia el '
        'cargador nuevo de la app.');
  }

  final commit = commitOf(manifest.rulesUrl);
  if (commit == null) {
    fail('manifest: rules_url debe ser '
        '${rulesUrlFor('<commit de 40 caracteres>')}');
    exit(1);
  }
  final blob = rulesBlobAt(commit);
  if (blob == null) {
    fail('manifest: el commit $commit no tiene rules.json en este '
        'repositorio (¿falta hacer push de ese commit?).');
    exit(1);
  }
  if (sha256.convert(blob).toString() != manifest.sha256) {
    fail('manifest: el sha256 no coincide con rules.json del commit '
        '$commit. Regenera con tool/update_manifest.dart.');
  }
  try {
    final published = RuleSet.fromJsonString(utf8.decode(blob));
    if (published.version != manifest.version) {
      fail('manifest: "version" ${manifest.version} pero rules.json del '
          'commit tiene ${published.version}.');
    }
    if (published.schemaVersion != manifest.schemaVersion) {
      fail('manifest: "schema_version" no coincide con rules.json del '
          'commit.');
    }
    print('✓ manifest.json: versión ${manifest.version}, commit '
        '${commit.substring(0, 7)}');
  } on RulesFormatException catch (e) {
    fail('rules.json del commit $commit: ${e.message}');
  }

  // 3. Lo que está en rules.json frente a lo publicado: cambiar valores
  //    sin subir la versión haría que la app nunca los descargue.
  if (rules != null) {
    final sameContent = const LineSplitter().convert(rulesText).join('\n') ==
        const LineSplitter().convert(utf8.decode(blob)).join('\n');
    if (rules.version < manifest.version) {
      fail('rules.json (v${rules.version}) es más viejo que lo publicado '
          '(v${manifest.version}).');
    } else if (rules.version == manifest.version && !sameContent) {
      fail('rules.json cambió pero sigue en la versión ${rules.version}: '
          'súbela para que la app lo descargue.');
    } else if (rules.version > manifest.version) {
      print('· rules.json v${rules.version} aún no está publicado: después '
          'del push corre tool/update_manifest.dart con su commit.');
    }
  }

  exit(ok ? 0 : 1);
}
