import 'dart:convert';

import 'rule_set.dart';

/// Archivo pequeño en una dirección estable que anuncia la última versión de
/// las reglas. La app lo lee primero y solo descarga [rulesUrl] si [version]
/// es mayor que la que ya tiene.
///
/// ```json
/// {
///   "version": 3,
///   "schema_version": 1,
///   "rules_url": "https://raw.githubusercontent.com/…/<commit>/rules.json",
///   "sha256": "…64 hex…"
/// }
/// ```
class RulesManifest {
  const RulesManifest({
    required this.version,
    required this.schemaVersion,
    required this.rulesUrl,
    required this.sha256,
  });

  /// Lanza [RulesFormatException] si el texto no es un manifest válido.
  factory RulesManifest.fromJsonString(String source) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException catch (e) {
      throw RulesFormatException('Manifest: JSON inválido: ${e.message}');
    }
    if (json is! Map<String, Object?>) {
      throw RulesFormatException('Manifest: la raíz debe ser un objeto');
    }
    final version = json['version'];
    if (version is! int || version < 1) {
      throw RulesFormatException('Manifest: "version" debe ser un entero ≥ 1');
    }
    final schemaVersion = json['schema_version'];
    if (schemaVersion is! int || schemaVersion < 1) {
      throw RulesFormatException(
          'Manifest: "schema_version" debe ser un entero ≥ 1');
    }
    final rawUrl = json['rules_url'];
    final url = rawUrl is String ? Uri.tryParse(rawUrl) : null;
    if (url == null || url.scheme != 'https' || url.host.isEmpty) {
      throw RulesFormatException('Manifest: "rules_url" debe ser https');
    }
    final sha256 = json['sha256'];
    if (sha256 is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha256)) {
      throw RulesFormatException(
          'Manifest: "sha256" debe ser 64 caracteres hexadecimales en '
          'minúscula');
    }
    return RulesManifest(
      version: version,
      schemaVersion: schemaVersion,
      rulesUrl: url,
      sha256: sha256,
    );
  }

  final int version;
  final int schemaVersion;
  final Uri rulesUrl;

  /// SHA-256 del archivo de reglas, en hexadecimal minúscula.
  final String sha256;
}
