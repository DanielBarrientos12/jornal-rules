// Escribe manifest.json apuntando a rules.json de un commit ya publicado.
//
//   dart run tool/update_manifest.dart <commit>
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:jornal_rules/jornal_rules.dart';

import 'git_blob.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Uso: dart run tool/update_manifest.dart <commit>');
    exit(64);
  }
  final commit = resolveCommit(args.single);
  final blob = commit == null ? null : rulesBlobAt(commit);
  if (commit == null || blob == null) {
    stderr.writeln('✗ ${args.single} no es un commit con rules.json.');
    exit(1);
  }
  final RuleSet rules;
  try {
    rules = RuleSet.fromJsonString(utf8.decode(blob));
  } on RulesFormatException catch (e) {
    stderr.writeln('✗ rules.json del commit no es válido: ${e.message}');
    exit(1);
  }

  final manifest = {
    'version': rules.version,
    'schema_version': rules.schemaVersion,
    'rules_url': '${rulesUrlFor(commit)}',
    'sha256': sha256.convert(blob).toString(),
  };
  File('manifest.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
  print('✓ manifest.json → versión ${rules.version}, commit '
      '${commit.substring(0, 7)}');
}
