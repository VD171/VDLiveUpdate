# Security and Trust Model

VDLU actualiza un módulo en su sitio, por la red, como root. Eso es mucho poder apuntado a un archivo que viene de un feed, así que todo el motor se construye sobre un único supuesto:

> **Cada campo del manifiesto es entrada hostil.**

Un feed puede ser envenenado en el origen, o intercambiado y mutilado en tránsito por un MITM. Cuando eso ocurre, el manifiesto aún llega luciendo como un manifiesto: lleva rutas de archivos, cadenas `sha256`, una lista `delete[]`, modes, clases y una bandera de codificación. VDLU no trata ninguno de esos como confiable. Valida el plan entero antes de descargar un solo byte, y nunca deja que un valor del manifiesto llegue a un shell.

Esta página es la historia completa de confianza. Ver [[Feed Format]] para el esquema del manifiesto que valida, y [[Engine]] para dónde se ubican estas comprobaciones en la transacción DIFF -> FETCH -> APPLY -> COMMIT.

---

## Versiones soportadas

Las correcciones de seguridad llegan al último `ENGINE_VERSION`; un manifiesto firmado declara el
engine mínimo que necesita vía `engine_min`, y el engine en el dispositivo rechaza un manifiesto
que pida más de lo que implementa. Se espera que los engines vendorizados más antiguos hagan
**re-vendor** para recoger una corrección, no que se les parchee en el lugar.

| ENGINE_VERSION | estado |
|---|---|
| 7 (actual) | soportado - nunca revertir un módulo por delante del feed (el `versionCode` instalado en vivo fija el piso de la versión "from"), auto-reparación en el arranque de un plan de downgrade obsoleto |
| 6 | superado - auto-reparación en el arranque de un journal obsoleto con `target <= 0` (el baseline 0 de un stub eliminado ya no dispara ninguna UI ni acción de arranque) |
| 5 | superado - exclusión del ancla de confianza del lado del engine (el directorio `vdlu/` se ignora aunque un feed lo lleve), topes de 128 MiB por archivo / 2 MiB de manifiesto |
| 4 | superado - allowlist de `key_id`, rechazo de paths con dot-segment/trailing-slash, topes de tamaño, lock en check-time |
| <= 3 | sin soporte - re-vendorizar el engine actual |

Cualquier cambio en la verificación del engine o la lógica de apply sube `ENGINE_VERSION`.

---

## La idea central: a prueba de fallos, antes de que pase nada

`validate_plan()` corre dentro de la fase `check`/diff, **antes** de cualquier fetch y **antes** de cualquier apply. Recorre cada entrada en el árbol de archivos planeado y cada entrada en `delete[]`, y si una sola entrada está malformada **rechaza el manifiesto entero** y la transacción nunca empieza. No hay aceptación parcial, ni "omitir el malo y aplicar el resto". Un campo malo envenena el lote, a propósito.

Un manifiesto se acepta solo si **todas** estas se cumplen para **cada** entrada:

| Campo | Regla | Por qué |
|---|---|---|
| `path` | no absoluta, sin componente `..`, sin componente `.`, sin `./` inicial, sin `/./` embebido, sin barra final, sin carácter de control (tab / newline) | una ruta debe quedarse dentro de `MODULE_DIR`; una ruta absoluta o con `..` es escribir-en-cualquier-parte |
| `sha256` | coincide con `^[0-9a-f]{64}$` exactamente | un sha no hex se interpolaría en una ruta de shell; es la dirección de contenido, así que debe ser un digesto hex puro y nada más |
| `mode` | solo octal (`[0-7]`) | una cadena de mode se vuelve un argumento de `chmod` |
| `size` | solo dígitos, y `<=` el techo de tamaño del motor | acota la descarga y la descompresión |
| `class` | exactamente `live`, `soft` o `reboot` | la clase decide si un archivo se aplica en vivo o se prepara para reinicio |
| `enc` | exactamente `raw` o `gz` | la codificación decide si el blob se descomprime con gunzip |
| entradas de `delete[]` | las mismas reglas de ruta de arriba | una entrada de `delete[]` impulsa una eliminación; un `..` sin comprobar haría `rm` fuera del árbol |

Como esto corre primero, un manifiesto envenenado nunca puede escribir fuera del módulo, nunca eliminar fuera del módulo, y nunca inyectar un token no hex en una línea de comando.

### Los valores del manifiesto nunca tocan un shell

