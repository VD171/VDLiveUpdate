> **Languages:** [English](../ENGINE.md) · [العربية](../ar/ENGINE.md) · [Čeština](../cs/ENGINE.md) · [Deutsch](../de/ENGINE.md) · Español · [فارسی](../fa/ENGINE.md) · [Français](../fr/ENGINE.md) · [हिन्दी](../hi/ENGINE.md) · [Bahasa Indonesia](../id/ENGINE.md) · [Italiano](../it/ENGINE.md) · [日本語](../ja/ENGINE.md) · [한국어](../ko/ENGINE.md) · [Nederlands](../nl/ENGINE.md) · [Polski](../pl/ENGINE.md) · [Português](../pt/ENGINE.md) · [Русский](../ru/ENGINE.md) · [Svenska](../sv/ENGINE.md) · [ไทย](../th/ENGINE.md) · [Türkçe](../tr/ENGINE.md) · [Українська](../uk/ENGINE.md) · [Tiếng Việt](../vi/ENGINE.md) · [中文](../zh/ENGINE.md)

---

# Engine VDLU (`update.sh`)

Cliente de actualización flashless e incremental para módulos KSU/Magisk. Implementa el ciclo
`DIFF -> FETCH -> APPLY -> COMMIT` como una transacción retomable. Se ajusta a `INTERFACES.md` (la ley
de convergencia).

sh POSIX puro (mksh/busybox/toybox). **SLIM:** depende solo de toybox (`sha256sum`/`gzip`/`base64`/`date`) +
el `ed25519-mini` embebido (verify ed25519, **sin openssl en el dispositivo**) + un `curl` estático **obtenido**
en la primera actualización https (la WebUI hace el `fetch()`, lo persiste en Tier-2, e `install-tool` verifica su
firma+hash ANTES de usarlo). `file://` no necesita curl. Cero dependencia de `jq`.

