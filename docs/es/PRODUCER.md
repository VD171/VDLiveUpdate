> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · [Deutsch](../de/PRODUCER.md) · Español · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# Capa de producer + firma de VDLU

Construye la entrega direccionada por contenido (manifiesto + blobs) para un módulo y la firma.
Se ajusta a [`INTERFACES.md`](INTERFACES.md) §3/§6/§7.

| herramienta | corre en | lenguaje | tarea |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | recorre el árbol final del módulo -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | par de claves ed25519 (`<id>.pem` priv, `<id>.pub` PEM, `<id>.pub.raw` RAW 32B para el keyring slim) |
| `producer/vdlu-sign` | PC | sh + openssl | inyecta `key_id` + `sig` en un manifiesto, in place |
| `engine/vdlu-verify` | **dispositivo** | sh + ed25519-mini | verifica `sig` vía el ed25519-mini embebido; keyring = pubkey RAW 32B (SIN openssl en el dispositivo) |

## Pipeline

```sh
# 1. one-time: a signing key. Keep the .pem off every device and off any repo push.
producer/vdlu-keygen release-2026 ./keys

# 2. each release: pack the final tree (same tree the .zip ships, post-whitelist).
producer/vdlu-pack  ./module_tree  ./out  demo 106 --version-name v106 --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev

# 3. sign the manifest in place.
producer/vdlu-sign  ./out/manifest.json  ./keys/release-2026.pem  release-2026

# 4. publish ./out/{manifest.json,blobs/} to <source> (Pages batch for public; rsync for private).
#    The slim device keyring holds ./keys/release-2026.pub.raw as keyring/release-2026.pub (RAW 32B).
```

`vdlu-pack` es direccionado por contenido y deduplicante: un blob cuyo `<sha256>` ya existe no se
reescribe, así que la publicación es incremental y el contenido sin cambios / revertido nunca se re-sube.

### Decisión de `enc` (vdlu-pack)

`sha256` es **siempre** del contenido original (sin comprimir); `enc` solo nombra cómo se almacena el blob.

- `gz` cuando `size >= 4096` **y** gzip (`-9 -n`, determinista) ahorra al menos un 10% (`comp <= raw*0.90`).
- `raw` en caso contrario (texto pequeño que el gzip de HTTP ya cubre, o datos ya incomprimibles).
- gzip faltante en el host de build -> todo `raw` (nunca falla).

Un blob se almacena una vez, en un formato: `blobs/<sha256>` (raw) o `blobs/<sha256>.gz` (gz). El dispositivo
descomprime con toybox `gunzip` (siempre presente), así que no se empaqueta zstd.

### Decisión de `class` (vdlu-pack) - taxonomía de reboot

Derivada del path (INTERFACES §3, doc §4). Solo defaults; una regla de path nunca degrada `reboot`->`live`.

| class | detectada por | aplicada |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | encenada `.vdlu-new`, swap en el arranque |
| `soft` | `service.sh` / `post-fs-data.sh` / `boot-completed.sh` raíz | escrita en vivo, corre en el próximo arranque |
| `live` | todo lo demás (webroot, bin, lib, confs, module.prop, ...) | escrita en vivo, atómica |

Los symlinks **no se siguen** (nunca filtran contenido de fuera del árbol, p. ej. un link a
`/etc/shadow`) y se saltan con una advertencia, ya que el esquema del manifiesto no tiene tipo symlink.
Los archivos no regulares (dirs, fifos, devices) se saltan. `built` respeta `SOURCE_DATE_EPOCH` para
manifiestos reproducibles.

### Baseline (la semilla de instalación) - sin firma, sin clave

`baseline.json` (entregado en `vdlu/baseline.json` en el zip del módulo) siembra `current.json` en una
instalación fresca para que el dispositivo nazca "al día" (sin from:0, sin re-fetch). El engine lo trata como una
**semilla local confiable** (llegó en el zip flasheado, que es la frontera de confianza de la instalación) y
**NO verifica su firma** - solo el manifiesto OBTENIDO del feed pasa por `vdlu-verify`. Así que el baseline no
necesita **ninguna clave**: es solo la salida de `vdlu-pack` sobre el árbol entregado (sin firma; `sig`/`key_id`
quedan vacíos). Una CI puede por tanto generarlo **sin clave**, manteniendo la clave de firma 100% fuera de la CI
- solo el FEED publicado se firma (operador, localmente). `vdlu-pack` excluye `baseline.json` de su propio
manifiesto (anti auto-referencia). No fatal si está ausente: el dispositivo simplemente parte de from:0 en la
primera actualización, nunca roto.