La segunda mitad de la regla: incluso después de que un valor pase la validación, nunca se interpola en `sh`, y nunca se alimenta a `awk system()`. El comando check fue reescrito deliberadamente para no contener ninguna llamada `system()`. El direccionamiento por contenido hace el resto del trabajo: un blob se descarga por su `sha256`, se escribe en una ruta de cache nombrada por ese mismo `sha256`, y los bytes descargados se vuelven a hashear y comparar antes de aplicar nada. Un valor que no sea un digesto limpio de 64 hex nunca llega tan lejos, porque `validate_plan()` ya lo rechazó.

### Una segunda línea de defensa en el apply

`validate_plan()` bloquea `..` **léxicamente**, pero un enlace simbólico preexistente ya dentro del árbol aún podría redirigir una escritura. Así que en el momento del apply `contained()` resuelve la ruta de destino real y confirma que está bajo la base del módulo, fallando de forma cerrada cuando no puede resolver. Las escrituras son atómicas (escribir en un nombre temporal, luego `rename` sobre el destino) y cada sobrescritura se respalda primero a `rollback/`; un respaldo fallido aborta el apply en vez de sobrescribir sin red de seguridad.

---

## Los dos perfiles

VDLU corre en uno de dos perfiles de confianza, establecido por `profile=` en la config.

### `hardened` (el valor por defecto público)

- **La firma es obligatoria.** El manifiesto debe llevar una firma ed25519 válida de una clave en el keyring del dispositivo, o la transacción aborta.
- **El downgrade está bloqueado.** Un manifiesto cuya `version` es menor que la versión instalada se rechaza. Un atacante no puede hacerte retroceder a un build con vulnerabilidad conocida.
- Este es el perfil para cualquier módulo distribuido al público sobre `https://`.

### `trusted` (fuente privada, por SSH)

- La verificación de firma es de **mejor esfuerzo**: la fuente es un feed privado `file://` o por SSH que tú controlas, así que una firma ausente o no verificable no aborta de forma dura.
- **Pero el `sha256` de cada blob aún se comprueba, siempre.** `trusted` relaja *quién firmó el manifiesto*, nunca *si los bytes coinciden con el plan*. La integridad del contenido es innegociable en ambos perfiles.

---

## A prueba de fallos por inversión

Esta es la parte sutil, y es la parte que la mayoría de los sistemas hacen mal.

`trusted` es la **única** cadena que opta por la verificación relajada. El motor no prueba "¿es esto `hardened`?" Prueba "¿es esto **no** `trusted`?":

```sh
prof=$(cfg profile hardened | tr -d '[:space:]')
...
if [ "$prof" != trusted ]; then
    # signature mandatory
fi
```

Así que **cualquier cosa** distinta del literal `trusted` resuelve a comportamiento hardened:

- la línea falta por completo -> hardened
- un typo como `hardend` -> hardened
- `trusted ` con un espacio final, o un `\r` de CRLF -> hardened
- `Trusted` con mayúscula equivocada -> hardened
- un valor mutilado por MITM -> hardened

Una versión anterior ponía por defecto una línea *ausente* en hardened, lo que aún dejaba un *valor* corrompido cayendo hacia la ruta abierta. Eso era un fail-open: una cadena de perfil mutilada podía aceptar en silencio un manifiesto sin firmar, y un manifiesto sin firmar significa un `.so` suministrado por el atacante intercambiado bajo MITM, lo cual es ejecución remota de código a nivel de root. La inversión lo cierra. La única forma de obtener verificación relajada es deletrear `trusted` exactamente, y aún entonces los hashes de los blobs se comprueban. El motor nunca está a un typo de aceptar código sin firmar. (El `tr -d` quita el espacio en blanco extraviado para que un `trusted` legítimo con espaciado descuidado no sea rechazado por error, sin reabrir el agujero.)

**Esta prueba es portante. Debe permanecer `!= trusted` y nunca volverse `== hardened`.**

---

## El manifiesto está ligado al módulo

Una sola clave de release firma muchos módulos. Así que un manifiesto que esté válidamente firmado, para un módulo *distinto*, podría en principio servirse a este (una mala configuración del feed, un intercambio de fuente, o una redirección MITM) y su firma verificaría.

VDLU cierra esto con un vínculo: el campo firmado `module` dentro del manifiesto debe igualar el `MODID` de esta instalación, o el manifiesto se rechaza como un feed de módulo cruzado. Como `module` está dentro de la forma canónica firmada, un atacante no puede cambiarlo sin romper la firma. Un feed válidamente firmado para el módulo B simplemente no se puede aplicar al módulo A.

---

## El verificador delgado en el dispositivo

La verificación en el dispositivo usa **ed25519-mini**, un diminuto comprobador de solo verificación construido sobre TweetNaCl (dominio público). **No hay `openssl` en el dispositivo**.

