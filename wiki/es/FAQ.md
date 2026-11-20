# FAQ

Respuestas cortas a las preguntas que surgen más. Cada una enlaza a la página con
la historia completa.

## ¿Qué significa "sin flasheo" (flashless)? ¿Igual tengo que flashear la primera vez?

Sí, flasheas una vez. El módulo se instala de la manera normal (flashear el zip en
tu gestor de root). "Sin flasheo" describe cada actualización después de eso: VDLU descarga
solo los archivos que cambiaron y los aplica en su sitio, de modo que nunca vuelves a flashear un
zip completo solo para enviar unas pocas líneas cambiadas. Ver [[Architecture]].

## ¿Una actualización necesita un reinicio?

Usualmente no. La mayoría de los archivos (tu WebUI, binarios, librerías, configs, `module.prop`)
son de clase **live** y se aplican atómicamente sin reinicio. Solo los archivos de clase reboot
(un `.so` bajo `zygisk/`, un overlay `/system/**`, un archivo sepolicy `*.rule`) se
**preparan por etapas** e intercambian en el siguiente arranque, porque un proceso en ejecución ya ha
mapeado el inode en vivo. Cuando eso ocurre la WebUI muestra un banner persistente "reboot to
activate". Ver [[Reboot Handling]].

## ¿Es seguro si el feed sufre MITM o es envenenado?

Sí, en un feed `hardened`. Cada campo del manifiesto se trata como entrada hostil.
El manifiesto debe llevar una firma ed25519 válida sobre su forma canónica, y
`validate_plan()` corre a prueba de fallos **antes de cualquier descarga**: rechaza el manifiesto
entero ante una ruta absoluta o con `..`, un `sha256` que no sean 64 caracteres hex,
o un mode, class o encoding inválido. El manifiesto también está ligado al id de tu módulo,
de modo que un feed válidamente firmado para un módulo distinto no se puede servir en su lugar.
El sha256 de cada blob se verifica tras la descarga sin importar el perfil. Ver
[[Security and Trust Model]].

## ¿Qué necesita en el dispositivo (dependencias)?

Muy poco. `sh` POSIX puro (mksh / busybox / toybox) más el `sha256sum`,
`gzip`, `base64` y `date` de toybox; el verificador `ed25519-mini` embebido; y, solo para
una fuente `https`, un `curl` estático que se descarga una vez y se cachea en Tier-2.
Una fuente `file://` no necesita curl en absoluto. **No hay dependencia de `jq`**: el
motor analiza JSON con un aplanador estilo gron escrito en `awk`. Ver [[Engine]].

## ¿Se requiere openssl en el dispositivo?

No. `openssl` se usa solo en el lado PC/publicación (`vdlu-keygen`, `vdlu-sign`).
En el dispositivo, la verificación de firma usa el delgado binario embebido `ed25519-mini`,
que lee una clave pública de 32 bytes EN CRUDO. Ver [[Producer]] y
[[Security and Trust Model]].

## ¿Cómo roto la clave de firma?

Genera un nuevo par de claves con `vdlu-keygen`, agrega la nueva clave pública de 32 bytes en crudo al
keyring del dispositivo junto a la anterior, y empieza a firmar con el nuevo
`key_id`. El dispositivo elige `<keyring>/<key_id>.pub` por el `key_id` del manifiesto,
de modo que no se necesita ningún cambio del motor. Enviar tanto la clave pública actual como la anterior
significa que una clave rotada nunca deja inservibles las instalaciones antiguas. Ver [[Security and Trust Model]].

## hardened vs trusted - ¿cuál uso?

Usa `hardened` para cualquier feed público (servido sobre `https`, p. ej. GitHub Pages).
Hace la firma obligatoria y bloquea los downgrades. Usa `trusted` solo para una
fuente privada `file://` o por SSH que ya controlas, donde la firma
es de mejor esfuerzo (el hash de cada blob aún se comprueba). En la duda, usa `hardened`:
es el valor por defecto a prueba de fallos, y cualquier valor no-`trusted` se trata como
`hardened`. Ver [[Security and Trust Model]].

## ¿Qué pasa si un blob es manipulado o el manifiesto está malformado?

La actualización aborta y no se aplica nada. Un manifiesto malformado se rechaza entero
por `validate_plan()` antes de cualquier fetch. Un blob cuyo sha256 no coincide con el
manifiesto se rechaza; tres fallos en el mismo blob abortan la fase de fetch sin
aplicar nada. Ante cualquier fallo duro el diario registra `ERROR` y el módulo
queda intacto. Ver [[Engine]].

## ¿Puede una actualización eliminar mis archivos o dejar inservible el dispositivo?

El riesgo está contenido por diseño. Los archivos sobrescritos y eliminados se respaldan primero
a `rollback/<version>/`, y `apply` aborta en vez de sobrescribir sin un
respaldo exitoso. Las eliminaciones corren solo cuando una transacción alcanza `DONE`, nunca
mientras un reinicio siga pendiente. Un apply fallido revierte los archivos en vivo que ya
escribió. Las rutas se validan para contención dentro del directorio del módulo antes de usarse,
de modo que un manifiesto no puede escribir ni eliminar fuera del árbol. Ver [[Engine]] y
[[Security and Trust Model]].

## ¿Funciona en KernelSU Y Magisk Y APatch?

Sí. VDLU es `sh` POSIX plano más una WebUI, incorporado al módulo, de modo que corre en
KernelSU, APatch y Magisk por igual. Usa el puente WebUI del gestor de root
(`ksu.exec`) para manejar el motor y sondear el progreso. Ver [[Architecture]] y
[[WebUI]].

## ¿Qué tan grande es la huella en el dispositivo?

Pequeña. El motor son scripts; los únicos binarios son el verificador `ed25519-mini` por ABI
(diminuto) y, para una fuente `https`, un `curl` estático (~1MB) que se
descarga una vez y se cachea. Un módulo que ya empaqueta su propio `curl` lo reutiliza
y no agrega ninguna descarga. El cache de blobs Tier-2 contiene el contenido verificado más
las últimas 3 versiones de rollback. Ver [[Engine]] y [[Architecture]].