## Canonicalización (el punto de convergencia)

`vdlu-sign` y `engine/vdlu-verify` deben derivar los **mismos bytes** de un manifiesto, en dos
runtimes distintos (openssl del PC vs toybox + openssl del dispositivo). La regla es deliberadamente una
transformación de bytes, no una re-serialización JSON, así que no necesita librería JSON en el dispositivo:

1. `vdlu-pack` escribe `manifest.json` **compacto, claves ordenadas, UTF-8**
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), incluyendo siempre
   los campos `key_id` y `sig` (placeholders de cadena vacía hasta firmar). Esta es la forma de almacenamiento
   canónica.
2. **Forma canónica = ese texto con el campo `"sig"` removido.** Como las claves están ordenadas, `sig`
   siempre aparece como `,"sig":"<value>",` entre `"schema"` (antes) y `"version"` (después),
   ambos siempre presentes. Removerlo deja `...,"schema":N,"version":...` bien formado.
   JSON escapa toda `"` dentro de valores de cadena a `\"`, así que el token estructural `"sig":"` es
   inequívoco incluso frente a un nombre de archivo que contenga literalmente `"sig":"` (probado).
3. El mensaje firmado/verificado es el **sha256 hex** (64 caracteres ASCII, sin newline) de la forma
   canónica. ed25519 sobre ese hex (`openssl pkeyutl -sign/-verify -rawin`).

La remoción en sh POSIX (función idéntica en ambas herramientas, sin `sed`/`jq`):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` es parte de la forma canónica (solo `sig` se quita); `vdlu-sign` fija `key_id` **antes** de
hashear. El placeholder de valor vacío (`"sig":""`, al firmar) o lleno (al verificar) da los
bytes canónicos idénticos, así que firma y verify concuerdan por construcción.

Python lo reproduce como `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` luego sha256 - usado
solo para el cross-check; los productores autoritativos son las dos herramientas sh.

## Firma (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  para firma/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (el DER SPKI
  ed25519 es un prefijo de 12 bytes + la clave de 32 bytes, así que `tail -c 32` ES la clave). Emite AMBAS.
- `vdlu-sign` (PC): `openssl pkeyutl -sign -rawin` sobre el sha256 hex canónico; firma almacenada en base64.
- `vdlu-verify` (**dispositivo, slim**): `ed25519-mini <pubkey32> <msg> <sig64>` - lee el keyring como la pubkey
  **RAW 32B**, SIN openssl en el dispositivo. `key_id` es path-sanitized (sin `/`, `.`, `..`, `"`). 🚨 El keyring
  entrega el **`.pub.raw` (32B)**, nunca el `.pub` PEM (113B): el PEM es solo PC-side y `ed25519-mini` no puede
  leerlo.

Modelo de confianza (INTERFACES §6, doc §11/§13): `profile=hardened` (público) hace verify obligatorio - una
firma fallida o ausente aborta la actualización. `profile=trusted` (privado, fuente staged por SSH) trata
verify como best-effort, pero el sha256 de cada blob se verifica de todos modos.

## Keyring + rotación

El keyring es un directorio de archivos `<key_id>.pub`, cada uno la pubkey ed25519 **RAW 32B** (del `.pub.raw`
de `keygen`), NO PEM - `ed25519-mini` lee 32 bytes raw. Entrega la pubkey raw actual **y** la previa
(doc §13) para que una clave rotada no deje inservibles las instalaciones viejas. `vdlu-sign` con el nuevo
`key_id` y el dispositivo tomando `<keyring>/<key_id>.pub` (raw) es todo el mecanismo de rotación - sin cambio en
el engine. El keyring es **estable** entre releases (solo la rotación de clave lo cambia): un re-vendor debe
**verificar-no-copiar** y nunca sobrescribirlo con el `.pub` PEM del PC-side.

`vdlu-pack` **excluye el keyring y los binarios de `verify/` del feed** (la raíz de confianza es solo-flash, nunca servida por la red), junto con `baseline.json`, el andamiaje del instalador (`META-INF/`, `customize.sh`), la compuerta de flash `.vd/`, los `update.json`/`update-mmrl.json` rellenados por CI, y los compañeros `.sha256` por archivo. Solo el contenido propio del módulo es actualizable por el feed, así que un manifiesto nunca puede reescribir el ancla de confianza en el dispositivo.

<!-- doc-footer -->

---

> _Esta documentación se generó con Claude (Anthropic) y la mantiene VD171. Las correcciones y mejoras son bienvenidas; consulta [CONTRIBUTING.md](CONTRIBUTING.md)._
