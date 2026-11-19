<!--
  ======================================================================
   VDLiveUpdate (VDLU)  ::  flashless, incremental module updates
   A self-update engine for KernelSU/APatch/Magisk modules: fetch only the
   files that changed, apply the live ones with no reboot, verified by ed25519.

   Copyright (C) 2026  VD171
   SPDX-License-Identifier: Apache-2.0

   Licensed under the Apache License, Version 2.0; you may obtain a copy at
   http://www.apache.org/licenses/LICENSE-2.0

   Site           : https://vd171.ru
   Site           : https://vd.priv8.ru
   Source         : https://github.com/VD171/VDLiveUpdate
   GitHub         : @VD171 https://github.com/VD171
   XDA-Developers : @VD171 https://xdaforums.com/m/vd171.4699873/
   Telegram       : @VD_Priv8 https://t.me/VD_Priv8
   Channel        : @Priv8_VD https://t.me/Priv8_VD
   Discord        : @VD.Priv8 https://discord.com/users/1296831918989639721
   E-mail         : vd.priv8@pm.me
  ======================================================================
-->

# VDLiveUpdate

> **Languages:** [English](README.md) · [العربية](README.ar.md) · [Čeština](README.cs.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Svenska](README.sv.md) · [ไทย](README.th.md) · [Türkçe](README.tr.md) · [Українська](README.uk.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

**VDLU** es un motor de autoactualización incremental y sin flasheo para módulos de **KernelSU / APatch / Magisk**. Un módulo instalado se actualiza a sí mismo descargando **solo los archivos que cambiaron** (blobs direccionados por contenido + un manifiesto firmado), aplica en caliente los que puede **sin reiniciar**, y prepara y señala los pocos que sí requieren reinicio (un `.so`, una superposición de `/system`, una `sepolicy.rule`). Sin gestor de root, sin volver a descargar el `.zip` completo, sin reinicio salvo para esos archivos preparados.

Está diseñado para ser **vendorizado** dentro de un módulo (colocado en `<module>/vdlu/`), no para ejecutarse como un módulo en sí.

## Por qué

Una actualización de módulo normal vuelve a enviar el `.zip` completo. Para un módulo grande eso significa una descarga enorme por unas pocas líneas cambiadas, y un manifiesto de actualización estático solo puede apuntar a un `zipUrl`, de modo que no puede servir el sabor (ABI, full vs lite) que el dispositivo realmente tiene. VDLU compara el árbol **instalado** contra un feed firmado y descarga solo los deltas, así una instalación arm64-full sigue siendo arm64-full, una instalación lite sigue siendo lite, y la mayoría de las actualizaciones se aplican en caliente.

## Cómo funciona

- **Productor (PC / release):** `vdlu-pack` convierte un árbol de módulo en un feed direccionado por contenido (`manifest.json` + `blobs/<sha256>`, gzip, deduplicación, `delete[]`); `vdlu-keygen` / `vdlu-sign` (ed25519); `vdlu-gc` poda los blobs huérfanos por referencia a los últimos N manifiestos (a prueba de fallos, dry-run por defecto).
- **Motor (dispositivo):** POSIX sh, sin `jq`. `update.sh` (`check | run | resume | boot | status | cancel`) ejecuta DIFF -> FETCH -> APPLY -> COMMIT como una **transacción reanudable** (journal), con rollback y un lock por `mkdir`. La firma se verifica con el `ed25519-mini` embebido (sin `openssl` en el dispositivo).
- **WebUI:** un panel de Updates listo para integrar (toast de progreso, cancelar, banner de reinicio), JS puro.

## Perfiles

- `trusted`: uso privado, fuente `file://` o SSH, verificación best-effort (el hash siempre).
- `hardened`: uso público, **firma obligatoria**, downgrade bloqueado. El manifiesto está **ligado al id del módulo**, y cada campo se valida fail-closed antes de descargar nada.

## Adóptalo en tu módulo

Vendoriza `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` en `<module>/vdlu/`, embarca tu **clave pública cruda de 32 bytes** como `vdlu/keyring/<id>.pub`, añade un `config` (perfil + fuente), conecta los disparadores (`post-fs-data.sh` pre-zygote para autoactualización en el arranque; un disparador al abrir la WebUI), y añade `vdlu-pack` + `vdlu-sign` a tu release. Consulta [`docs/QUICKSTART.md`](docs/QUICKSTART.md) para una plantilla trabajada.

## Seguridad

- **Cada campo del manifiesto es entrada hostil.** `validate_plan()` rechaza el manifiesto entero fail-closed ante una ruta absoluta o con `..`, un `sha256` que no sean 64 caracteres hex, o un mode / class / encoding inválido, **antes** de cualquier descarga o aplicación.
- La **clave privada de firma nunca toca el CI ni un dispositivo**; solo se embebe la clave pública cruda, y la verificación usa `ed25519-mini`, no `openssl`.
- `hardened` es fail-closed por inversión: cualquier cosa que no sea el literal `trusted` se trata como `hardened`, de modo que un valor de perfil corrupto nunca puede aceptar silenciosamente un manifiesto sin firmar.
- Los archivos de clase reinicio (`.so`, superposición de `/system`, `sepolicy.rule`) se **preparan, nunca se escriben sobre un inodo en vivo**; todo lo demás se aplica en caliente. Una aplicación fallida aborta en lugar de sobrescribir sin respaldo.

## Compilar / probar

Son scripts, no hay nada que compilar. De extremo a extremo (productor + motor juntos):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js`, y abre `webui/demo.html` en un navegador (simula el puente del dispositivo).

## Documentación

- [`INTERFACES.md`](docs/INTERFACES.md): el contrato de costura entre los componentes (la ley de convergencia; trátalo como inmutable).
- [`ENGINE.md`](docs/ENGINE.md): el motor del lado del dispositivo (`update.sh`): la transacción reanudable DIFF -> FETCH -> APPLY -> COMMIT.
- [`PRODUCER.md`](docs/PRODUCER.md): el lado de PC/release: construir y firmar el feed direccionado por contenido (`vdlu-pack`, `vdlu-sign`).
- [`WEBUI.md`](docs/WEBUI.md): el widget integrable del panel de actualizaciones (toast de progreso, cancelar, banner de reinicio).
- [`docs/QUICKSTART.md`](docs/QUICKSTART.md): una guía de adopción paso a paso y fragmentos de cableado.

## Véase también

Proyectos hermanos del mismo autor:

- **[VDBackup](https://github.com/VD171/VD-Backup)**: copia de seguridad y restauración completas de apps y datos como root, gestionadas por entero desde una WebUI.
- **[COPG-VD](https://github.com/VD171/COPG-VD)**: un spoofer de dispositivo que convierte una huella nueva en un perfil coherente y consistente.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: un demonio SSH con root, autónomo y configurable, para KernelSU/APatch/Magisk.
- **[VDInfos](https://github.com/VD171/VD-Infos)**: un depurador de métodos del dispositivo que lee cada elemento a través de todos los métodos que pueden leerlo.
- **[VDGoogle](https://github.com/VD171/VD-Google)**: lee lo que Google registra en tu dispositivo, totalmente en local y sin internet.

## Contactos

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## Licencia

El código propio de VDLiveUpdate es **Apache-2.0**; véase [LICENSE](LICENSE). Vendoriza un pequeño verificador
`ed25519-mini` y un `curl` estático para el arranque de la descarga, cada uno bajo su propia licencia; véanse
[NOTICE.md](NOTICE.md) y los archivos `PROVENANCE.json` junto a los binarios incluidos.

## Marcas

VDLiveUpdate es un proyecto independiente y no oficial, no afiliado ni respaldado por ningún tercero.
"Android" es una marca de Google LLC; "KernelSU", "Magisk" y "APatch" son marcas de sus respectivos
autores. VDLU se ejecuta por completo en tu dispositivo y en tu propio host de release.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Join the channel for updates:** @Priv8_VD https://t.me/Priv8_VD
