import 'dart:convert';

import 'civil_date.dart';

/// El JSON de reglas no cumple el esquema o trae valores fuera de rango.
class RulesFormatException implements Exception {
  RulesFormatException(this.message);

  final String message;

  @override
  String toString() => 'RulesFormatException: $message';
}

/// El JSON usa un `schema_version` más nuevo del que esta versión de la app
/// sabe leer. No es un error del archivo: hay que actualizar la app.
class RulesSchemaTooNewException extends RulesFormatException {
  RulesSchemaTooNewException(this.schemaVersion)
      : super('"schema_version" $schemaVersion es más nuevo que '
            '$supportedRulesSchemaVersion');

  final int schemaVersion;

  @override
  String toString() => 'RulesSchemaTooNewException: $message';
}

/// Versión del formato del JSON que esta app entiende. Subirla solo cuando
/// cambie la forma del archivo (no por valores nuevos).
const supportedRulesSchemaVersion = 1;

/// Máximo de días que puede durar una entrada provisional.
const maxProvisionalDays = 90;

/// Reglas que admiten entradas provisionales: las que cambian cada año por
/// decreto y pueden faltar los primeros días de enero.
const provisionalRuleKeys = {'smmlv', 'auxilio_transporte'};

/// No hay versión de una regla vigente en la fecha pedida. Nunca se inventa
/// un valor: el que llama decide qué mostrar.
class RuleNotFoundException implements Exception {
  RuleNotFoundException(this.key, this.date);

  final String key;
  final CivilDate date;

  @override
  String toString() => 'RuleNotFoundException: sin "$key" vigente el $date';
}

/// Un valor de regla con su vigencia. Ambos extremos son inclusivos;
/// [to] nulo significa "sin fecha de fin".
///
/// Una versión [provisional] repite el valor anterior mientras sale el
/// oficial (p. ej. el salario mínimo de enero antes del decreto). El cargador
/// exige que sea la última, que dure como máximo [maxProvisionalDays] días y
/// que su valor sea igual al de la versión anterior: nunca es un valor nuevo.
class RuleVersion {
  const RuleVersion({
    required this.from,
    required this.to,
    required this.value,
    this.provisional = false,
  });

  final CivilDate from;
  final CivilDate? to;
  final int value;
  final bool provisional;

  bool covers(CivilDate date) =>
      !date.isBefore(from) && (to == null || !date.isAfter(to!));
}

/// Una regla y todas sus versiones, ordenadas, contiguas y sin solaparse.
class Rule {
  Rule(this.key, List<RuleVersion> versions)
      : versions = List.unmodifiable(versions);

  final String key;
  final List<RuleVersion> versions;

  /// Valor vigente en [date]. Lanza [RuleNotFoundException] si no hay.
  int valueOn(CivilDate date) {
    for (final version in versions) {
      if (version.covers(date)) return version.value;
    }
    throw RuleNotFoundException(key, date);
  }
}

/// Rango aceptado para cada clave del JSON. Lo que no esté aquí se rechaza.
const _ranges = <String, (int, int)>{
  'recargo_nocturno_pct': (0, 300),
  'extra_diurna_pct': (0, 300),
  'extra_nocturna_pct': (0, 300),
  'recargo_dominical_festivo_pct': (0, 300),
  'divisor_hora_ordinaria': (150, 300),
  'jornada_maxima_semanal_min': (60, 60 * 60),
  'inicio_nocturno_min': (0, 24 * 60 - 1),
  'fin_nocturno_min': (0, 24 * 60 - 1),
  'smmlv': (100000, 100000000),
  'auxilio_transporte': (0, 10000000),
  'auxilio_transporte_tope_smmlv': (1, 10),
  'salud_empleado_pct': (0, 300),
  'pension_empleado_pct': (0, 300),
};

/// Una regla que en un rango de fechas usa un valor provisional.
class ProvisionalValue {
  const ProvisionalValue({required this.key, required this.version});

  final String key;
  final RuleVersion version;

  /// Año del valor que se repite (el vigente el día antes de la provisional).
  int get basedOnYear => version.from.addDays(-1).year;
}

/// Todas las reglas, leídas de `assets/rules/rules.json`.
class RuleSet {
  RuleSet._(this.version, this.schemaVersion, this.coverageFrom, this._rules);

