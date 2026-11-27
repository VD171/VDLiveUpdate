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

> **Languages:** [English](README.md) · [العربية](README.ar.md) · Čeština · [Deutsch](README.de.md) · [Español](README.es.md) · [فارسی](README.fa.md) · [Français](README.fr.md) · [हिन्दी](README.hi.md) · [Bahasa Indonesia](README.id.md) · [Italiano](README.it.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Nederlands](README.nl.md) · [Polski](README.pl.md) · [Português](README.pt.md) · [Русский](README.ru.md) · [Svenska](README.sv.md) · [ไทย](README.th.md) · [Türkçe](README.tr.md) · [Українська](README.uk.md) · [Tiếng Việt](README.vi.md) · [中文](README.zh.md)

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

**VDLU** je bezflashový, přírůstkový engine pro vlastní aktualizaci modulů **KernelSU / APatch / Magisk**. Nainstalovaný modul se aktualizuje sám tím, že stáhne **jen soubory, které se změnily** (bloby adresované obsahem + podepsaný manifest), aplikuje ty živé **bez restartu** a připraví a označí tu hrstku, která restart opravdu vyžaduje (soubor `.so`, překryv `/system`, `sepolicy.rule`). Žádný správce rootu, žádné opětovné stahování celého `.zip`, žádný restart kromě těch připravených souborů.

Je navržen tak, aby byl **vendorován** do modulu (vložen do `<module>/vdlu/`), nikoli aby běžel jako modul sám o sobě.

## Proč

Běžná aktualizace modulu posílá znovu celý `.zip`. U velkého modulu to znamená velké opětovné stahování kvůli pár změněným řádkům a statický aktualizační manifest může ukázat jen na jeden `zipUrl`, takže nedokáže obsloužit variantu (ABI, full vs lite), kterou zařízení skutečně má. VDLU porovnává **nainstalovaný** strom proti podepsanému feedu a stahuje jen rozdíly, takže instalace arm64-full zůstane arm64-full, instalace lite zůstane lite a většina aktualizací se aplikuje živě.

## Jak to funguje

- **Producent (PC / vydání):** `vdlu-pack` promění strom modulu na feed adresovaný obsahem (`manifest.json` + `blobs/<sha256>`, gzip, deduplikace, `delete[]`), `vdlu-keygen` / `vdlu-sign` (ed25519), `vdlu-gc` prořezává osiřelé bloby podle odkazů z posledních N manifestů (bezpečné při selhání, ve výchozím stavu zkušební běh).
- **Engine (zařízení):** POSIX sh, bez `jq`. `update.sh` (`check | run | resume | boot | status | cancel`) spouští DIFF -> FETCH -> APPLY -> COMMIT jako **obnovitelnou transakci** (journal), s rollbackem a zámkem `mkdir`. Podpis se ověřuje vestavěným `ed25519-mini` (na zařízení žádné `openssl`).
- **WebUI:** zásuvný panel Updates (toast průběhu, zrušit, banner restartu), čisté JS.

## Profily

- `trusted`: soukromé použití, zdroj `file://` nebo SSH, ověření s nejlepší snahou (hash vždy).
- `hardened`: veřejné použití, **podpis povinný**, downgrade zablokován. Manifest je **vázán na id modulu** a každé pole se ověřuje fail-closed, než se cokoli stáhne.

## Zaveďte jej do svého modulu

Vendorujte `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` do `<module>/vdlu/`, vložte svůj **surový 32bajtový veřejný klíč** jako `vdlu/keyring/<id>.pub`, přidejte `config` (profil + zdroj), zapojte spouštěče (`post-fs-data.sh` před zygote pro automatickou aktualizaci při bootu, spouštěč při otevření WebUI) a do svého vydání přidejte `vdlu-pack` + `vdlu-sign`. Hotovou šablonu najdete v [`docs/QUICKSTART.md`](docs/QUICKSTART.md).

## Bezpečnost

- **Každé pole manifestu je nepřátelský vstup.** `validate_plan()` odmítne celý manifest fail-closed při absolutní cestě nebo `..`, při `sha256`, které není 64 hex znaků, nebo při neplatném režimu / třídě / kódování, **dřív** než proběhne jakékoli stahování nebo aplikace.
- **Soukromý podpisový klíč se nikdy nedotkne CI ani zařízení**, vkládá se jen surový veřejný klíč a ověřování používá `ed25519-mini`, nikoli `openssl`.
- `hardened` je fail-closed inverzí: cokoli jiného než doslovné `trusted` se považuje za `hardened`, takže poškozená hodnota profilu nemůže nikdy potichu přijmout nepodepsaný manifest.
- Soubory třídy restart (`.so`, překryv `/system`, `sepolicy.rule`) se **připraví, nikdy se nepíší přes živý inode**, vše ostatní se aplikuje živě. Neúspěšná aplikace raději přeruší, než aby přepsala bez zálohy.