- La entrada del keyring es la **clave pública de 32 bytes en crudo**, almacenada como `keyring/<key_id>.pub`. (La clave pública PEM es un artefacto solo del lado PC; copiar un PEM en el keyring del dispositivo rompe la verificación, ya que el verificador espera exactamente 32 bytes en crudo.)
- `vdlu-verify <manifest.json> <keyring_dir>` reconstruye la forma canónica (el texto del manifiesto con el campo `sig` eliminado, compacto, claves ordenadas), lo hashea al mensaje hex de 64 caracteres que la firma cubre, decodifica la firma base64, comprueba que sean 64 bytes, y pide a `ed25519-mini <pub32> <msg> <sig64>` un veredicto. rc 0 = válido, cualquier otra cosa = rechazar.
- El binario es estático por ABI (arm64-v8a, armeabi-v7a, x86, x86_64), con un `PROVENANCE.json` que fija las fuentes exactas de TweetNaCl, el hash del wrapper y las banderas de build, de modo que lo que corre como root es auditable.
- El `key_id` del manifiesto se sanea él mismo (sin `/`, sin `..`, sin comillas) antes de usarse para elegir un archivo de keyring, de modo que no puede escapar del directorio del keyring.

### El keyring es solo-flash, verificar-no-copiar, estable

El keyring se envía dentro del módulo en el momento del flasheo y no lo reescribe el motor de actualización. En la re-incorporación la regla es **verificar, no copiar**: el keyring cambia solo en una rotación de clave deliberada, nunca como efecto secundario de una actualización.

### La rotación de clave no deja inservibles las instalaciones antiguas

Cuando una clave de firma se rota, el keyring envía **tanto la clave pública en crudo actual como la anterior**. El verificador selecciona el archivo de clave por el `key_id` del manifiesto, de modo que un feed aún firmado por la clave antigua verifica contra la pubkey antigua, y un feed firmado por la clave nueva verifica contra la nueva. Un dispositivo que no se ha actualizado más allá de la rotación sigue funcionando; nada queda varado.

---

## La allowlist de `key_id` de actualización de módulo

La rotación de clave ya significa que el keyring puede legítimamente contener más de una clave, y un módulo puede contener más de una por una segunda razón: puede enviar una clave de menor confianza que firma un feed *diferente*. El feed de fingerprint es exactamente ese caso. Un módulo puede llevar una clave acotada cuyo único trabajo es firmar un feed de fingerprint, situada en el mismo keyring justo al lado de la clave de release que firma el módulo mismo.

Eso plantea una pregunta que la historia de la rotación por sí sola no responde: una vez que dos claves viven en el keyring, ¿*cuál* de ellas puede firmar una **actualización de módulo**? Una actualización de módulo es lo más poderoso que un manifiesto puede pedir, porque reescribe archivos que el dispositivo ejecuta como root. El verificador solía tomar la pubkey nombrada por el `key_id` del manifiesto y aceptar cualquier clave que resultara estar presente en el keyring. Así que la clave de feed de fingerprint, de menor confianza, si se filtrara, podría firmar un manifiesto de actualización de módulo y el dispositivo lo honraría. Eso es un bypass de la raíz de confianza: una clave pensada para un único trabajo acotado podría impulsar una actualización de root completa sin flasheo.

La corrección fija el `key_id` de actualización de módulo aceptado a una **allowlist** a prueba de fallos, comprobada **antes** de que se seleccione la pubkey. La clave de configuración es `key_id`, y el motor la resuelve así:

- **Un keyring de una sola clave fija automáticamente esa única clave.** El caso común no necesita ninguna configuración: si el keyring contiene exactamente una clave, esa clave *es* la allowlist, y nada más puede firmar una actualización de módulo.
- **Un keyring de varias claves debe establecer `key_id`.** En el momento en que aparece una segunda clave, el motor se niega a adivinar. Falla a prueba de fallos con "multiple keys in keyring; config must pin key_id" hasta que la configuración nombra la clave (o las claves, separadas por comas durante una ventana de rotación) que puede firmar actualizaciones de módulo.

Como la comprobación se ejecuta antes de la selección de la pubkey, un manifiesto que nombra una clave que está presente pero no en la allowlist se rechaza sin que el verificador llegue a cargar esa clave. El conjunto resuelto se refleja en `vdlu-verify` a través de `VDLU_KEYID_ALLOW`, de modo que el comprobador delgado en el dispositivo aplica la misma fijación y los dos no pueden discrepar. Esto se cumple en **ambos** perfiles: `hardened` y `trusted` consultan ambos la allowlist, porque la allowlist decide *qué clave* es una raíz válida de actualización de módulo, no *si* se requiere una firma.

