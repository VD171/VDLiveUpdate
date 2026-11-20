> **Languages:** [English](../INTERFACES.md) · [العربية](../ar/INTERFACES.md) · [Čeština](../cs/INTERFACES.md) · [Deutsch](../de/INTERFACES.md) · Español · [فارسی](../fa/INTERFACES.md) · [Français](../fr/INTERFACES.md) · [हिन्दी](../hi/INTERFACES.md) · [Bahasa Indonesia](../id/INTERFACES.md) · [Italiano](../it/INTERFACES.md) · [日本語](../ja/INTERFACES.md) · [한국어](../ko/INTERFACES.md) · [Nederlands](../nl/INTERFACES.md) · [Polski](../pl/INTERFACES.md) · [Português](../pt/INTERFACES.md) · [Русский](../ru/INTERFACES.md) · [Svenska](../sv/INTERFACES.md) · [ไทย](../th/INTERFACES.md) · [Türkçe](../tr/INTERFACES.md) · [Українська](../uk/INTERFACES.md) · [Tiếng Việt](../vi/INTERFACES.md) · [中文](../zh/INTERFACES.md)

---

# VDLU - Contrato de interfaz (la costura entre los componentes)

**Ley de convergencia:** cada componente se ajusta a este archivo. Las piezas de 4 agentes tienen que **encajar
juntas** - las firmas de CLI, los nombres de archivo y las claves JSON de abajo son **inmutables** (un cambio
significa alinear aquí primero).

Principios heredados de los repos: **sh POSIX puro** en el dispositivo (sin bashismos; corre con toybox/busybox +
`sha256sum`/`gzip`/`base64` de toybox + el `curl` obtenido + el `ed25519-mini` embebido - ligero, sin bundle de
binarios), **cero comentarios gratuitos**, **siempre release**, **rigor ante el fallo** (transacción retomable,
nada falsamente "concluido", nada perdido), **nada aflojado**.

---

## 1. Distribución del estado (Tier-2, fuera del directorio del módulo)

```
$VDLU_DIR = /data/adb/<module>/vdlu
  config               # key=value (§5)
  current.json         # manifest of the ACTIVE version (diff base); absent = never updated
  journal.json         # transaction in progress (§4); absent = idle
  cancel               # presence = cancel request (WebUI creates it; engine deletes it on stop)
  lock.d/              # mkdir-lock (flock unworkable on toybox; stale-recovery by PID)
  blobs/<sha256>       # cache of verified blobs (ORIGINAL content, already decompressed)
  rollback/<version>/<path>   # backup of overwritten files
  staged/<path>.vdlu-new      # REBOOT-hard awaiting swap at boot
  target.json          # PINNED manifest of the in-flight transaction (presence = active transaction; becomes current.json on DONE)
  plan.tsv  plan.del   # engine's internal plan (progress); the WebUI IGNORES it (reads only journal/config/current)
```
`cancelled:true` en el journal = el engine paró ante una cancelación (un estado no terminal, retomable; `error`
queda null).

Engine vendorizado en el módulo: `$MODULE_DIR/vdlu/update.sh` (+ `vdlu-verify`). `$MODULE_DIR =
/data/adb/modules/<module>`. El engine recibe por env: `VDLU_DIR`, `MODULE_DIR`, `MODID`.

## 2. CLI del engine (componente ENGINE)

`sh update.sh <cmd>` - rc 0 = ok, !=0 = error (stderr tiene la razón):

