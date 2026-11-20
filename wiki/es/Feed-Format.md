# Feed Format

El **feed** es lo que VDLU sirve sobre la línea y desde lo que el dispositivo se actualiza. Es un directorio estático plano, servible por cualquier cosa (GitHub Pages, un destino rsync, una ruta `file://`):

```
<source>/
  manifest.json          # the signed description of the current release
  blobs/<sha256>         # one blob per distinct file content
  blobs/<sha256>.gz      # (when the blob is stored gzipped)
```

El módulo en sí también envía un archivo extra, `baseline.json`, dentro del `.zip` (no servido desde el feed). El productor que construye todo esto se describe en [[Producer]]; esta página es el contrato sobre la línea.

---

## manifest.json

El manifiesto es la descripción completa de una release: cada archivo en el árbol de destino, qué eliminar, y la firma sobre todo el conjunto.

```json
{
  "schema": 1,
  "module": "demo",
  "version": 106,
  "version_name": "v106",
  "built": "2026-11-19T12:00:00Z",
  "engine_min": 3,
  "channel": "stable",
  "key_id": "release-2026",
  "files": [
    {
      "path": "webroot/index.html",
      "sha256": "<hex64>",
      "size": 1234,
      "mode": "0644",
      "enc": "raw",
      "class": "live"
    }
  ],
  "delete": ["webroot/old.html"],
  "sig": "<base64>"
}
```

### Campos

| Campo | Significado |
|---|---|
| `schema` | Versión de formato del manifiesto en sí (actualmente `1`). |
| `module` | El id del módulo. El dispositivo rechaza el manifiesto si no coincide con su propio id de módulo, de modo que un feed válidamente firmado para un módulo distinto no se puede servir en su lugar. |
| `version` | Versión entera. El motor actualiza solo hacia adelante; un feed más antiguo que el dispositivo es un estado benigno "ahead", no un error. |
| `version_name` | Cadena de versión legible por humanos (por ejemplo `v106`). |
| `built` | Marca de tiempo de build ISO 8601. Respeta `SOURCE_DATE_EPOCH` para reproducibilidad. |
| `engine_min` | La versión mínima del motor requerida para aplicar este manifiesto. |
| `channel` | Canal de release (por ejemplo `stable`). |
| `key_id` | Qué clave en el keyring del dispositivo firmó este manifiesto. Selecciona la clave pública para la verificación. |
| `files[]` | El árbol de destino **completo** (no un diff). Cada entrada: `path`, `sha256`, `size`, `mode`, `enc` (`raw`/`gz`), `class` (`live`/`soft`/`reboot`). |
| `delete[]` | Rutas presentes en la release anterior pero ausentes ahora, para que el dispositivo las elimine. |
| `sig` | La firma ed25519, base64. Ver la canonicalización abajo. |

`files[]` describe el árbol **entero**, no un delta. El dispositivo calcula el delta él mismo comparando el manifiesto contra lo que ya tiene, y descarga solo los blobs cuyo `sha256` le falta. El `sha256` es siempre del contenido original (sin comprimir); `enc` solo dice cómo se almacena ese blob en `blobs/`. El significado de `class` y lo que el dispositivo hace con cada valor se cubre en [[Reboot Handling]].

---

## Canonicalización (los bytes firmados)

Esta es la invariante más importante del formato. El firmador de la PC y el verificador del dispositivo corren en runtimes completamente distintos (openssl en la PC, toybox + un diminuto verificador embebido en el dispositivo, y **ninguna librería JSON en absoluto** en el dispositivo). Aún deben derivar exactamente los mismos bytes para firmar y para verificar. La regla es por lo tanto una **transformación de bytes** deliberada, no una re-serialización JSON.

**Paso 1: una forma de almacenamiento fija.** `vdlu-pack` escribe `manifest.json` compacto, con claves ordenadas, UTF-8, incluyendo siempre `key_id` y `sig` (como cadenas vacías hasta que se firma):

```
json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
```

**Paso 2: quitar solo `sig`.** La forma canónica es ese texto exacto con **solo el campo `"sig"` eliminado**. Como las claves están ordenadas, `sig` siempre aparece como `,"sig":"<value>",` enmarcado por `"schema"` antes y `"version"` después (ambos siempre presentes), de modo que quitarlo deja texto bien formado. JSON escapa cada `"` dentro de un valor de cadena como `\"`, de modo que el token estructural `"sig":"` es inequívoco incluso frente a un nombre de archivo que literalmente contenga `"sig":"`.

La eliminación es un puñado de expansiones de parámetros POSIX, idénticas en el firmador y el verificador, sin `sed` y sin `jq`:

