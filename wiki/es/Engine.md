# Engine

El motor es el lado del dispositivo de VDLU: la parte que corre en el teléfono, decide qué cambió, lo descarga y lo aplica. Es un único script de shell POSIX, `engine/update.sh`, más un diminuto verificador de firmas, `engine/vdlu-verify`. Ambos se incorporan al módulo anfitrión en `<module>/vdlu/` y los ejecuta root.

Todo el motor está construido alrededor de una sola idea: una actualización es una **transacción reanudable**. Si el teléfono se reinicia, se mata o pierde la red a mitad de camino, la siguiente ejecución retoma exactamente donde se detuvo, y el módulo nunca queda aplicado a medias fingiendo estar hecho.

Si quieres el panorama general primero, ver [[Architecture]]. Para saber cómo las actualizaciones evitan un reinicio siempre que pueden, ver [[Reboot Handling]].

## Escrito para el dispositivo, no para tu portátil

`update.sh` es `sh` POSIX puro. Corre bajo mksh, busybox o toybox, sin características exclusivas de bash, y pasa `sh -n`. Eso importa porque el entorno en un dispositivo Android rooteado es pequeño y estricto.

En particular, no hay `jq`. VDLU analiza `manifest.json` con un pequeño aplanador estilo gron escrito en `awk`: recorre el JSON un carácter a la vez y emite una línea `path<TAB>value` por hoja (por ejemplo `files/0/sha256<TAB>ab..` o `version<TAB>6`). El shell luego lee esas líneas con `grep` y `cut`. Esto funciona tanto en JSON compacto como con formato bonito, y nunca invoca una herramienta de JSON que no está.

El motor depende solo de lo que toybox ya trae (`sha256sum`, `gzip`/`gunzip`, `base64`, `date`), el verificador `ed25519-mini` embebido y, para feeds `https://`, un pequeño `curl` estático que se descarga y verifica una vez. Un feed `file://` no necesita ningún `curl`.

## Los seis comandos

Invocas el motor con las rutas del módulo en el entorno y un comando:

```sh
VDLU_DIR=/data/adb/<mod>/vdlu MODULE_DIR=/data/adb/modules/<mod> MODID=<mod> \
  sh "$MODULE_DIR/vdlu/update.sh" <cmd>
```

El código de salida `0` significa éxito; cualquier otro código significa un error, con la razón impresa en stderr.

| Comando | Qué hace |
|---|---|
| `check` | Diff de solo lectura. Descarga el manifiesto, lo compara con lo instalado, e imprime un resumen JSON de una línea: `{"update":bool,"from":N,"to":M,"fetch":K,"reboot":bool}`. No cambia nada en el disco. Si el dispositivo es más nuevo que el feed (un downgrade bloqueado) reporta `{"update":false,"ahead":true,...}` con salida `0`, no un error. |
| `run` | El ciclo en vivo completo: DIFF, FETCH, APPLY, COMMIT. Aplica cada archivo en vivo de inmediato y prepara por etapas los pocos archivos de clase reboot. Respeta `cancel`. Escribe el progreso en `journal.json`. |
| `resume` | Continúa una transacción que fue interrumpida, empezando desde la fase en que estuviera. Idempotente. **No** intercambia un `.so` por etapas (eso queda reservado para `boot`). |
| `boot` | La ruta pre-zygote. Hace un `resume` y luego intercambia cualquier archivo `*.vdlu-new` por etapas en su sitio, cerrando `PENDING_REBOOT` a `DONE`. Si no hay transacción pendiente, ejecuta un ciclo nuevo y aplica todo, incluido el `.so`, en ese único arranque. |
| `status` | Imprime `journal.json`, o `{"state":"idle"}` cuando no hay nada en curso. |
| `cancel` | Crea un marcador `cancel`. Un `run` en curso se detiene limpiamente en el siguiente punto seguro. |

El comando `check` es deliberadamente barato, para que la UI pueda decirte que existe una actualización en cualquier red. La descarga real se gestiona por separado (ver la fase de fetch abajo).

## La transacción, paso a paso

