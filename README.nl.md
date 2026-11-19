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

**VDLU** is een flashloze, incrementele zelf-updateengine voor **KernelSU- / APatch- / Magisk**-modules. Een geinstalleerde module werkt zichzelf bij door **alleen de bestanden die zijn gewijzigd** op te halen (content-geadresseerde blobs + een ondertekend manifest), past de live bestanden toe **zonder herstart**, en zet de paar bestanden die er wel een vereisen (een `.so`, een `/system`-overlay, een `sepolicy.rule`) klaar en markeert ze. Geen root-manager, geen volledige `.zip` opnieuw downloaden, geen herstart behalve voor die klaargezette bestanden.

Het is ontworpen om in een module te worden **gevendord** (geplaatst in `<module>/vdlu/`), niet om zelf als module te draaien.

## Waarom

Een normale module-update levert de hele `.zip` opnieuw. Voor een grote module betekent dat een flinke herdownload voor een paar gewijzigde regels, en een statisch update-manifest kan maar naar een `zipUrl` wijzen, zodat het de flavor (ABI, full versus lite) die het apparaat werkelijk heeft niet kan leveren. VDLU vergelijkt de **geinstalleerde** boom met een ondertekende feed en haalt alleen de delta's op, zodat een arm64-full-installatie arm64-full blijft, een lite-installatie lite blijft, en de meeste updates live worden toegepast.

## Hoe het werkt

- **Producer (pc / release):** `vdlu-pack` zet een moduleboom om in een content-geadresseerde feed (`manifest.json` + `blobs/<sha256>`, gzip, dedup, `delete[]`); `vdlu-keygen` / `vdlu-sign` (ed25519); `vdlu-gc` snoeit verweesde blobs weg op basis van verwijzing naar de laatste N manifesten (fail-safe, standaard dry-run).
- **Engine (apparaat):** POSIX sh, geen `jq`. `update.sh` (`check | run | resume | boot | status | cancel`) draait DIFF -> FETCH -> APPLY -> COMMIT als een **hervatbare transactie** (journaal), met rollback en een `mkdir`-slot. De handtekening wordt geverifieerd door de ingebedde `ed25519-mini` (geen `openssl` op het apparaat).
- **WebUI:** een kant-en-klaar Updates-paneel (voortgangstoast, annuleren, herstartbanner), vanilla JS.

## Profielen

- `trusted`: prive gebruik, `file://`- of SSH-bron, best-effort verificatie (hash altijd).
- `hardened`: openbaar gebruik, **handtekening verplicht**, downgrade geblokkeerd. Het manifest is **gebonden aan de module-id**, en elk veld wordt fail-closed gevalideerd voordat er iets wordt gedownload.

## Neem het op in je module

Vendor `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` in `<module>/vdlu/`, neem je **ruwe 32-byte publieke sleutel** mee als `vdlu/keyring/<id>.pub`, voeg een `config` toe (profiel + bron), bedraad de triggers (`post-fs-data.sh` pre-zygote voor automatische update bij het opstarten; een WebUI-open-trigger), en voeg `vdlu-pack` + `vdlu-sign` toe aan je release. Zie [`docs/QUICKSTART.md`](docs/QUICKSTART.md) voor een uitgewerkte sjabloon.

## Beveiliging

- **Elk manifestveld is vijandige invoer.** `validate_plan()` weigert het hele manifest fail-closed bij een absoluut pad of een `..`-pad, een `sha256` die geen 64 hex-tekens is, of een ongeldige mode / class / encoding, **voordat** er wordt opgehaald of toegepast.
- De **private ondertekeningssleutel raakt nooit CI of een apparaat**; alleen de ruwe publieke sleutel wordt ingebed, en de verificatie gebruikt `ed25519-mini`, niet `openssl`.
- `hardened` is fail-closed door inversie: alles behalve het letterlijke `trusted` wordt als `hardened` behandeld, zodat een beschadigde profielwaarde nooit stilletjes een niet-ondertekend manifest kan accepteren.
- Bestanden van de herstartklasse (`.so`, `/system`-overlay, `sepolicy.rule`) worden **klaargezet, nooit over een live inode geschreven**; al het andere wordt live toegepast. Een mislukte toepassing breekt af in plaats van zonder back-up te overschrijven.

## Bouwen / testen

Het zijn scripts, er valt niets te compileren. End-to-end (producer + engine samen):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js`, en open `webui/demo.html` in een browser (het bootst de apparaatbrug na).

## Documentatie

- [`INTERFACES.md`](docs/INTERFACES.md): het naadcontract tussen de componenten (de wet van convergentie; behandel het als onveranderlijk).
- [`ENGINE.md`](docs/ENGINE.md): de engine aan de apparaatzijde (`update.sh`): de hervatbare transactie DIFF -> FETCH -> APPLY -> COMMIT.
- [`PRODUCER.md`](docs/PRODUCER.md): de PC-/releasekant: het content-geadresseerde feed bouwen en ondertekenen (`vdlu-pack`, `vdlu-sign`).
- [`WEBUI.md`](docs/WEBUI.md): de kant-en-klare Updates-paneelwidget (voortgangstoast, annuleren, herstartbanner).
- [`docs/QUICKSTART.md`](docs/QUICKSTART.md): een stapsgewijze adoptiegids en bedradingssnippets.

## Zie ook

Zusterprojecten van dezelfde auteur:

- **[VDBackup](https://github.com/VD171/VD-Backup)**: volledige back-up en herstel van apps en gegevens als root, volledig aangestuurd vanuit een WebUI.
- **[COPG-VD](https://github.com/VD171/COPG-VD)**: een apparaatspoofer die een verse fingerprint omzet in een coherent, consistent profiel.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: een zelfstandige, configureerbare root-SSH-daemon voor KernelSU/APatch/Magisk.
- **[VDInfos](https://github.com/VD171/VD-Infos)**: een apparaatmethode-debugger die elk item leest via elke methode die het kan lezen.
- **[VDGoogle](https://github.com/VD171/VD-Google)**: leest wat Google op je apparaat vastlegt, volledig op het apparaat en zonder internet.

## Contact

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## Licentie

De eigen code van VDLiveUpdate is **Apache-2.0**; zie [LICENSE](LICENSE). Het vendort een kleine `ed25519-mini`-
verifier en een statische `curl` voor de ophaalbootstrap, elk onder zijn eigen licentie; zie
[NOTICE.md](NOTICE.md) en de `PROVENANCE.json`-bestanden naast de meegeleverde binaries.

## Handelsmerken

VDLiveUpdate is een onafhankelijk, onofficieel project, niet gelieerd aan of onderschreven door een derde partij.
"Android" is een handelsmerk van Google LLC; "KernelSU", "Magisk" en "APatch" zijn de merken van hun
respectieve auteurs. VDLU draait volledig op je eigen apparaat en op je eigen releasehost.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Join the channel for updates:** @Priv8_VD https://t.me/Priv8_VD
