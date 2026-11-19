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

**VDLU** är en flashlös, inkrementell självuppdateringsmotor för **KernelSU / APatch / Magisk**-moduler. En installerad modul uppdaterar sig själv genom att bara hämta **de filer som har ändrats** (innehållsadresserade blobbar + ett signerat manifest), tillämpar de live-tillämpbara **utan en omstart**, och köar och flaggar de få som verkligen kräver en (en `.so`, ett `/system`-overlay, en `sepolicy.rule`). Ingen root-hanterare, ingen ny nedladdning av hela `.zip`-filen, ingen omstart utom för de köade filerna.

Den är utformad för att **vendoriseras** in i en modul (släppas in i `<module>/vdlu/`), inte köras som en egen modul.

## Varför

En vanlig moduluppdatering levererar hela `.zip`-filen igen. För en stor modul betyder det en stor omnedladdning för några få ändrade rader, och ett statiskt uppdateringsmanifest kan bara peka på ett `zipUrl`, så det kan inte betjäna den flavor (ABI, full vs lite) som enheten faktiskt har. VDLU diffar det **installerade** trädet mot ett signerat flöde och hämtar bara deltana, så en arm64-full-installation förblir arm64-full, en lite-installation förblir lite, och de flesta uppdateringar tillämpas live.

## Så fungerar det

- **Producent (PC / release):** `vdlu-pack` förvandlar ett modulträd till ett innehållsadresserat flöde (`manifest.json` + `blobs/<sha256>`, gzip, dedup, `delete[]`); `vdlu-keygen` / `vdlu-sign` (ed25519); `vdlu-gc` gallrar bort föräldralösa blobbar genom referens till de senaste N manifesten (fail-safe, dry-run som standard).
- **Motor (enhet):** POSIX sh, inget `jq`. `update.sh` (`check | run | resume | boot | status | cancel`) kör DIFF -> FETCH -> APPLY -> COMMIT som en **återupptagbar transaktion** (journal), med rollback och ett `mkdir`-lås. Signaturen verifieras av det inbäddade `ed25519-mini` (inget `openssl` på enheten).
- **WebUI:** en inkopplingsbar Updates-panel (förloppstoast, avbryt, omstartsbanner), ren JS.

## Profiler

- `trusted`: privat användning, `file://`- eller SSH-källa, verifiering efter bästa förmåga (hash alltid).
- `hardened`: publik användning, **signatur obligatorisk**, nedgradering blockerad. Manifestet är **bundet till modulens id**, och varje fält valideras fail-closed innan något laddas ner.

## Anamma den i din modul

Vendorisera `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` i `<module>/vdlu/`, bädda in din **råa 32-byte publika nyckel** som `vdlu/keyring/<id>.pub`, lägg till en `config` (profil + källa), koppla in triggrarna (`post-fs-data.sh` pre-zygote för automatisk uppdatering vid start; en trigger när WebUI öppnas), och lägg till `vdlu-pack` + `vdlu-sign` i din release. Se [`integration/`](integration/) för en genomarbetad mall.

## Säkerhet

- **Varje manifestfält är fientlig indata.** `validate_plan()` avvisar hela manifestet fail-closed vid en absolut eller `..`-sökväg, en `sha256` som inte är 64 hex-tecken, eller ett ogiltigt mode / class / encoding, **innan** någon hämtning eller tillämpning.
- Den **privata signeringsnyckeln rör aldrig CI eller en enhet**; endast den råa publika nyckeln bäddas in, och verifiering använder `ed25519-mini`, inte `openssl`.
- `hardened` är fail-closed genom inversion: allt annat än det bokstavliga `trusted` behandlas som `hardened`, så ett korrupt profilvärde kan aldrig tyst acceptera ett osignerat manifest.
- Omstartsklassade filer (`.so`, `/system`-overlay, `sepolicy.rule`) **köas, skrivs aldrig över en levande inod**; allt annat tillämpas live. En misslyckad tillämpning avbryter i stället för att skriva över utan en säkerhetskopia.

## Bygga / testa

Det är skript, inget att kompilera. Ände till ände (producent + motor tillsammans):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js`, och öppna `webui/demo.html` i en webbläsare (den mockar enhetsbryggan).

## Dokumentation

- [`INTERFACES.md`](docs/INTERFACES.md): sömkontraktet mellan komponenterna (konvergensens lag; behandla det som oföränderligt).
- `integration/`: en steg-för-steg-guide för anammande och kopplingssnuttar.

## Se även

Systerprojekt av samma författare:

- **[VDBackup](https://github.com/VD171/VD-Backup)**: fullständig säkerhetskopiering och återställning av appar och data som root, helt styrd från ett WebUI.
- **[COPG-VD](https://github.com/VD171/COPG-VD)**: en enhetsspoofer som förvandlar ett färskt fingerprint till en sammanhängande, konsekvent profil.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: en fristående, konfigurerbar rootad SSH-daemon för KernelSU/APatch/Magisk.
- **[VDInfos](https://github.com/VD171/VD-Infos)**: en felsökare för enhetsmetoder som läser varje objekt genom varje metod som kan läsa det.
- **[VDGoogle](https://github.com/VD171/VD-Google)**: läser vad Google registrerar på din enhet, helt på enheten och utan internet.

## Kontakter

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## Licens

VDLiveUpdates egen kod är **Apache-2.0**; se [LICENSE](LICENSE). Den vendoriserar en liten `ed25519-mini`-verifierare och en statisk `curl` för hämtnings-bootstrappen, var och en under sin egen licens; se
[NOTICE.md](NOTICE.md) och `PROVENANCE.json`-filerna bredvid de medföljande binärerna.

## Varumärken

VDLiveUpdate är ett oberoende, inofficiellt projekt, inte anslutet till eller rekommenderat av någon tredje part.
"Android" är ett varumärke som tillhör Google LLC; "KernelSU", "Magisk" och "APatch" är sina
respektive upphovsmäns märken. VDLU körs helt på din enhet och på din egen release-värd.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Join the channel for updates:** @Priv8_VD https://t.me/Priv8_VD
