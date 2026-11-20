# Security and Trust Model

VDLU actualiza un módulo en su sitio, por la red, como root. Eso es mucho poder apuntado a un archivo que viene de un feed, así que todo el motor se construye sobre un único supuesto:

> **Cada campo del manifiesto es entrada hostil.**

Un feed puede ser envenenado en el origen, o intercambiado y mutilado en tránsito por un MITM. Cuando eso ocurre, el manifiesto aún llega luciendo como un manifiesto: lleva rutas de archivos, cadenas `sha256`, una lista `delete[]`, modes, clases y una bandera de codificación. VDLU no trata ninguno de esos como confiable. Valida el plan entero antes de descargar un solo byte, y nunca deja que un valor del manifiesto llegue a un shell.

Esta página es la historia completa de confianza. Ver [[Feed Format]] para el esquema del manifiesto que valida, y [[Engine]] para dónde se ubican estas comprobaciones en la transacción DIFF -> FETCH -> APPLY -> COMMIT.

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

## Lo que cierra el manifiesto de herramientas

El arranque delgado de fetch descarga un `curl` estático en el primer uso para los módulos que no envían el suyo propio. Como ese binario corre como root, la firma de su propio manifiesto (ed25519-mini) y su hash son **obligatorios en cualquier perfil**, incluido `trusted`, antes de que se instale o ejecute. El webview es solo transporte; la confianza viene de la comprobación de firma y hash en el dispositivo, nunca del hecho de que una descarga tuvo éxito.

---

## Lo que un atacante NO PUEDE hacer

Incluso poseyendo el feed, o sentado en el cable como un MITM completo, un atacante no puede:

- **Escribir fuera del módulo.** Las rutas absolutas, `..`, `.`, los caracteres de control y las barras finales se rechazan todos antes de cualquier apply, y la redirección de enlace simbólico se detecta de nuevo en el momento del apply.
- **Eliminar fuera del módulo.** Las entradas de `delete[]` pasan la misma validación de ruta.
- **Inyectar un comando.** Ningún valor del manifiesto se interpola en un shell o `awk system()`; `sha256` debe ser hex puro de 64 o el manifiesto entero se rechaza.
- **Enviar código sin firmar a una instalación pública.** `hardened` hace la firma obligatoria, y el perfil es a prueba de fallos por inversión, de modo que ningún typo o valor mutilado degrada eso.
- **Servir aquí el feed firmado de otro módulo.** El campo firmado `module` debe igualar este `MODID`.
- **Hacerte retroceder.** El downgrade está bloqueado en `hardened`.
- **Corromper un blob sin ser detectado.** Cada blob descargado se vuelve a hashear contra el `sha256` del manifiesto en ambos perfiles; un desajuste tras tres intentos aborta la fase sin aplicar nada.
- **Intercambiar un fetcher de root falso.** El `curl` arrancado se comprueba por firma y hash antes de instalarse o ejecutarse, en cada perfil.
- **Aplicar a medias una actualización corrupta.** La transacción solo alcanza `DONE` cuando un re-hash de todo coincide; un apply fallido revierte en vez de sobrescribir sin un respaldo.

---

Ver también: [[Feed Format]] para el esquema del manifiesto, [[Engine]] para la transacción en la que viven estas comprobaciones, y [[Architecture]] para el panorama general.
