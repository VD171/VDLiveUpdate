# Architecture

VDLU tiene dos lados unidos por una sola cosa en el medio. En la PC, el [[Producer]] convierte el árbol de un módulo en un feed firmado y direccionado por contenido. En el dispositivo, el [[Engine]] lee ese feed, averigua qué cambió y lo aplica. La costura entre ambos es el **manifiesto firmado más el almacén de blobs** (el [[Feed Format]]). Nada más cruza la brecha.

```
        PC / release host                                device
  +--------------------------+                 +---------------------------+
  |  Producer                |                 |  Engine  (update.sh)      |
  |  vdlu-pack  -> manifest  |    signed       |  POSIX sh, no jq          |
  |  vdlu-sign  -> sig       |    feed         |  DIFF FETCH APPLY COMMIT  |
  |  vdlu-gc    -> prune     | =============>  |  journal + rollback       |
  +--------------------------+   manifest.json |  ed25519-mini verify      |
                                 blobs/<sha>   +-------------+-------------+
                                                             |
                                                       +-----v------+
                                                       |  WebUI     |
                                                       |  Updates   |
                                                       |  panel     |
                                                       +------------+
```

Los dos lados nunca comparten un runtime. El Producer usa `python3` y `openssl`; el Engine es `sh` POSIX puro con toybox y un `ed25519-mini` embebido. Solo concuerdan porque ambos derivan los **mismos bytes canónicos** de un manifiesto (ver [[Security and Trust Model]]). La WebUI es un panel delgado en JS plano que maneja el motor a través del puente del gestor de root y lee su diario de progreso; no contiene lógica de actualización propia. Ver [[WebUI]].

## Los dos lados

| Lado | Corre en | Construido con | Trabajo |
|---|---|---|---|
| [[Producer]] | PC / CI | `python3` + `sh` + `openssl` | Recorrer el árbol del módulo hacia `manifest.json` + `blobs/`, firmarlo, podar huérfanos |
| [[Engine]] | dispositivo | `sh` POSIX + toybox + `ed25519-mini` | Comparar el árbol instalado contra el feed, descargar deltas, aplicar, confirmar |
| [[WebUI]] | dispositivo (webview) | JS/CSS plano | Disparar actualizaciones, mostrar el progreso, editar la config, mostrar el banner de reinicio |

## La tubería de actualización

Cada actualización es una transacción, ejecutada en un orden fijo:

```
  DIFF  ------>  FETCH  ------>  APPLY  ------>  COMMIT
  read feed      download        write live     re-hash all,
  + validate     only missing    files now,      promote target
  + plan         blobs, verify   stage reboot     -> current,
  (no changes)   each sha256     ones             DONE or
                                                  PENDING_REBOOT
```

- **DIFF** (`update.sh check` es esta fase, de solo lectura). El motor descarga solo el manifiesto, ejecuta `validate_plan()` sobre cada campo **antes** de tocar nada, y luego compara el feed contra `current.json` para armar un plan por archivo. No cambia nada en el disco. Un dispositivo por delante del feed es un benigno resultado "ahead", no un error.
- **FETCH.** Descarga solo los blobs que el plan tiene faltantes, hacia `<sha>.part`, descomprime `gz`, comprueba `sha256sum` contra el manifiesto, y hace `mv` atómico de cada blob verificado hacia el cache. Un blob ya cacheado (o sembrado desde un archivo local sin cambios) se omite, de modo que una reversión o un archivo compartido no cuesta nada. Tres fallos en un mismo blob abortan la fase sin aplicar nada. Una descarga bloqueada por la política de red sale como `DEFERRED` (reanudable), no como error.
- **APPLY.** Los archivos corrientes (`live` / `soft`) se escriben ahora: respaldo a `rollback/<v>/`, escritura de un `.vdlu-tmp`, `chmod`, verificación, luego `rename` atómico sobre el destino. Los archivos de clase reboot se materializan en `staged/<path>.vdlu-new` y el inode en vivo queda intacto. Una entrada de `delete[]` se respalda y luego se elimina. Cada paso es idempotente: un archivo que ya está en el hash de destino se omite.
- **COMMIT.** Vuelve a hashear cada archivo en vivo; solo si todo coincide el motor promueve `target.json` a `current.json`. Si algo quedó por etapas, la transacción termina en `PENDING_REBOOT`; en caso contrario, `DONE`.

## Manifiesto y blobs direccionados por contenido

El feed está direccionado por contenido: el manifiesto lista el árbol de destino **completo**, cada archivo portado por su `sha256`, y el almacén de blobs guarda una copia de cada contenido distinto bajo `blobs/<sha256>` (o `blobs/<sha256>.gz`).