## Invocación

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh $MODULE_DIR/vdlu/update.sh <cmd>
```

`rc 0` = ok, `rc != 0` = error (razón en stderr). `vdlu-verify` lo entrega otro componente
(firma en `INTERFACES.md §6`), el engine solo lo llama.

| cmd | hace |
|---|---|
| `check` | DIFF de solo lectura; imprime `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`; no cambia nada |
| `run` | ciclo LIVE completo + encena REBOOT-hard; respeta `cancel`; progreso en `journal.json` |
| `resume` | retoma la transacción pendiente (`target.json`) desde la fase actual; idempotente; **no** hace el swap del `.so` |
| `boot` | modo pre-zygote: resume **+** hace el swap de los `staged/*.vdlu-new` → cierra `PENDING_REBOOT`→`DONE`. Sin transacción pendiente, corre un ciclo fresco y aplica todo (incluido el `.so`) en un solo arranque |
| `status` | imprime `journal.json` (o `{"state":"idle"}`) |
| `cancel` | crea `$VDLU_DIR/cancel`; un `run` en curso para en el próximo punto seguro |

## Máquina de estados (journal.json)

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

`DONE` solo una vez que un re-hash de TODO coincide. Si se encenó algún REBOOT-hard ⇒ `PENDING_REBOOT` (nunca un
`DONE` falso). `ERROR` ante cualquier fallo, sin corromper el módulo (los archivos LIVE aplicados se revierten
desde `rollback/<v>/`, nada "aplicado a medias mintiendo al respecto"). Salida benigna de la fase `fetch`:
**`DEFERRED`** - la descarga fue postergada por `net_policy` (red no permitida), plan/target persisten y se reanuda
en el próximo check/boot (la WebUI muestra un toast info azul "esperando la red X", no un error).

## Garantías de rigor

- **FETCH:** controlado por `net_policy` (any/wifi/mobile, solo http/https, `file://` nunca) - una red no
  permitida ⇒ `DEFERRED` (retomable), sin gastar datos. Descarga solo lo que falta en `<sha>.part` (curl con
  `--connect-timeout` + `--speed-time`, nunca se cuelga), descomprime `gz` (toybox `gunzip`), verifica `sha256sum` ==
  manifiesto, `mv` atómico a `blobs/<sha>`. Un blob cacheado+ok se salta. Puede sembrar el blob desde un archivo
  local sin cambios (dedup/offline). **3 fallos en el mismo blob = la fase aborta sin aplicar nada.** Solo pasa a
  `FETCHED` con TODOS los blobs del plan presentes+verificados. En el setup del toolchain registra la confianza
  TLS resuelta (path de la CA + legibilidad, tamaño del bundle y conteo de certs) para que un `rc 77` de curl en
  el arranque sea autoexplicativo en `boot.log` - distingue un store vacío de uno ilegible (el caso del contexto
  SELinux de arranque).
- **APPLY** (solo desde `FETCHED`): `live`/`soft` → backup a `rollback/<v>/` → `.vdlu-tmp` → `chmod` → verify →
  `rename` atómico. `reboot` → materializa en `staged/<path>.vdlu-new` (NO toca el inode vivo).
  `delete[]` → backup → remover. Idempotente (un archivo ya en el hash objetivo se salta).
- **COMMIT:** re-hash de todo `live`/`soft`, solo entonces escribe `current.json`. Con archivos encenados ⇒
  `PENDING_REBOOT`. `boot` hace `mv -f staged/....vdlu-new $MODULE_DIR/<path>` (pre-zygote) + re-verifica +
  `DONE`.
- **cancel:** verificado entre archivos (punto seguro), remueve el `.vdlu-tmp`/`.part` en vuelo, borra `cancel`,
  deja el journal retomable (`cancelled:true`, `error:null`).
- **mkdir-lock `$VDLU_DIR/lock.d`** serializa (flock es inviable en toybox, recuperación de stale por PID). El
  reintento de boot PACIENTE no retiene el lock mientras espera (`acquire_lock_try`+release entre intentos) ni un
  wakelock - seguro para la batería. Un crash/red/reboot a mitad → `resume`/`boot` continúa.
- **profile=hardened** ⇒ `vdlu-verify` obligatorio en el manifiesto ANTES de usarlo, fallo = abortar, downgrade
  bloqueado (versión monotónica). **trusted** ⇒ verify es best-effort, pero el hash de cada blob se verifica SIEMPRE.
- **Allowlist de clave de module-update (ambos profiles):** `verify_manifest` rechaza, fail-closed, cualquier manifiesto cuyo `key_id` no esté en la allowlist `key_id` configurada (ver INTERFACES §5/§6) ANTES de seleccionar la pubkey, así una clave de menor confianza que solo reside en el keyring (p. ej. una clave de fingerprint-feed) nunca puede firmar una actualización root flashless. Seguro por defecto cuando no se define: keyring de una clave = solo esa clave, keyring multiclave = rechazado hasta fijar `key_id`.
- **Exclusión del ancla de confianza (VDLU#2):** el engine IGNORA cada path `vdlu/` en un plan obtenido (`update.sh`, `vdlu-verify`, `verify/*`, `keyring/*`, config) - nunca obtenido, aplicado, ni borrado - aunque un feed firmado los lleve. Un feed nunca puede intercambiar el verificador o la clave de firma en el dispositivo, el ancla de confianza cambia solo con un re-flash firmado completo, así que una sola clave de firma filtrada no puede persistir root por la red.
- **Busy-defer (`apply_busy_file`, opt-in):** con `apply_busy_file` definido (un path absoluto que el módulo anfitrión toca durante sus propias operaciones, p. ej. un backup en curso), APPLY se posterga mientras ese path exista - una actualización nunca intercambia archivos del módulo a mitad de una operación. Los blobs ya están obtenidos, así que el próximo trigger aplica sin re-descarga.
- **Topes de tamaño:** 128 MiB por archivo (`MAX_FILE_BYTES`) y 2 MiB por manifiesto (`MAX_MANIFEST_BYTES`), impuestos antes de leer en ambos `update.sh` y `vdlu-verify` (anti decompression-bomb / anti-OOM).
- Degrada con gracia: binario faltante / red caída / disco lleno → un error claro en stderr + `state:ERROR` en
  el journal, sin corromper el módulo.

## Parseo de JSON sin jq

Un aplanador estilo gron en `awk` (POSIX puro: `substr`/`index`/`gsub`/`split`/`printf` + locals pasados como
parámetros) tokeniza el manifiesto carácter a carácter y emite una línea `path<TAB>value` por hoja escalar
(`files/0/sha256<TAB>ab..`, `version<TAB>6`, `delete/0<TAB>etc/x`). Robusto ante JSON compacto O pretty-printed.
El `sh` lo consume con `grep`/`cut`, el plan por archivo se reensambla en un 2º `awk` en TSV
(`class st mode enc sha size path`), que se vuelve `$VDLU_DIR/plan.tsv`.

## Archivos de estado (en `$VDLU_DIR`, Tier-2)

| archivo | rol |
|---|---|
| `config` | key=value (`source`/`profile`/`channel`/`net_policy`/`key_id`/`apply_busy_file`/`boot_retry_*`/…; ver INTERFACES §5) |
| `current.json` | manifiesto de la versión ACTIVA (base del diff); ausente = nunca actualizado |
| `target.json` | manifiesto fijado de la transacción en vuelo (presencia = transacción activa); se vuelve `current.json` en `DONE` |
| `plan.tsv` / `plan.del` | plan + progreso por archivo (st) / paths a borrar |
| `journal.json` | progreso para la WebUI (regenerado en cada transición) |
| `blobs/<sha256>` | cache del contenido original verificado |
| `rollback/<version>/<path>` | backup de archivos sobrescritos (undo; conserva los últimos 3) |
| `staged/<path>.vdlu-new` | REBOOT-hard esperando el swap en el arranque |
| `lock.d/` | mkdir-lock (flock inviable en toybox; recuperación de stale por PID) |
| `tools/<abi>/curl` | curl estático obtenido (bootstrap slim); persiste entre actualizaciones |
| `cancel` | pedido de cancelación |

<!-- doc-footer -->

---

> _Esta documentación se generó con Claude (Anthropic) y la mantiene VD171. Las correcciones y mejoras son bienvenidas, consulta [CONTRIBUTING.md](CONTRIBUTING.md)._