| cmd | hace |
|---|---|
| `check` | DIFF: descarga el manifiesto, compara; imprime un JSON de 1 línea `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; no cambia nada. Dispositivo POR DELANTE del feed (downgrade bloqueado, endurecido) = un estado BENIGNO: `{"update":false,"ahead":true,"from":N,"to":M}` + rc0 (nunca "check failed"). rc de do_diff: 2 fetch/parse, 3 verify/meta, 4 ahead |
| `run` | ciclo completo: DIFF→FETCH→APPLY→COMMIT; respeta `cancel`; escribe el progreso en `journal.json`; aplica LIVE, encena REBOOT-hard |
| `resume` | retoma la transacción de `journal.json` desde la fase actual (idempotente) |
| `boot` | modo pre-zygote: `resume` + hace el SWAP de los `staged/*.vdlu-new` (aplica el `.so`), cierra `PENDING_REBOOT`→`DONE` |
| `status` | imprime `journal.json` (o `{"state":"idle"}`) |
| `cancel` | crea `$VDLU_DIR/cancel` (un `run` en curso para en el próximo punto seguro) |

Fuente de blobs/manifiesto: `source` de la config. `<source>` + `/manifest.json`, `/blobs/<sha>`, `/blobs/<sha>.gz`.
`source` empieza con `https://` (curl estático obtenido, TLS) o `file://` (staging local).

## 3. manifest.json (producido por el PRODUCER, consumido por el ENGINE)

```json
{ "schema":1, "module":"<id>", "version":<int>, "version_name":"<str>", "built":"<ISO8601>",
  "engine_min":3, "key_id":"<str>", "channel":"stable",
  "files":[ {"path":"webroot/index.html","sha256":"<hex64>","size":<int>,"mode":"0644","enc":"raw|gz","class":"live|soft|reboot"} ],
  "delete":["<path>"], "sig":"<base64>" }
```

- `files[]` = el árbol objetivo COMPLETO. `class`: `live` (webroot/bin/lib/confs/scripts-on-demand/module.prop) ·
  `soft` (service.sh/post-fs-data.sh/boot-completed.sh) · `reboot` (`zygisk/**/*.so`, `system/**`, `*.rule`).
  Por defecto según el path; nunca degrada `reboot`→`live`.
- `enc`: `gz` (gzip `-9 -n`, determinista; toybox gunzip en el dispositivo) solo cuando comprime bien Y el
  tamaño es significativo; `sha256` es SIEMPRE del contenido original.
- `sig`: firma del manifiesto canónico SIN el campo `sig` (§4 de verify).

## 4. journal.json (el ENGINE escribe, la WEBUI lee - el contrato de progreso)

```json
{ "schema":1, "module":"<id>", "target":<version>, "from":<version>,
  "phase":"diff|fetch|apply|commit", "state":"PLANNED|FETCHING|FETCHED|APPLYING|APPLIED_LIVE|PENDING_REBOOT|DONE|ERROR|DEFERRED",
  "total":<int>, "done":<int>, "current":"<path>", "bytes":<int>, "reboot_pending":bool,
  "cancelled":bool, "error":"<str|null>", "updated":"<ISO8601>",
  "items":[ {"path":"<p>","sha256":"<h>","class":"<c>","st":"pending|fetched|applied|staged|skipped"} ] }
```

Máquina de estados (orden fijo): `PLANNED→FETCHING→FETCHED→APPLYING→APPLIED_LIVE→(PENDING_REBOOT|DONE)`.
`DONE` solo una vez que un re-hash de TODO coincide. Un REBOOT-hard encenado ⇒ `PENDING_REBOOT` (no `DONE`).
Salidas de la fase `fetch`: `ERROR` (fallo duro) o `DEFERRED` (net_policy bloqueó la descarga - benigno/retomable,
no un error).

## 5. config (key=value, uno por línea; editable en la WEBUI)

```
auto_on_webui_open=0
auto_on_reboot=1
source=https://<user>.github.io/<repo>/<module>
channel=stable
profile=trusted        # trusted | hardened. CODE DEFAULT (line absent) = hardened (fail-closed, 9a9a824)
net_policy=any         # any (Wi-Fi+mobile) | wifi (Wi-Fi only) | mobile (mobile only) - gates the DOWNLOAD by network type
allow_metered=0        # ⚠️ SUPERSEDED by net_policy (not consumed by the engine)
pubkey_dir=keyring     # relative to $MODULE_DIR/vdlu (keyring of pubkeys for verify)
key_id=                # ALLOWLIST of accepted MODULE-UPDATE signing key id(s), comma-separated (rotation).
                       # UNSET = default-safe: a single-key keyring accepts only that one key; a MULTI-key
                       # keyring (one that also ships a fingerprint-feed key) MUST pin its module key here.
ca_path=               # empty = auto-detect of the Android trust store; set a path to override
tools_source=          # empty = derived from source (.../vdlu-tools); feed of the static curl
boot_retry_interval=30 # seconds between probes when BOOT finds the device offline (floor 5s)
boot_retry_minutes=0   # ceiling of the PATIENT retry (AWAKE-time) only at boot; 0 = off. Battery-safe (no wakelock,
                       # no held lock, route probe never wakes the radio) -> a generous ceiling is ~free
```

**Reintento en el arranque (offline) - PACIENTE, seguro para la batería:** solo en `boot` (nunca en
check/auto-open). Si el fetch del manifiesto falla por RED (`fetch_offline` clasifica por el exit del fetcher),
espera y reintenta hasta tener éxito O agotar `boot_retry_minutes` de tiempo AWAKE. Un diseño que **no retiene
nada y no drena**:
- **Cero wakelock:** entre intentos es `sleep`, que se congela en deep-sleep → el dispositivo duerme con
  normalidad (~cero batería); el reintento se pausa y se reanuda una vez que el dispositivo ya está despierto.
- **Cero lock retenido:** `acquire_lock_try`+release ENTRE intentos (no retiene el lock mientras espera) →
  `run`/check manual nunca se bloquean; si un run manual encena un TARGET mientras tanto, el boot se posterga.
- **No despierta la radio por nada:** un sondeo `net_allowed` (vía `net_type`/`ip route get`, una búsqueda de
  ruta del kernel que respeta el policy-routing de Android; sin paquete) controla cada intento - solo gasta un
  fetch una vez que la red apareció.
- NUNCA reintenta un fallo determinista (manifiesto/sig/downgrade). `--connect-timeout 15` en el fetch (no se
  cuelga en un portal cautivo). `service.sh` lo manda al fondo (el boot nunca se cuelga).
- ⛔ **DURO: activar `boot_retry_minutes>0` exige el engine PACIENTE** (el que tiene
  `net_allowed`+`acquire_lock_try`, canónico `da7115f4`+). El reintento de boot PREVIO (retiene el lock toda la
  ventana + reintenta curl ciego offline) **DRENA la batería/despierta la radio** - activar el reintento en un
  engine viejo es un footgun. Al activarlo, vendoriza el engine actual.

**`net_policy` (any|wifi|mobile):** controla la **DESCARGA** por tipo de red. `net_type()` clasifica la salida
de `ip route get` (iface celular `rmnet/ccmni/v4-*/clat` = móvil; todo lo demás = wifi; búsqueda del kernel, sin
paquete). `net_allowed()` compara contra `net_policy` y controla `do_fetch` (blobs) + el sondeo del reintento de
boot paciente. El **check del manifiesto queda libre** (diminuto → la UI reporta una actualización en cualquier
red); solo la descarga espera la red permitida. Una descarga en una red no permitida = el estado **`DEFERRED`**
en el journal (NO ERROR; un toast INFO azul suave "esperando la red X"; plan/target persisten, se reanuda en el
próximo check/boot en la red correcta). `net_policy` **supera** a `allow_metered` (que nunca se consumió).
Engine `97baf887`+ (`file://` nunca se controla).

