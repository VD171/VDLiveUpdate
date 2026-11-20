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

**VDLU** è un motore di auto-aggiornamento incrementale e senza flash per i moduli **KernelSU / APatch / Magisk**. Un modulo installato si aggiorna da sé scaricando **solo i file che sono cambiati** (blob indirizzati per contenuto + un manifest firmato), applica quelli live **senza riavvio**, e mette in staging e segnala i pochi che un riavvio lo richiedono davvero (un `.so`, un overlay di `/system`, una `sepolicy.rule`). Nessun root manager, nessun riscaricamento dell'intero `.zip`, nessun riavvio tranne che per quei file in staging.

È progettato per essere **incorporato (vendored)** in un modulo (inserito in `<module>/vdlu/`), non eseguito come modulo a sé stante.

## Perché

Un normale aggiornamento di modulo rispedisce di nuovo l'intero `.zip`. Per un modulo grande questo significa un pesante riscaricamento per poche righe cambiate, e un manifest di aggiornamento statico può puntare a un solo `zipUrl`, quindi non può servire il flavor (ABI, full o lite) che il dispositivo possiede realmente. VDLU confronta (diff) l'albero **installato** con un feed firmato e scarica solo i delta, così un'installazione arm64-full resta arm64-full, un'installazione lite resta lite, e la maggior parte degli aggiornamenti si applica live.

## Come funziona

- **Producer (PC / rilascio):** `vdlu-pack` trasforma un albero di modulo in un feed indirizzato per contenuto (`manifest.json` + `blobs/<sha256>`, gzip, dedup, `delete[]`); `vdlu-keygen` / `vdlu-sign` (ed25519); `vdlu-gc` pota i blob orfani in base al riferimento agli ultimi N manifest (fail-safe, dry-run per impostazione predefinita).
- **Engine (dispositivo):** POSIX sh, niente `jq`. `update.sh` (`check | run | resume | boot | status | cancel`) esegue DIFF -> FETCH -> APPLY -> COMMIT come una **transazione riprendibile (resumable)** (journal), con rollback e un lock `mkdir`. La firma è verificata dall'`ed25519-mini` incorporato (nessun `openssl` sul dispositivo).
- **WebUI:** un pannello Updates pronto all'uso (toast di avanzamento, cancel, banner di riavvio), JS vanilla.

## Profili

- `trusted`: uso privato, sorgente `file://` o SSH, verifica best-effort (hash sempre).
- `hardened`: uso pubblico, **firma obbligatoria**, downgrade bloccato. Il manifest è **legato all'id del modulo**, e ogni campo è validato in modalità fail-closed prima che venga scaricato qualsiasi cosa.

## Adottalo nel tuo modulo

Incorpora (vendor) `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` in `<module>/vdlu/`, imbarca la tua **chiave pubblica grezza da 32 byte** come `vdlu/keyring/<id>.pub`, aggiungi un `config` (profilo + sorgente), collega i trigger (`post-fs-data.sh` pre-zygote per l'auto-update all'avvio; un trigger di apertura della WebUI), e aggiungi `vdlu-pack` + `vdlu-sign` al tuo rilascio. Vedi [`docs/QUICKSTART.md`](docs/QUICKSTART.md) per un modello già pronto.

## Sicurezza

- **Ogni campo del manifest è input ostile.** `validate_plan()` rifiuta l'intero manifest in modalità fail-closed su un percorso assoluto o con `..`, un `sha256` che non sia 64 caratteri esadecimali, o un mode / class / encoding non valido, **prima** di qualsiasi fetch o apply.
- La **chiave di firma privata non tocca mai la CI né un dispositivo**; solo la chiave pubblica grezza è incorporata, e la verifica usa `ed25519-mini`, non `openssl`.
- `hardened` è fail-closed per inversione: qualsiasi cosa diversa dal letterale `trusted` è trattata come `hardened`, così un valore di profilo corrotto non può mai accettare silenziosamente un manifest non firmato.
- I file di classe-riavvio (`.so`, overlay di `/system`, `sepolicy.rule`) sono **messi in staging, mai scritti sopra un inode live**; tutto il resto si applica live. Un apply fallito aborta anziché sovrascrivere senza un backup.

## Build / test

Sono script, niente da compilare. End-to-end (producer + engine insieme):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js`, e apri `webui/demo.html` in un browser (simula (mock) il bridge del dispositivo).

## Documentazione

- [`INTERFACES.md`](docs/INTERFACES.md): il contratto di giunzione (seam contract) tra i componenti (la legge della convergenza; trattalo come immutabile).
- [`ENGINE.md`](docs/ENGINE.md): il motore lato dispositivo (`update.sh`): la transazione ripristinabile DIFF -> FETCH -> APPLY -> COMMIT.
- [`PRODUCER.md`](docs/PRODUCER.md): il lato PC/rilascio: costruire e firmare il feed indirizzato per contenuto (`vdlu-pack`, `vdlu-sign`).
- [`WEBUI.md`](docs/WEBUI.md): il widget integrabile del pannello Updates (toast di avanzamento, annulla, banner di riavvio).
- [`docs/QUICKSTART.md`](docs/QUICKSTART.md): una guida all'adozione passo-passo e snippet di wiring.

## Vedi anche

Progetti fratelli dello stesso autore:

- **[VDInfos](https://github.com/VD171/VD-Infos)**: un debugger di metodi del dispositivo che legge ogni elemento attraverso ogni metodo in grado di leggerlo.
- **[VDGoogle](https://github.com/VD171/VD-Google)**: legge ciò che Google registra sul tuo dispositivo, interamente on-device e senza internet.
- **[COPG-VD](https://github.com/VD171/COPG-VD)**: uno spoofer di dispositivo che trasforma un fingerprint fresco in un profilo coerente e consistente.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: un daemon SSH con root autonomo e configurabile per KernelSU/APatch/Magisk.
- **[VDBackup](https://github.com/VD171/VD-Backup)**: backup e ripristino completi di app e dati come root, guidati interamente da una WebUI.
- **[VDInstaller](https://github.com/VD171/VD-Installer)**: un installer sideload con root e senza attriti per APK singoli, in batch e split, con un interruttore per il verificatore Play Protect e lo spoofing della sorgente di installazione.

## Contatti

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## Licenza

Il codice proprio di VDLiveUpdate è **Apache-2.0**; vedi [LICENSE](LICENSE). Incorpora un piccolo
verifier `ed25519-mini` e un `curl` statico per il bootstrap del fetch, ciascuno con la propria licenza; vedi
[NOTICE.md](NOTICE.md) e i file `PROVENANCE.json` accanto ai binari inclusi.

## Marchi

VDLiveUpdate è un progetto indipendente e non ufficiale, non affiliato né approvato da terze parti.
"Android" è un marchio di Google LLC; "KernelSU", "Magisk" e "APatch" sono marchi dei loro
rispettivi autori. VDLU gira interamente sul tuo dispositivo e sul tuo host di rilascio.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`