El feed de fingerprint conserva su propia raíz de confianza fijada por separado, `FEED_KEY_ID`. Es una raíz distinta con un trabajo distinto, nunca alcanzable a través de la ruta de actualización de módulo anterior, de modo que fijar la allowlist de actualización de módulo no la toca y una clave de feed filtrada sigue sin poder firmar una actualización de módulo. Este cambio subió `ENGINE_VERSION` a 4.

---

## La exclusión del ancla de confianza del lado del motor

La allowlist de arriba decide *qué* clave puede firmar una actualización de módulo. Un cambio posterior (`ENGINE_VERSION` 5) cierra el riesgo adyacente desde el otro lado: qué tiene permitido tocar siquiera un feed válidamente firmado. Un feed publicado lleva el árbol entero del módulo, y ese árbol incluye el propio directorio `vdlu/` del módulo - el motor, el shim `vdlu-verify`, los binarios de `verify/`, el keyring y la config. Esos son el ancla de confianza. Si una actualización pudiera reescribirlos, una sola clave de firma filtrada podría enviar un verificador nuevo o un keyring nuevo y persistir root indefinidamente.

Así que el motor **ignora** cada ruta `vdlu/` en un plan obtenido. Nunca los obtiene, aplica, ni borra, aun cuando el manifiesto los liste, y tampoco rechaza el manifiesto: el resto del módulo igual se actualiza con normalidad, y solo las rutas `vdlu/` se descartan en silencio. El ancla de confianza puede cambiar **solo** con un re-flash firmado completo del zip del módulo, nunca por la red. Esto complementa la exclusión del lado del producer en `vdlu-pack` (que mantiene esas rutas fuera del feed en primer lugar) con una segunda guarda, independiente, en el dispositivo. El mismo cambio también bajó los topes de endurecimiento a **128 MiB por archivo** y **2 MiB por manifiesto**. Reportado por Solomag (VD-Modules#1).

---

## Lo que cierra el manifiesto de herramientas

El arranque delgado de fetch descarga un `curl` estático en el primer uso para los módulos que no envían el suyo propio. Como ese binario corre como root, la firma de su propio manifiesto (ed25519-mini) y su hash son **obligatorios en cualquier perfil**, incluido `trusted`, antes de que se instale o ejecute. El webview es solo transporte; la confianza viene de la comprobación de firma y hash en el dispositivo, nunca del hecho de que una descarga tuvo éxito.

---

## Lo que un atacante NO PUEDE hacer

Incluso poseyendo el feed, o sentado en el cable como un MITM completo, un atacante no puede:

- **Escribir fuera del módulo.** Las rutas absolutas, `..`, `.`, los caracteres de control y las barras finales se rechazan todos antes de cualquier apply, y la redirección de enlace simbólico se detecta de nuevo en el momento del apply.
- **Eliminar fuera del módulo.** Las entradas de `delete[]` pasan la misma validación de ruta.
- **Inyectar un comando.** Ningún valor del manifiesto se interpola en un shell o `awk system()`; `sha256` debe ser hex puro de 64 o el manifiesto entero se rechaza.
- **Enviar código sin firmar a una instalación pública.** `hardened` hace la firma obligatoria, y el perfil es a prueba de fallos por inversión, de modo que ningún typo o valor mutilado degrada eso.
- **Firmar una actualización de módulo con una clave de menor confianza.** El `key_id` de actualización de módulo está fijado a una allowlist a prueba de fallos, comprobada antes de que se seleccione la pubkey, de modo que una clave de feed de fingerprint filtrada que comparte el keyring no puede firmar una actualización de root completa.
- **Servir aquí el feed firmado de otro módulo.** El campo firmado `module` debe igualar este `MODID`.
- **Hacerte retroceder.** El downgrade está bloqueado en `hardened`.
- **Corromper un blob sin ser detectado.** Cada blob descargado se vuelve a hashear contra el `sha256` del manifiesto en ambos perfiles; un desajuste tras tres intentos aborta la fase sin aplicar nada.
- **Intercambiar un fetcher de root falso.** El `curl` arrancado se comprueba por firma y hash antes de instalarse o ejecutarse, en cada perfil.
- **Aplicar a medias una actualización corrupta.** La transacción solo alcanza `DONE` cuando un re-hash de todo coincide; un apply fallido revierte en vez de sobrescribir sin un respaldo.

---

Ver también: [[Feed Format]] para el esquema del manifiesto, [[Engine]] para la transacción en la que viven estas comprobaciones, y [[Architecture]] para el panorama general.