## 6. Firma (el PRODUCER firma en el PC vía openssl; el ENGINE verifica en el dispositivo vía ed25519-mini)

- Canonicalización: el manifiesto SIN `sig`, claves ordenadas, JSON compacto (sin espacios superfluos), UTF-8.
  Lo que se firma/verifica = el `sha256` hex de esa forma canónica (da determinismo entre herramientas).
- `producer/vdlu-sign <manifest.json> <privkey.pem> <key_id>` → inyecta `key_id` + `sig` (base64 de la firma ed25519 del sha256 canónico) en el manifiesto, in place.
- `engine/vdlu-verify <manifest.json> <keyring_dir>` → rc 0 si la `sig` coincide con la pubkey `<key_id>.pub` del
  keyring (SLIM: pubkey **RAW 32 bytes**). Internamente, sin openssl: toybox `sha256sum`/`base64 -d` + el
  binario `ed25519-mini` embebido (CLI `ed25519-mini <pub32> <msg> <sig64>`, rc 0=válido/1=inválido/2=uso).
  rc!=0 = rechazo. **`profile=hardened` ⇒ verify obligatorio; fallo = abortar.**
  `profile=trusted` ⇒ verify es best-effort (fuente ya confiable vía SSH), pero el hash de cada blob se verifica SIEMPRE.