## Sestavení / test

Jsou to skripty, není co kompilovat. Od začátku do konce (producent + engine dohromady):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js` a otevřete `webui/demo.html` v prohlížeči (mockuje most k zařízení).

## AI agenti

Engine se ovládá výhradně ze shellu (`sh engine/update.sh <check|run|resume|boot|status|cancel>` vypíše strojově čitelný stav), takže agent AI může zkontrolovat, použít a obnovit aktualizaci bez rozhraní. Kontrakt spojů mezi komponentami je v [`docs/INTERFACES.md`](docs/INTERFACES.md) a opravy od AI podléhají stejné úrovni kontroly jako kterékoli jiné.

## Dokumentace

- [`INTERFACES.md`](docs/INTERFACES.md): kontrakt švu mezi komponentami (zákon konvergence, ber ho jako neměnný).
- [`ENGINE.md`](docs/ENGINE.md): engine na straně zařízení (`update.sh`): obnovitelná transakce DIFF -> FETCH -> APPLY -> COMMIT.
- [`PRODUCER.md`](docs/PRODUCER.md): strana PC/vydání: sestavení a podepsání obsahově adresovaného feedu (`vdlu-pack`, `vdlu-sign`).
- [`WEBUI.md`](docs/WEBUI.md): zasouvací widget panelu Updates (ukazatel průběhu, zrušení, banner restartu).
- [`docs/QUICKSTART.md`](docs/QUICKSTART.md): průvodce zavedením krok za krokem a úryvky zapojení.

## Viz také

- **[COPG-VD](https://github.com/VD171/COPG-VD)**: podvržení globálního fingerprintu zařízení / Play Integrity, pro celé zařízení s rozsahem pro jednotlivé aplikace a WebUI.
- **[VDBackup](https://github.com/VD171/VD-Backup)**: kompletní záloha a obnova aplikací a dat jako root, řízená zcela z WebUI.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: samostatný rootovaný SSH démon (Dropbear).
- **[VDGoogle](https://github.com/VD171/VD-Google)**: vaše služby Google (RCS, Wallet, atestace Play Integrity) čtené na vašem zařízení bez internetu.
- **[VDInstaller](https://github.com/VD171/VD-Installer)**: bezproblémový rootový sideload instalátor pro jednotlivé, dávkové a rozdělené APK, s přepínačem ověřování Play Protect a podvržením zdroje instalace.
- **[VDInfos](https://github.com/VD171/VD-Infos)**: debugger metod zařízení: čte každou položku všemi metodami, které ji dokážou přečíst, a porovnává je vedle sebe.
- **[VD-Modules](https://github.com/VD171/VD-Modules)**: naše úložiště modulů pro MMRL/WebUI-X (vše z tohoto nainstalujete ze svého root manageru).
- **[@VictorGabriel7Dev/build.prop](https://github.com/VictorGabriel7Dev/build.prop)**: datová sada fingerprintů `build.prop` od Pixelů (fork @T3SL4).
- **[@VictorGabriel7Dev/mtproto-store](https://github.com/VictorGabriel7Dev/mtproto-store)**: použijte Telegram jako úložiště objektů z malého Go CLI.

## Kontakty

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## Licence

Vlastní kód VDLiveUpdate je **Apache-2.0**, viz [LICENSE](LICENSE). Vendoruje malý ověřovač
`ed25519-mini` a statický `curl` pro bootstrap stahování, každý pod vlastní licencí, viz
[NOTICE.md](NOTICE.md) a soubory `PROVENANCE.json` vedle přibalených binárek.

## Ochranné známky

VDLiveUpdate je nezávislý, neoficiální projekt, nijak nespojený s žádnou třetí stranou ani jí neschválený.
"Android" je ochranná známka Google LLC, "KernelSU", "Magisk" a "APatch" jsou známky jejich
příslušných autorů. VDLU běží výhradně na tvém zařízení a na tvém vlastním hostiteli vydání.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Připojte se ke kanálu pro aktualizace:** @Priv8_VD https://t.me/Priv8_VD