```sh
# $1 = the full manifest text
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

**Paso 3: firmar el hash de eso.** El mensaje firmado/verificado es el **sha256 hex** (64 caracteres ASCII, sin newline) de la forma canónica. ed25519 firma ese hex.

Dos consecuencias se desprenden de esto por construcción:

- `key_id` es parte de la forma canónica (solo `sig` se quita). `vdlu-sign` establece `key_id` **antes** de hashear, de modo que la identidad de la clave queda cubierta por la firma.
- Ya sea que el marcador de posición `sig` esté vacío (`"sig":""`, en el momento de firmar) o lleno (en el momento de verificar), quitarlo produce los bytes canónicos idénticos. Firmar y verificar concuerdan automáticamente.

Las dos herramientas sh POSIX son autoritativas. Un equivalente en Python, `re.sub(r'"sig":"[^"]*",', '', text, count=1)` luego sha256, existe solo para contrastarlas.

El razonamiento de confianza alrededor de todo esto (por qué la verificación es en el dispositivo, cómo `hardened` falla de forma cerrada) vive en [[Security and Trust Model]].

---

## baseline.json (la semilla de instalación)

Cuando un módulo se instala por primera vez, ya debería estar "al día" para su propia versión enviada, sin una autoactualización innecesaria de la versión que acaba de instalar. Eso es lo que `baseline.json` hace.

`baseline.json` se envía **dentro del zip del módulo** (en `vdlu/baseline.json`), no en el feed. En una instalación nueva, el motor siembra su registro de "versión activa" desde él, de modo que el dispositivo nace al día, sin `from:0` y sin re-descargar lo que ya tiene.

Propiedades clave:

- Es una **copia sin clave del manifiesto firmado** para la versión enviada: la misma salida de `vdlu-pack`, dejada sin firmar (`key_id` y `sig` quedan vacíos).
- **No está verificada.** El motor la trata como una semilla local confiable porque llegó dentro del zip flasheado, que es el límite de confianza de instalación. Solo un manifiesto *descargado del feed* pasa por la verificación de firma.
- Como no necesita firma, **CI puede generarla sin clave**, que es lo que mantiene la clave de firma enteramente fuera de CI (ver [[Producer]]).
- `vdlu-pack` **excluye `baseline.json` de su propio manifiesto**, de modo que el manifiesto nunca referencia la baseline (eso sería un bucle de autorreferencia: manifiesto a baseline a manifiesto).
- Es **no fatal si está ausente**. Sin ella, el dispositivo simplemente parte de `from:0` en su primera actualización y descarga lo que necesita. Nunca roto, solo menos óptimo.

---

## Blobs

Cada contenido de archivo distinto es un blob bajo `blobs/`, nombrado por el **sha256 del contenido original**:

- `blobs/<sha256>` para un blob en crudo.
- `blobs/<sha256>.gz` para un blob comprimido con gzip (el gzip se mantiene solo cuando el archivo tiene al menos 4096 bytes y la compresión ahorra al menos un 10 por ciento).

Un blob se almacena una vez, en un solo formato. El direccionamiento por contenido da deduplicación gratis: el contenido sin cambios, compartido o revertido mapea a un blob que ya existe, de modo que el feed crece solo por contenido genuinamente nuevo, y el dispositivo descarga solo los hashes que le faltan. El dispositivo comprueba el `sha256` de cada blob descargado contra el manifiesto (después de descomprimir un blob `gz`) antes de usarlo.

---

## Qué se excluye del feed, y por qué

El feed lleva **solo el contenido propio del módulo**. Un conjunto fijo de rutas se mantiene fuera de él a propósito. `vdlu-pack` aplica un predicado de exclusión tanto al recorrer el árbol como al calcular `delete[]`.

| Excluido | Por qué |
|---|---|
| `vdlu/keyring/`, `vdlu/verify/` (la raíz de confianza: claves públicas en crudo + el binario verificador) | **Esta es la razón de seguridad central.** El anclaje de confianza es **solo-flash**. Si el keyring o el verificador fueran entregables por el feed, un manifiesto podría sobrescribir la propia cosa que lo valida. Mantenerlos fuera de la línea significa que un manifiesto nunca puede reescribir el anclaje de confianza en el dispositivo. |
| `vdlu/baseline.json` | Es una copia del manifiesto firmado (la semilla de instalación); empaquetarla sería un bucle de autorreferencia. |
| `.vd/` infraestructura de flasheo | Andamiaje de compuerta de flasheo que se envía en el zip, nunca se aplica en vivo. |
| `update.json`, `update-mmrl.json` | Su size/sha los rellena CI *después* de que los zips se construyen, de modo que la copia enviada difiere de cualquier copia del feed. Alimentarlos causaría un fetch fantasma de un solo archivo en la primera autoactualización de cada instalación, y de todos modos son vestigiales en el dispositivo (el gestor lee el update JSON remoto en crudo). |
| `META-INF/`, `customize.sh` (andamiaje del instalador) | Consumidos por el gestor en el momento del **flasheo** y no conservados en el módulo instalado. No son contenido de VDLU; servirlos desperdicia blobs y, si alguno cambiara entre versiones, se escribiría como un archivo del instalador dentro del directorio del módulo en vivo. |
| Compañeros `.sha256` por archivo | Pertenecen solo al zip flasheable, quedan obsoletos tras una actualización incremental, y duplicarían el manifiesto. |
| Archivos dev/doc (`RELEASE.md`, `CLAUDE.md`, `.gitignore`) | Nunca se envían al dispositivo; servirlos desperdicia blobs y agita el manifiesto firmado en cada edición de doc. |

El razonamiento detrás de la exclusión de la raíz de confianza se amplía en [[Security and Trust Model]].

---

## Semántica de delete[]

`delete[]` le dice al dispositivo qué rutas eliminar, de modo que un archivo que se dejó caer entre releases no persista en el dispositivo como un huérfano. Se calcula pasando `--prev <manifest.json previo>` a `vdlu-pack`: una ruta que estaba en la release anterior y no está en la actual se vuelve una entrada de eliminación.

La regla importante: **las rutas excluidas nunca se emiten como eliminaciones, aun con `--prev`.** Cada ruta anterior se pasa por el mismo predicado de exclusión usado al recorrer el árbol. Si un `--prev` apunta a un manifiesto más antiguo que aún listaba rutas ahora excluidas (un `baseline.json` extraviado, `META-INF/*`, una entrada de keyring, y así sucesivamente), esas rutas **no** se convierten en entradas de eliminación. Una ruta excluida nunca fue contenido del feed, así que no le corresponde a VDLU eliminarla, y nunca se le ordena al dispositivo quitar un archivo que no se sirvió a través del feed. Esto es lo que evita que la lista de exclusión alguna vez se vuelva en contra como una instrucción destructiva.