- **Allowlist de clave de module-update (fail-closed, antes de la selección de la pubkey):** el `key_id` del manifiesto debe ser una clave MODULE-UPDATE aceptada antes de seleccionar `<key_id>.pub` - el `key_id` de la config (§5) es esa allowlist. Un keyring puede llevar TAMBIÉN una clave de menor confianza (p. ej. una clave de fingerprint-feed, automatizada, de otra cuenta); sin la allowlist, un manifiesto firmado por esa clave verificaría y aplicaría una actualización root flashless completa si se filtrara. `verify_manifest` lo impone en AMBOS profiles y pasa el conjunto resuelto a `vdlu-verify` por la env `VDLU_KEYID_ALLOW` (para que el verificador standalone coincida). Sin definir es seguro por defecto (keyring de una clave: solo esa clave; keyring multiclave: rechazado hasta fijar `key_id`). La raíz de confianza del fingerprint-feed es una ruta SEPARADA, con su propia clave fijada, y no se ve afectada.
- `producer/vdlu-keygen <id> <out>` → genera `<id>.pem` (priv) + `<id>.pub` (PEM, para tooling en el PC) +
  `<id>.pub.raw` (**RAW 32B** = el `<id>.pub` del keyring slim en el dispositivo). openssl `genpkey -algorithm ed25519`.

## 7. Blob - verificación (ENGINE)

Descarga `<source>/blobs/<sha>` (o `.gz` si `enc=gz`), escribe `.part`, si es `gz` descomprime (`gunzip`),
verifica `sha256sum` == el `sha256` del manifiesto; coincide → `mv` atómico a `$VDLU_DIR/blobs/<sha>`. 3 fallos
en el mismo blob = aborta la fase (nada aplicado). Un blob ya en `$VDLU_DIR/blobs/<sha>` con hash ok = salta la
descarga.

## 8. APPLY por clase (ENGINE)

- `live`/`soft`: backup `rollback/<v>/<path>` → escribe `$MODULE_DIR/<path>.vdlu-tmp` desde el blob → `chmod mode` →
  `rename` atómico sobre el objetivo. Ya en el hash objetivo = skip. (En la variante Zygisk la escritura va al
  directorio montado = merge por archivo, nunca `rm -rf` del directorio.)
- `reboot`: materializa en `$VDLU_DIR/staged/<path>.vdlu-new` (NO toca el vivo). El swap es en `boot`.
- `delete[]`: backup → remover.

## 9. WEBUI ↔ ENGINE (componente WEBUI)

- Dispara: `ksu.exec("sh $MODULE_DIR/vdlu/update.sh run")` (en el fondo).
- Progreso: un poll ligero `ksu.exec("cat $VDLU_DIR/journal.json")` cada ~1s; renderiza `{phase,state,total,done,current,bytes}`.
- Vivacidad: journal ausente por 8 ticks ⇒ "sin respuesta". Journal CONGELADO (mismos valores) por 20 ticks ⇒ verifica `lock.d`: vivo = sigue (fetch lento de 1 blob), muerto = error + Resume. Sin esto, un run que murió a mitad del fetch congelaría el toast en "actualizando".
- Cancel: `ksu.exec("touch $VDLU_DIR/cancel")`.
- Config: lee/escribe `$VDLU_DIR/config` (key=value) en una pestaña "Updates".
- Toast: barra + `phase done/total · current`; al terminar con `reboot_pending` ⇒ un banner persistente "reinicia para activar el .so".
- Auto-open (`auto_on_webui_open=1`): hace primero un `check()` SILENCIOSO (sin toast de progreso); solo dispara el `run`+toast persistente si `update && fetch>0`. Al día/por delante/nada nuevo = un resultado inline en el panel, cero toast residual. No intrusivo como el botón manual (el toast solo aparece cuando hay una descarga real). El bootstrap de curl es de una sola vez.

## 10. Integración en la demo (componente INTEGRATION) - SNIPPETS, no edites los archivos vivos