- **Deduplicación.** Contenido idéntico en cualquier parte del árbol, o a través de versiones, es un solo blob. Publicar es incremental: un blob cuyo `sha256` ya existe en el host nunca se vuelve a subir, y el dispositivo nunca vuelve a descargar contenido que ya tiene.
- **El sha256 es del original.** El hash siempre nombra el contenido sin comprimir; `enc` (`raw` o `gz`) solo registra cómo se almacena ese blob en particular. El dispositivo descomprime `gz` con el `gunzip` de toybox, de modo que no se empaqueta ningún compresor extra.
- **Estable por sabor.** Como el dispositivo compara contra lo que está realmente instalado, el feed puede llevar toda una familia de módulos; cada instalación descarga solo los blobs que completan su propio sabor.

La disposición campo por campo completa está en [[Feed Format]].

## El diario reanudable

Cada transacción es segura ante caídas porque su progreso vive en un diario (`journal.json`), y el destino fijado de la transacción en curso vive en `target.json`. La máquina de estados corre en un orden fijo:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> ( PENDING_REBOOT | DONE )
                                                               \-> ERROR / DEFERRED
```

| Estado | Significado |
|---|---|
| `PLANNED` | Plan armado, nada descargado aún |
| `FETCHING` / `FETCHED` | Descargando blobs / todos los blobs presentes y verificados |
| `APPLYING` / `APPLIED_LIVE` | Escribiendo archivos / todos los archivos en vivo escritos |
| `PENDING_REBOOT` | Un archivo de clase reboot está por etapas, esperando el intercambio de arranque |
| `DONE` | El re-hash de todo coincidió; `current.json` promovido |
| `ERROR` | Fallo duro; el módulo queda sin corromper, los archivos en vivo revertidos desde `rollback/` |
| `DEFERRED` | Descarga retenida por la política de red; el plan persiste, se reanuda luego |

`DONE` se alcanza **solo** una vez que un re-hash de todo coincide, de modo que el diario nunca afirma que una actualización aplicada a medias esté completa. Una caída, una red perdida o un reinicio a mitad de camino deja un diario reanudable; `update.sh resume` (o `boot`) retoma desde la fase actual. Ver [[Engine]] para el conjunto de comandos y los archivos de estado en el dispositivo.

## Atomicidad y rollback

Nada se sobrescribe jamás en su sitio y nada se pierde:

- **Escrituras atómicas.** Cada archivo aterriza vía un temporal (`.vdlu-tmp`) y un `rename` / `mv` atómico, de modo que un lector nunca ve un archivo a medio escribir.
- **Respaldo antes de sobrescribir.** El contenido previo va a `rollback/<version>/<path>` antes de que el nuevo archivo se renombre sobre él (se conservan las últimas versiones). Si un apply falla, los archivos en vivo se revierten desde la copia de rollback en vez de quedar corrompidos. Un respaldo fallido **aborta** el apply en lugar de sobrescribir sin red de seguridad.
- **Serializado.** Un lock basado en `mkdir` (`lock.d/`, dado que `flock` es inviable en toybox, con recuperación de locks obsoletos por PID) serializa las ejecuciones concurrentes.

## El principio de ausencia de reinicio

La mayoría de los archivos se pueden intercambiar mientras el módulo está en vivo, así que VDLU los aplica de inmediato. Solo tres clases necesitan un reinicio, porque un proceso en vivo ya los ha mapeado: un `.so` (cargado por Zygisk), un overlay de `/system` y un `sepolicy.rule`. Esos se **preparan por etapas, nunca se escriben sobre un inode en vivo**, y se intercambian en un único paso pre-zygote en el siguiente arranque. La taxonomía completa y el flujo de arranque están en [[Reboot Handling]].

## La postura de confianza a prueba de fallos

El feed es lo único que cruza desde la PC hacia el dispositivo, así que el motor trata cada byte de él como hostil. `validate_plan()` corre en la fase DIFF, antes de cualquier descarga, y rechaza el manifiesto entero ante cualquier campo malformado. La verificación de firma usa un `ed25519-mini` embebido (sin `openssl` en el dispositivo), la clave privada nunca toca un dispositivo ni CI, y el perfil `hardened` es a prueba de fallos por inversión, de modo que un valor de perfil corrompido nunca puede aceptar en silencio un feed sin firmar. El modelo completo, los dos perfiles y las amenazas que cada uno responde están en [[Security and Trust Model]].