  /// Lee y valida el JSON. Lanza [RulesFormatException] ante cualquier
  /// problema: el que llama debe caer a la copia empaquetada.
  factory RuleSet.fromJsonString(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw RulesFormatException('JSON inválido: ${e.message}');
    }
    return RuleSet.fromJson(decoded);
  }

  factory RuleSet.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw RulesFormatException('La raíz debe ser un objeto');
    }
    // El esquema va primero: un archivo más nuevo puede traer claves que
    // esta app no conoce, y eso no lo hace inválido.
    final schemaVersion = json['schema_version'];
    if (schemaVersion is! int || schemaVersion < 1) {
      throw RulesFormatException('"schema_version" debe ser un entero ≥ 1');
    }
    if (schemaVersion > supportedRulesSchemaVersion) {
      throw RulesSchemaTooNewException(schemaVersion);
    }
    final version = json['version'];
    if (version is! int || version < 1) {
      throw RulesFormatException('"version" debe ser un entero ≥ 1');
    }
    final coverageFrom = _parseDate(json['cobertura_desde'], 'cobertura_desde');
    final rulesJson = json['reglas'];
    if (rulesJson is! Map<String, Object?>) {
      throw RulesFormatException('"reglas" debe ser un objeto');
    }
    for (final key in rulesJson.keys) {
      if (!_ranges.containsKey(key)) {
        throw RulesFormatException('Regla desconocida: "$key"');
      }
    }
    final rules = <String, Rule>{};
    for (final MapEntry(key: key, value: range) in _ranges.entries) {
      rules[key] = _parseRule(key, rulesJson[key], range);
    }
    return RuleSet._(version, schemaVersion, coverageFrom, rules);
  }

  /// Versión del archivo; el remoto solo se acepta si es mayor a la local.
  final int version;

  /// Versión del formato del archivo (ver [supportedRulesSchemaVersion]).
  final int schemaVersion;

  /// Primera fecha para la que la app calcula. Antes de esta fecha no se
  /// garantiza que todas las reglas estén cargadas.
  final CivilDate coverageFrom;

  final Map<String, Rule> _rules;

  Rule get nightSurchargePct => _rules['recargo_nocturno_pct']!;
  Rule get overtimeDayPct => _rules['extra_diurna_pct']!;
  Rule get overtimeNightPct => _rules['extra_nocturna_pct']!;
  Rule get sundayHolidaySurchargePct =>
      _rules['recargo_dominical_festivo_pct']!;
  Rule get ordinaryHourDivisor => _rules['divisor_hora_ordinaria']!;
  Rule get weeklyMaxMinutes => _rules['jornada_maxima_semanal_min']!;

  /// Minuto del día (0-1439) en que empieza el horario nocturno.
  Rule get nightStartMinute => _rules['inicio_nocturno_min']!;

  /// Minuto del día (0-1439) en que termina el horario nocturno.
  Rule get nightEndMinute => _rules['fin_nocturno_min']!;
  Rule get minimumWage => _rules['smmlv']!;
  Rule get transportAllowance => _rules['auxilio_transporte']!;
  Rule get transportAllowanceCapMinimumWages =>
      _rules['auxilio_transporte_tope_smmlv']!;
  Rule get healthEmployeePct => _rules['salud_empleado_pct']!;
  Rule get pensionEmployeePct => _rules['pension_empleado_pct']!;

  Iterable<Rule> get all => _rules.values;

  /// Valores provisionales que se usan en algún día entre [from] y [to].
  List<ProvisionalValue> provisionalBetween(CivilDate from, CivilDate to) => [
        for (final rule in _rules.values)
          for (final version in rule.versions)
            if (version.provisional &&
                !version.from.isAfter(to) &&
                (version.to == null || !version.to!.isBefore(from)))
              ProvisionalValue(key: rule.key, version: version),
      ];

  static Rule _parseRule(String key, Object? json, (int, int) range) {
    if (json is! List<Object?> || json.isEmpty) {
      throw RulesFormatException('"$key" debe ser una lista no vacía');
    }
    final (min, max) = range;
    final versions = <RuleVersion>[];
    for (final item in json) {
      if (item is! Map<String, Object?>) {
        throw RulesFormatException('"$key": cada versión debe ser un objeto');
      }
      final from = _parseDate(item['vigente_desde'], '$key.vigente_desde');
      final rawTo = item['vigente_hasta'];
      final to = rawTo == null ? null : _parseDate(rawTo, '$key.vigente_hasta');
      final value = item['valor'];
      if (value is! int) {
        throw RulesFormatException('"$key": "valor" debe ser entero');
      }
      if (value < min || value > max) {
        throw RulesFormatException(
            '"$key": valor $value fuera de rango [$min, $max]');
      }
      if (to != null && to.isBefore(from)) {
        throw RulesFormatException('"$key": vigente_hasta antes de desde');
      }
      final provisional = item['provisional'] ?? false;
      if (provisional is! bool) {
        throw RulesFormatException('"$key": "provisional" debe ser booleano');
      }
      versions.add(RuleVersion(
          from: from, to: to, value: value, provisional: provisional));
    }
    // Las versiones deben ir en orden y sin huecos: un hueco suele ser un
    // error de tipeo en una fecha, y es mejor fallar al cargar.
    for (var i = 1; i < versions.length; i++) {
      final previousTo = versions[i - 1].to;
      if (previousTo == null || versions[i].from != previousTo.addDays(1)) {
        throw RulesFormatException(
            '"$key": la versión ${i + 1} debe empezar el día siguiente '
            'al fin de la anterior');
      }
    }
    for (var i = 0; i < versions.length; i++) {
      if (versions[i].provisional) _checkProvisional(key, versions, i);
    }
    return Rule(key, versions);
  }

  static void _checkProvisional(String key, List<RuleVersion> versions, int i) {
    final version = versions[i];
    if (!provisionalRuleKeys.contains(key)) {
      throw RulesFormatException('"$key" no admite valores provisionales');
    }
    if (i == 0 || versions[i - 1].value != version.value) {
      throw RulesFormatException(
          '"$key": la provisional debe repetir el valor de la versión '
          'anterior');
    }
    if (i != versions.length - 1) {
      throw RulesFormatException(
          '"$key": la provisional debe ser la última versión; el valor '
          'oficial la reemplaza');
    }
    final to = version.to;
    if (to == null || to.isAfter(version.from.addDays(maxProvisionalDays - 1))) {
      throw RulesFormatException(
          '"$key": la provisional dura como máximo $maxProvisionalDays días');
    }
  }

  static CivilDate _parseDate(Object? json, String field) {
    if (json is! String) {
      throw RulesFormatException('"$field" debe ser una fecha AAAA-MM-DD');
    }
    try {
      return CivilDate.parse(json);
    } catch (_) {
      throw RulesFormatException('"$field" no es una fecha válida: $json');
    }
  }
}