Cada `run` avanza por una máquina de estados fija, registrada en `journal.json` para que la WebUI (y tú) puedan observarla:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> (PENDING_REBOOT | DONE)
```

**DIFF.** El motor descarga `manifest.json`, valida cada campo (ver abajo y [[Security and Trust Model]]), y compara el árbol de destino firmado contra `current.json`, el manifiesto de la versión ya instalada. El resultado es un plan por archivo escrito en `plan.tsv`: una fila por archivo, portando su clase, hash de destino, mode y estado de progreso. Los archivos que ya están en el hash de destino se marcan para omitir.

**FETCH.** Por cada archivo que aún hace falta, el motor descarga su blob direccionado por contenido desde `<source>/blobs/<sha>` (o `<sha>.gz` cuando está comprimido), hacia un archivo `.part`. Si el blob está comprimido con gzip se descomprime, y luego su SHA-256 se comprueba contra el manifiesto. Solo ante una coincidencia se hace `mv` atómico hacia `blobs/<sha>`. Un blob ya cacheado con un hash correcto se omite por completo, y un archivo local sin cambios puede sembrar el cache sin ninguna descarga. Tres fallos en el mismo blob abortan la fase sin aplicar nada. La fase alcanza `FETCHED` solo una vez que cada blob del plan está presente y verificado. Para el [[Feed Format]] del que vienen estos blobs, ver esa página.

El fetch se gestiona por la política de red: un feed puede restringirse a solo Wi-Fi, solo móvil o cualquier red. Cuando la red actual no está permitida, el fetch no falla; entra en el estado benigno `DEFERRED`, mantiene el plan y el destino fijados, y se reanuda en el siguiente check o arranque cuando aparezca la red correcta. Mientras tanto no se gastan datos.

**APPLY.** Solo se entra desde `FETCHED`. Por cada archivo el motor actúa según la clase:

- Archivos `live` y `soft`: respaldar el archivo actual a `rollback/<version>/<path>`, escribir el nuevo contenido en un hermano `.vdlu-tmp`, hacerle `chmod`, verificar su hash, luego hacer `rename` atómico sobre el destino. Un archivo que ya está en el hash de destino se omite.
- Archivos `reboot` (un `.so`, un overlay de `/system`, un `sepolicy.rule`): materializar en `staged/<path>.vdlu-new`. El inode en vivo nunca se toca aquí. Ver [[Reboot Handling]].
- eliminaciones: respaldar, luego eliminar. Las eliminaciones se aplican solo al final del todo, en un `DONE` limpio, nunca mientras un reinicio siga pendiente.

**COMMIT.** El motor vuelve a hashear cada archivo `live` y `soft` que tocó. Solo cuando todos coinciden escribe `current.json`, haciendo de la nueva versión la base del diff. Si algún archivo de clase reboot quedó por etapas, el estado pasa a `PENDING_REBOOT` en vez de `DONE`; el intercambio y la reverificación final ocurren más tarde bajo el comando `boot`.

## A prueba de fallos por construcción

Las garantías que hacen seguro ejecutarlo sin supervisión:

- **Nada se marca `DONE` sin un re-hash coincidente.** `DONE` se alcanza solo después de que cada archivo aplicado se vuelva a leer y su SHA-256 se compare con el manifiesto. Un archivo reboot por etapas fuerza `PENDING_REBOOT`, nunca un `DONE` falso.
- **Nada se pierde.** Cada archivo se respalda a `rollback/<version>/` antes de ser sobrescrito, y se conservan las últimas tres versiones. Si un apply falla, los archivos en vivo se revierten desde el respaldo; el módulo nunca queda aplicado a medias mintiendo al respecto. `apply_live` aborta de plano si el paso de respaldo falla, en vez de sobrescribir sin vuelta atrás.
- **Todo es atómico.** El contenido nuevo aterriza vía `rename`/`mv` sobre el destino, de modo que un lector siempre ve o el archivo viejo o el nuevo, nunca una escritura truncada.
- **Reanudable tras una caída o un kill.** Una caída, una red perdida o un reinicio a mitad de camino deja un diario válido; `resume` (o `boot`) continúa desde la fase registrada. El diseño asume que será interrumpido.
- **Se degrada limpiamente.** Un binario ausente, una red caída o un disco lleno produce un error claro en stderr y `state:ERROR` en el diario, sin corromper el módulo.

## El lock

Solo una transacción puede tocar el estado a la vez. `flock` no es confiable en toybox, así que VDLU serializa con un lock de directorio: `mkdir "$VDLU_DIR/lock.d"` tiene éxito para exactamente un invocador y falla para el resto, lo cual es atómico en cualquier sistema de archivos razonable. Un lock obsoleto dejado por un proceso muerto se recupera comprobando el PID registrado.

El reintento paciente en el arranque (usado cuando el dispositivo está sin conexión al arrancar) **no** mantiene este lock mientras espera. Lo adquiere y lo libera entre intentos, de modo que un `run` manual nunca queda bloqueado por un arranque que está esperando la red, y nunca mantiene un wakelock. Seguro para la batería por diseño. Más sobre eso en [[Reboot Handling]].

## Comprobación de firma: `vdlu-verify`

`vdlu-verify` es el comprobador de firmas en el dispositivo, mantenido deliberadamente delgado:

```
vdlu-verify <manifest.json> <keyring_dir>
```

La salida `0` significa que la firma del manifiesto es válida contra la clave pública del keyring cuyo id coincide con el `key_id` del manifiesto; cualquier otro código es un rechazo.

Lo que lo hace delgado es que usa **ningún `openssl` en el dispositivo**. Lee la clave pública del keyring como un archivo de **32 bytes en crudo**, canonicaliza el manifiesto (el texto del manifiesto con el campo `sig` eliminado), lo hashea con el `sha256sum` de toybox, decodifica en base64 la firma, y entrega la clave en crudo, el mensaje y la firma de 64 bytes al binario `ed25519-mini` embebido. El comprobador también rechaza cualquier cosa malformada antes de verificar: un `key_id` o `sig` ausente o vacío, un `key_id` que contenga separadores de ruta, una clave pública que no sea exactamente 32 bytes, o una firma que no sea exactamente 64 bytes.

Antes de seleccionar una clave siquiera, el motor aplica una **allowlist de `key_id`**: el `key_id` del manifiesto debe ser uno que la configuración permita firmar una *actualización de módulo*, y una clave que esté meramente presente en el keyring pero no en la allowlist se rechaza antes de que su pubkey llegue a cargarse. Un keyring de una sola clave fija automáticamente esa única clave sin configuración; un keyring de varias claves debe fijar `key_id` o el motor falla a prueba de fallos. El conjunto permitido se pasa a `vdlu-verify` como `VDLU_KEYID_ALLOW`, y se aplica en ambos perfiles. Esto impide que una clave de menor confianza, como una clave de feed de fingerprint que comparte el keyring, firme una actualización de root completa; el feed de fingerprint separado conserva su propia clave fijada, `FEED_KEY_ID`. La historia completa está en [[Security and Trust Model]].

La canonicalización es idéntica byte a byte a la del firmador del productor, que es lo que hace que una firma verifique a través de las herramientas. La clave privada correspondiente nunca toca un dispositivo ni CI; solo la clave pública en crudo está embebida. La historia completa de confianza, los dos perfiles y por qué `hardened` es a prueba de fallos por inversión están en [[Security and Trust Model]].

El motor llama a `vdlu-verify` durante la fase de diff. Bajo el perfil `hardened` una verificación fallida aborta toda la actualización; bajo `trusted` la verificación es de mejor esfuerzo, pero el hash de cada blob siempre se comprueba de todos modos, de modo que el contenido corrompido se detecta sin importar el perfil.

## Estado en disco

Todo el estado del motor vive en `$VDLU_DIR` (fuera del directorio del módulo), de modo que el propio árbol del módulo solo contiene archivos terminados:

| Ruta | Rol |
|---|---|
| `config` | ajustes clave=valor (source, profile, channel, política de red, reintento de arranque) |
| `current.json` | manifiesto de la versión activa; esta es la base del diff. Ausente significa nunca actualizado |
| `target.json` | el manifiesto fijado de la transacción en curso. Su presencia marca una transacción activa; se convierte en `current.json` en `DONE` |
| `plan.tsv` / `plan.del` | el plan por archivo y el progreso, y la lista de rutas a eliminar |
| `journal.json` | progreso para la WebUI, reescrito en cada cambio de estado |
| `blobs/<sha256>` | cache de contenido original verificado y descomprimido |
| `rollback/<version>/<path>` | respaldos de archivos sobrescritos; se conservan las últimas tres versiones |
| `staged/<path>.vdlu-new` | un archivo de clase reboot esperando el intercambio de arranque |
| `lock.d/` | el lock de mkdir |
| `tools/<abi>/curl` | el curl estático descargado y verificado; persiste entre actualizaciones |
| `cancel` | una solicitud de cancelación |

## Ver también

- [[Reboot Handling]]: cómo el sistema de clases mantiene la mayoría de las actualizaciones sin reinicio, y cómo un `.so` por etapas se intercambia pre-zygote.
- [[Security and Trust Model]]: los dos perfiles, la validación a prueba de fallos y la cadena ed25519 de clave en crudo.
- [[Feed Format]]: el manifiesto y los blobs direccionados por contenido que el motor consume.
- [[Architecture]]: cómo encajan el motor, el productor y la WebUI.
