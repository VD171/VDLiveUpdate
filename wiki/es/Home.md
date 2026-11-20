# VDLiveUpdate (VDLU)

**VDLU es un motor de autoactualización incremental y sin flasheo para módulos de KernelSU / APatch / Magisk: un módulo instalado actualiza sus propios archivos a través de un feed firmado, descargando solo lo que cambió y aplicando la mayor parte sin reiniciar.**

Una actualización normal de un módulo vuelve a enviar todo el `.zip`, de modo que unas pocas líneas cambiadas cuestan una redescarga completa, y un manifiesto de actualización estático solo puede apuntar a un único `zipUrl` (un solo sabor para todos los dispositivos). VDLU toma otro camino: compara el árbol que está realmente instalado contra un feed firmado y direccionado por contenido, descarga solo los deltas y los escribe en su sitio. Una instalación arm64 completa sigue siendo arm64 completa, una instalación lite sigue siendo lite, y el módulo nunca se vuelve a flashear.

VDLU está pensado para ser **incorporado (vendored)** dentro de un módulo, colocado en `<module>/vdlu/`. No es un módulo por sí mismo.

## Objetivos

- **Autoactualización sin flasheo.** Actualizar un módulo instalado en su sitio, por aire, sin gestor de root, sin reflashear el `.zip` y sin perder el sabor instalado.
- **Incremental por contenido.** Transferir solo los blobs cuyo contenido cambió. Un feed direccionado por contenido (`manifest.json` + `blobs/<sha256>`) hace que los archivos sin cambios o revertidos nunca se vuelvan a descargar.
- **Sin reinicio donde es seguro.** Aplicar los archivos corrientes en vivo, de inmediato. Reservar un reinicio por etapas solo para los pocos archivos que realmente lo necesitan (un `.so`, un overlay de `/system`, un `sepolicy.rule`).
- **Ligero en el dispositivo.** `sh` POSIX puro, sin `jq`, sin `bash`, sin `openssl` en el dispositivo. La verificación se apoya en un `ed25519-mini` embebido; el único binario que se descarga es un `curl` estático, usado solo para feeds `https`.
- **A prueba de fallos y honesto.** Cada campo del manifiesto se trata como entrada hostil y se valida antes de descargar nada. Nada se reporta como "hecho" a menos que un re-hash lo demuestre, y nada se sobrescribe sin un respaldo previo.

## Particularidades

Lo que hace a VDLU distinto de un cliente OTA típico:

- **Sin flasheo e incremental.** Diff / fetch / apply direccionado por contenido con deduplicación: el dispositivo calcula el delta contra el feed firmado y descarga solo los blobs que faltan.
- **Sin reinicio donde es posible.** Los archivos corrientes se aplican en vivo; solo los `.so`, los overlays de `/system` y los archivos `sepolicy.rule` se preparan por etapas y se intercambian en un único reinicio. Ver [[Reboot Handling]].
- **`sh` POSIX en el dispositivo.** Corre bajo toybox / busybox / mksh. Sin `jq` (un aplanador estilo `gron` en `awk` analiza el JSON), sin `bash`ismos, sin runtime pesado.
- **Verificación ligera.** Un `ed25519-mini` embebido verifica las firmas. **No hay `openssl` en el dispositivo**; la clave privada nunca toca un dispositivo ni CI.
- **Seguridad a prueba de fallos.** `validate_plan()` rechaza el manifiesto **entero** ante cualquier campo malo (una ruta absoluta o con `..`, un `sha256` que no sean 64 caracteres hex, un mode / class / encoding inválido). Dos perfiles, `trusted` y `hardened`, con `hardened` a prueba de fallos por inversión. Ver [[Security and Trust Model]].
- **Reanudable y atómico.** Un diario hace que cada transacción sea segura ante caídas; las escrituras usan `rename` / `mv`; se toma un respaldo antes de cualquier sobrescritura, de modo que un apply fallido revierte en vez de corromper el módulo.

## Empieza aquí

| Si quieres... | Ve a |
|---|---|
| Adoptar VDLU en tu módulo, paso a paso | [[Quick Start]] |
| Entender todo el sistema de un vistazo | [[Architecture]] |
| Conocer el motor del lado del dispositivo (`update.sh`) | [[Engine]] |
| Construir y firmar un feed en tu PC | [[Producer]] |
| Insertar el panel de Updates | [[WebUI]] |
| Leer el modelo de confianza y la postura ante amenazas | [[Security and Trust Model]] |
| Ver la disposición del manifiesto y los blobs | [[Feed Format]] |
| Saber qué reinicia y por qué | [[Reboot Handling]] |
| Hacer una pregunta común | [[FAQ]] |
| Contribuir | [[Contributing]] |

## Enlaces del proyecto

- **Código fuente:** https://github.com/VD171/VDLiveUpdate
- **Canal (actualizaciones):** @Priv8_VD https://t.me/Priv8_VD

VDLiveUpdate es un proyecto independiente y no oficial. "Android" es una marca registrada de Google LLC; "KernelSU", "Magisk" y "APatch" son marcas de sus respectivos autores. VDLU corre enteramente en tu dispositivo y en tu propio host de publicación.
