# netto-rules

Reglas de cálculo de **Netto** (recargos, horas extra, salario mínimo, auxilio de transporte, salud y pensión en Colombia), con su vigencia. La app las descarga para no depender de una actualización en la tienda cada vez que cambia un valor.

La app no envía nada a este repositorio: solo lee dos archivos públicos.

## Archivos

| Archivo | Qué es |
|---|---|
| `manifest.json` | Lo que la app lee primero, en una dirección estable (`main`). Dice la última `version`, el `schema_version`, la URL de `rules.json` **en un commit fijo** y su `sha256`. |
| `rules.json` | Las reglas. Cada valor tiene `vigente_desde` / `vigente_hasta` y su `fuente`. |
| `lib/src/` | El cargador de reglas, **copiado tal cual** de la app (`lib/core/rules_engine/`). No se edita aquí. |
| `tool/validate.dart` | Valida `rules.json` y `manifest.json` con ese mismo cargador. |
| `tool/update_manifest.dart` | Genera `manifest.json` para un commit. |
| `.github/workflows/validate.yml` | Corre el validador en cada push. |

## Qué valida

- `rules.json`: esquema, claves conocidas, rangos razonables (porcentajes 0-300), vigencias en orden, sin solapes ni huecos, y valores provisionales bien formados.
- `manifest.json`: forma, URL a `rules.json` de un commit de este repositorio, que el `sha256` coincida con ese archivo byte a byte, y que su versión y esquema sean los del archivo.
- Que no se cambien valores sin subir `version` (la app solo descarga versiones mayores).

## Cómo la usa la app

1. Al abrir (como máximo cada 12 h) o con **Buscar actualización** en Ajustes, lee `manifest.json`.
2. Si `version` no es mayor que la suya, no descarga nada.
3. Si es mayor, descarga `rules_url`, verifica el `sha256`, valida con el cargador y exige que la versión coincida.
4. Si algo falla (sin internet, timeout, hash distinto, JSON inválido), sigue con su copia en caché o la empaquetada, sin mostrar errores.
5. Si `schema_version` es más nuevo de lo que entiende, ignora las reglas y sugiere actualizar la app.

## Publicar reglas nuevas

```sh
dart pub get

# 1. Editar rules.json y SUBIR "version".
dart run tool/validate.dart        # avisa que aún no está publicado
git commit -am "Reglas v3: SMMLV 2027 (Decreto …)"
git push                           # el workflow valida

# 2. Apuntar el manifest a ese commit.
dart run tool/update_manifest.dart HEAD
dart run tool/validate.dart
git commit -am "Manifest: reglas v3"
git push
```

Desde ese momento la app recibe la versión nueva. Se hace en dos commits porque `rules_url` apunta al commit del paso 1: lo publicado nunca cambia aunque `main` siga avanzando.

## Valores provisionales

`smmlv` y `auxilio_transporte` cambian cada año por decreto. Para que la app no se quede sin cálculo el 1 de enero, su última versión puede ser **provisional**:

```json
{ "vigente_desde": "2027-01-01", "vigente_hasta": "2027-03-31", "valor": 1750905, "provisional": true, "fuente": "Provisional: repite 2026 mientras sale el decreto de 2027" }
```

El cargador exige:

- que repita **el mismo valor** de la versión anterior (nunca se inventa una cifra);
- que sea la **última** versión;
- que dure **como máximo 90 días**.

La app avisa "Valores provisionales" en el detalle del mes. Cuando sale el decreto, se reemplaza por el valor oficial en una versión mayor. Pasado el plazo sin valor oficial, la app muestra "Estamos actualizando las reglas de [año]".

## Cambios de formato

Si cambia la **forma** del archivo (no los valores), se sube `schema_version` y el cargador de la app. Las versiones viejas de la app ignoran ese archivo y sugieren actualizarse. Después hay que copiar aquí el cargador nuevo (`lib/core/rules_engine/{civil_date,rule_set,rules_manifest}.dart` → `lib/src/`).

## Fuentes

Cada valor cita su norma en `fuente`. Lo pendiente de verificar con fuente primaria está en la lista previa a la publicación del proyecto de la app.