Produce, en `integration/demo/`, snippets + un `INTEGRATION.md` diciendo dónde va cada uno (sin aplicar):
- el hook `auto_on_reboot` en `post-fs-data`/`service.sh` (pre-zygote → `update.sh boot`) y `auto_on_webui_open`.
- los defaults de `config` + el keyring embebido + la vendorización (`modules/<mod>/vdlu/`).
- la variante PARCIAL (merge en el directorio montado).

## 11. Toolchain obtenido + baseline (SLIM, Enfoque B)

**Distribución en el módulo (zip):** `vdlu/{update.sh, vdlu-verify, config.default, keyring/<id>.pub (RAW 32B),
verify/<abi>/ed25519-mini, baseline.json}`. **SIN** `bin/` (openssl/curl/zstd). `customize.sh` puede podar
`verify/` hasta la ABI del dispositivo (`vdlu-verify` encuentra el mini en `<dir>/ed25519-mini` O `<dir>/verify/<abi>/ed25519-mini`).

**ed25519-mini** (binario embebido, solo verify): `ed25519-mini <pubkey32> <msg> <sig64>` → rc 0=válido,
1=inválido, 2=uso/IO. msg = los bytes firmados exactos (NO re-hashea). TweetNaCl PD, estático por ABI, PROVENANCE.

**tools-feed** (solo perfil público/https): servido en `<tools_source>` (default derivado: cambia el último
segmento de `source` por `vdlu-tools`, p. ej. `https://<user>.github.io/<repo>/vdlu-tools`). Contiene:
- `tools-manifest.json` - un manifiesto `vdlu-pack` FIRMADO sobre el árbol `<abi>/curl`, fijando el `sha256` de
  cada curl (misma clave `release-2026`).
- `<abi>/curl` - el curl **estático** RAW (autocontenido, ~1MB; curl 8.11.1 + mbedTLS). 🪤 mbedTLS NO lleva un
  CA bundle: `fetch_url` pasa `--capath` (autodetección del trust store de Android: `/system/etc/security/cacerts`
  → APEX conscrypt; `ca_path` sobrescribe). Sin capath = error 60. La integridad es el ed25519; el cert-check es defensa en profundidad.

**install-tool** (ENGINE): `update.sh install-tool <abi>` lee `$VDLU_DIR/.work/{tools-manifest.json, tool.<abi>}`
(la WEBUI lo descarga vía `fetch()` y lo escribe ahí), **verifica la firma del tools-manifest (ed25519-mini,
OBLIGATORIO en cualquier perfil)** + el hash del curl == manifiesto, y solo entonces lo instala en `$VDLU_DIR/tools/<abi>/curl` (0755).
El curl corre como root → sig+hash antes de exec cierra el RCE. Persiste en Tier-2: nunca se re-descarga (salvo en la desinstalación).

**fetch-bootstrap** (WEBUI, `ensureToolchain()`): corre antes de check/run/resume. `file://` = no-op; curl YA
disponible (Tier-2, O `module/bin/<abi>/curl` de un módulo **auto-empaquetado**, O sistema) = no-op
(VDLU reutiliza el curl existente); solo `https` **sin ningún curl** descarga curl + tools-manifest vía el webview, los
escribe en `.work` (base64 en trozos vía `ksu.exec`), llama a `install-tool`. La confianza = la verificación en el dispositivo, no la descarga.

> 🪤 **Slim (fetch-bootstrap) ≠ obligatorio.** Un módulo cuyo `bin/` existe para SUS PROPIAS funciones (p. ej.
> empaqueta restic/rclone/age/tar/curl...) **no** se adelgaza a ~2MB ni descarga curl - VDLU adopta el engine
> slim (gz, mini, baseline, fixes) y **reutiliza** el toolchain embebido. Solo los módulos sin su propio
> toolchain ganan los ~2MB.

**baseline.json** (fix from:0): el release copia el `manifest.json` FIRMADO de la versión entregada a
`vdlu/baseline.json`; en una instalación fresca el engine siembra `current.json` desde él (`init_paths`, solo si
está ausente) → el dispositivo nace "al día", sin auto-actualización de sí mismo y sin re-fetch.

<!-- doc-footer -->

---

> _Esta documentación se generó con Claude (Anthropic) y la mantiene VD171. Las correcciones y mejoras son bienvenidas; consulta [CONTRIBUTING.md](CONTRIBUTING.md)._
