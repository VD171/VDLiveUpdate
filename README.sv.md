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

# VD Live Update

> **Languages:** [English](README.md) · [العربية](README.ar.md) · [Čeština](README.cs.md) · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Русский](README.ru.md) · Svenska · [ไทย](README.th.md) · [Türkçe](README.tr.md) · [Українська](README.uk.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

<p align="center">
  <img src="images/logo-wordmark.png" alt="VD Live Update" width="320">
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-Apache--2.0-1a7f37" alt="License"></a>
  <a href="https://github.com/VD171/VDLiveUpdate/stargazers"><img src="https://img.shields.io/github/stars/VD171/VDLiveUpdate?color=d29922" alt="Stars"></a>
</p>

<p align="center">
  <a href="docs/QUICKSTART.md">Quickstart</a> ·
  <a href="docs/ENGINE.md">Engine</a> ·
  <a href="docs/PRODUCER.md">Producer</a> ·
  <a href="docs/WEBUI.md">WebUI</a> ·
  <a href="docs/INTERFACES.md">Interfaces</a> ·
  <a href="docs/AI-AGENTS.md">AI agents</a> ·
  <a href="docs/TRUST-MODEL.md">Trust model</a>
</p>

**VDLU** är en flashlös, inkrementell självuppdateringsmotor för **KernelSU / APatch / Magisk**-moduler. En installerad modul uppdaterar sig själv genom att bara hämta **de filer som har ändrats** (innehållsadresserade blobbar + ett signerat manifest), tillämpar de live-tillämpbara **utan en omstart**, och köar och flaggar de få som verkligen kräver en (en `.so`, ett `/system`-overlay, en `sepolicy.rule`). Ingen root-hanterare, ingen ny nedladdning av hela `.zip`-filen, ingen omstart utom för de köade filerna.

Den är utformad för att **vendoriseras** in i en modul (släppas in i `<module>/vdlu/`), inte köras som en egen modul.

## Varför

En vanlig moduluppdatering levererar hela `.zip`-filen igen. För en stor modul betyder det en stor omnedladdning för några få ändrade rader, och ett statiskt uppdateringsmanifest kan bara peka på ett `zipUrl`, så det kan inte betjäna den flavor (ABI, full vs lite) som enheten faktiskt har. VDLU diffar det **installerade** trädet mot ett signerat flöde och hämtar bara deltana, så en arm64-full-installation förblir arm64-full, en lite-installation förblir lite, och de flesta uppdateringar tillämpas live.

## Så fungerar det

- **Producent (PC / release):** `vdlu-pack` förvandlar ett modulträd till ett innehållsadresserat flöde (`manifest.json` + `blobs/<sha256>`, gzip, dedup, `delete[]`), `vdlu-keygen` / `vdlu-sign` (ed25519), `vdlu-gc` gallrar bort föräldralösa blobbar genom referens till de senaste N manifesten (fail-safe, dry-run som standard).
- **Motor (enhet):** POSIX sh, inget `jq`. `update.sh` (`check | run | resume | boot | status | cancel`) kör DIFF -> FETCH -> APPLY -> COMMIT som en **återupptagbar transaktion** (journal), med rollback och ett `mkdir`-lås. Signaturen verifieras av det inbäddade `ed25519-mini` (inget `openssl` på enheten).
- **WebUI:** en inkopplingsbar Updates-panel (förloppstoast, avbryt, omstartsbanner), ren JS.

## Profiler

- `trusted`: privat användning, `file://` eller SSH-källa, verifiering efter bästa förmåga (hash alltid).
- `hardened`: publik användning, **signatur obligatorisk**, nedgradering blockerad. Manifestet är **bundet till modulens id**, och varje fält valideras fail-closed innan något laddas ner.

## Anamma den i din modul

Vendorisera `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` i `<module>/vdlu/`, bädda in din **råa 32-byte publika nyckel** som `vdlu/keyring/<id>.pub`, lägg till en `config` (profil + källa), koppla in triggrarna (`post-fs-data.sh` pre-zygote för automatisk uppdatering vid start, en trigger när WebUI öppnas), och lägg till `vdlu-pack` + `vdlu-sign` i din release. Se [`docs/QUICKSTART.md`](docs/QUICKSTART.md) för en genomarbetad mall.

## Säkerhet

- **Varje manifestfält är fientlig indata.** `validate_plan()` avvisar hela manifestet fail-closed vid en absolut eller `..`-sökväg, en `sha256` som inte är 64 hex-tecken, eller ett ogiltigt mode / class / encoding, **innan** någon hämtning eller tillämpning.
- Den **privata signeringsnyckeln rör aldrig CI eller en enhet**, endast den råa publika nyckeln bäddas in, och verifiering använder `ed25519-mini`, inte `openssl`.
- `hardened` är fail-closed genom inversion: allt annat än det bokstavliga `trusted` behandlas som `hardened`, så ett korrupt profilvärde kan aldrig tyst acceptera ett osignerat manifest.
- Omstartsklassade filer (`.so`, `/system`-overlay, `sepolicy.rule`) **köas, skrivs aldrig över en levande inod**, allt annat tillämpas live. En misslyckad tillämpning avbryter i stället för att skriva över utan en säkerhetskopia.

## Bygga / testa

Det är skript, inget att kompilera. Ände till ände (producent + motor tillsammans):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js`, och öppna `webui/demo.html` i en webbläsare (den mockar enhetsbryggan).

## AI-agenter

Motorn styrs helt från skalet (`sh engine/update.sh <check|run|resume|boot|status|cancel>` skriver ut en maskinläsbar status), så en AI-agent kan kontrollera, tillämpa och återuppta en uppdatering utan gränssnitt. Fogkontraktet mellan komponenterna finns i [`docs/INTERFACES.md`](docs/INTERFACES.md), och patchar från AI håller samma granskningsnivå som alla andra.

## Dokumentation

- [`INTERFACES.md`](docs/INTERFACES.md): sömkontraktet mellan komponenterna (konvergensens lag, behandla det som oföränderligt).
- [`ENGINE.md`](docs/ENGINE.md): motorn på enhetssidan (`update.sh`): den återupptagbara transaktionen DIFF -> FETCH -> APPLY -> COMMIT.
- [`PRODUCER.md`](docs/PRODUCER.md): PC-/releasesidan: bygga och signera det innehållsadresserade flödet (`vdlu-pack`, `vdlu-sign`).
- [`WEBUI.md`](docs/WEBUI.md): den inbäddningsbara Updates-panelwidgeten (förloppstoast, avbryt, omstartsbanner).
- [`docs/QUICKSTART.md`](docs/QUICKSTART.md): en steg-för-steg-guide för anammande och kopplingssnuttar.

## Se även

- **[COPG-VD](https://github.com/VD171/COPG-VD)**: spoofing av enhetens globala fingerprint / Play Integrity, för hela enheten med omfattning per app och ett WebUI.
- **[VDBackup](https://github.com/VD171/VD-Backup)**: fullständig säkerhetskopiering och återställning av appar och data som root, helt styrd från ett WebUI.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: en fristående rootad SSH-daemon (Dropbear).
- **[VDGoogle](https://github.com/VD171/VD-Google)**: dina Google-tjänster (RCS, Wallet, Play Integrity-attesteringar), lästa på din enhet utan internet.
- **[VDInstaller](https://github.com/VD171/VD-Installer)**: en friktionsfri root-sideload-installerare för enskilda, batch- och split-APK:er, med en växel för Play Protect-verifieraren och förfalskning av installationskällan.
- **[VDInfos](https://github.com/VD171/VD-Infos)**: en felsökare för enhetsmetoder: läser varje objekt genom varje metod som kan läsa det och jämför dem sida vid sida.
- **[VD-Modules](https://github.com/VD171/VD-Modules)**: vårt modulrepositorium för MMRL/WebUI-X (installera allt detta från din root-hanterare).
- **[@VictorGabriel7Dev/build.prop](https://github.com/VictorGabriel7Dev/build.prop)**: en datamängd med Pixel-`build.prop`-fingerprints (fork av @T3SL4).
- **[@VictorGabriel7Dev/mtproto-store](https://github.com/VictorGabriel7Dev/mtproto-store)**: använd Telegram som ett objektlager från ett litet Go-CLI.

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

VDLiveUpdates egen kod är **Apache-2.0**, se [LICENSE](LICENSE). Den vendoriserar en liten `ed25519-mini`-verifierare och en statisk `curl` för hämtnings-bootstrappen, var och en under sin egen licens, se
[NOTICE.md](NOTICE.md) och `PROVENANCE.json`-filerna bredvid de medföljande binärerna.

## Varumärken

VDLiveUpdate är ett oberoende, inofficiellt projekt, inte anslutet till eller rekommenderat av någon tredje part.
"Android" är ett varumärke som tillhör Google LLC, "KernelSU", "Magisk" och "APatch" är sina
respektive upphovsmäns märken. VDLU körs helt på din enhet och på din egen release-värd.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Gå med i kanalen för uppdateringar:** @Priv8_VD https://t.me/Priv8_VD
