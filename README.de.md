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

**VDLU** ist eine flashlose, inkrementelle Selbstaktualisierungs-Engine für **KernelSU- / APatch- / Magisk**-Module. Ein installiertes Modul aktualisiert sich selbst, indem es **nur die geänderten Dateien** holt (inhaltsadressierte Blobs + ein signiertes Manifest), die live anwendbaren **ohne Neustart** anwendet und die wenigen, die einen Neustart brauchen, bereitstellt und markiert (eine `.so`, ein `/system`-Overlay, eine `sepolicy.rule`). Kein Root-Manager, kein erneutes Herunterladen der gesamten `.zip`, kein Neustart außer für diese bereitgestellten Dateien.

Sie ist dafür gedacht, in ein Modul **eingebettet (vendored)** zu werden (abgelegt unter `<module>/vdlu/`), nicht selbst als Modul zu laufen.

## Warum

Eine normale Modulaktualisierung liefert die gesamte `.zip` erneut aus. Bei einem großen Modul bedeutet das einen großen erneuten Download für ein paar geänderte Zeilen, und ein statisches Aktualisierungs-Manifest kann nur auf eine `zipUrl` zeigen, kann also nicht die Variante (ABI, full vs lite) ausliefern, die das Gerät tatsächlich hat. VDLU vergleicht den **installierten** Baum gegen einen signierten Feed und holt nur die Deltas, sodass eine arm64-full-Installation arm64-full bleibt, eine lite-Installation lite bleibt und die meisten Aktualisierungen live angewendet werden.

## Wie es funktioniert

- **Producer (PC / Release):** `vdlu-pack` verwandelt einen Modulbaum in einen inhaltsadressierten Feed (`manifest.json` + `blobs/<sha256>`, gzip, Deduplizierung, `delete[]`); `vdlu-keygen` / `vdlu-sign` (ed25519); `vdlu-gc` beschneidet verwaiste Blobs anhand von Verweisen auf die letzten N Manifeste (ausfallsicher, standardmäßig Dry-Run).
- **Engine (Gerät):** POSIX sh, kein `jq`. `update.sh` (`check | run | resume | boot | status | cancel`) führt DIFF -> FETCH -> APPLY -> COMMIT als **fortsetzbare Transaktion** (Journal) aus, mit Rollback und einem `mkdir`-Lock. Die Signatur wird vom eingebetteten `ed25519-mini` geprüft (kein `openssl` auf dem Gerät).
- **WebUI:** ein einsteckbares Updates-Panel (Fortschritts-Toast, Abbrechen, Neustart-Banner), reines JS.

## Profile

- `trusted`: private Nutzung, Quelle `file://` oder SSH, Best-Effort-Prüfung (Hash immer).
- `hardened`: öffentliche Nutzung, **Signatur verpflichtend**, Downgrade blockiert. Das Manifest ist **an die Modul-ID gebunden**, und jedes Feld wird fail-closed validiert, bevor irgendetwas heruntergeladen wird.

## In dein Modul übernehmen

Bette `engine/update.sh` + `vdlu-verify` + `verify/<abi>/ed25519-mini` in `<module>/vdlu/` ein, lege deinen **rohen 32-Byte-Public-Key** als `vdlu/keyring/<id>.pub` bei, füge eine `config` hinzu (Profil + Quelle), verdrahte die Trigger (`post-fs-data.sh` vor Zygote für die automatische Aktualisierung beim Boot; einen Trigger beim Öffnen der WebUI) und nimm `vdlu-pack` + `vdlu-sign` in deinen Release auf. Eine ausgearbeitete Vorlage findest du unter [`docs/QUICKSTART.md`](docs/QUICKSTART.md).

## Sicherheit

- **Jedes Manifestfeld ist feindlicher Input.** `validate_plan()` weist das gesamte Manifest fail-closed ab bei einem absoluten Pfad oder `..`, einem `sha256`, das nicht 64 Hex-Zeichen hat, oder einem ungültigen mode / class / encoding, **bevor** irgendetwas geholt oder angewendet wird.
- **Der private Signaturschlüssel berührt nie CI oder ein Gerät**; nur der rohe Public-Key wird eingebettet, und die Prüfung nutzt `ed25519-mini`, nicht `openssl`.
- `hardened` ist fail-closed per Umkehrung: alles andere als das wörtliche `trusted` wird als `hardened` behandelt, sodass ein beschädigter Profilwert niemals stillschweigend ein unsigniertes Manifest akzeptieren kann.
- Dateien der Neustart-Klasse (`.so`, `/system`-Overlay, `sepolicy.rule`) werden **bereitgestellt, nie über einen lebenden Inode geschrieben**; alles andere wird live angewendet. Eine fehlgeschlagene Anwendung bricht lieber ab, als ohne Backup zu überschreiben.

## Build / Test

Es sind Skripte, nichts zu kompilieren. Durchgängig (Producer + Engine zusammen):

```sh
producer/vdlu-keygen demo /tmp/k
producer/vdlu-pack /tmp/tree /tmp/feed demo 1 --version-name v1
producer/vdlu-sign /tmp/feed/manifest.json /tmp/k/demo.pem demo
VDLU_DIR=... MODULE_DIR=... MODID=demo sh engine/update.sh check   # then run / boot
```

`sh -n engine/*.sh`, `node --check webui/vdlu.js` und öffne `webui/demo.html` in einem Browser (es mockt die Gerätebrücke).

## Dokumentation

- [`INTERFACES.md`](docs/INTERFACES.md): der Nahtvertrag zwischen den Komponenten (das Gesetz der Konvergenz; behandle ihn als unveränderlich).
- [`ENGINE.md`](docs/ENGINE.md): die geräteseitige Engine (`update.sh`): die fortsetzbare Transaktion DIFF -> FETCH -> APPLY -> COMMIT.
- [`PRODUCER.md`](docs/PRODUCER.md): die PC-/Release-Seite: Bau und Signierung des inhaltsadressierten Feeds (`vdlu-pack`, `vdlu-sign`).
- [`WEBUI.md`](docs/WEBUI.md): das einbindbare Updates-Panel-Widget (Fortschritts-Toast, Abbrechen, Neustart-Banner).
- [`docs/QUICKSTART.md`](docs/QUICKSTART.md): eine Schritt-für-Schritt-Anleitung zur Übernahme und Verdrahtungs-Snippets.

## Siehe auch

Schwesterprojekte desselben Autors:

- **[VDInfos](https://github.com/VD171/VD-Infos)**: ein Geräte-Methoden-Debugger, der jedes Element über jede Methode liest, die es lesen kann.
- **[VDGoogle](https://github.com/VD171/VD-Google)**: liest, was Google auf deinem Gerät aufzeichnet, vollständig auf dem Gerät und ohne Internet.
- **[COPG-VD](https://github.com/VD171/COPG-VD)**: ein Geräte-Spoofer, der aus einem frischen Fingerprint ein kohärentes, konsistentes Profil macht.
- **[VD-dropbear](https://github.com/VD171/VD-dropbear)**: ein eigenständiger, konfigurierbarer gerooteter SSH-Daemon für KernelSU/APatch/Magisk.
- **[VDBackup](https://github.com/VD171/VD-Backup)**: vollständiges Sichern und Wiederherstellen von Apps und Daten als root, komplett über eine WebUI gesteuert.
- **[VDInstaller](https://github.com/VD171/VD-Installer)**: ein reibungsloser Root-Sideload-Installer für einzelne, Batch- und Split-APKs, mit einem Play-Protect-Verifier-Schalter und Fälschung der Installationsquelle.

## Kontakte

- https://vd171.ru
- https://vd.priv8.ru
- **Telegram:** @VD_Priv8 https://t.me/VD_Priv8
- **Channel:** @Priv8_VD https://t.me/Priv8_VD
- **Discord:** @VD.Priv8 https://discord.com/users/1296831918989639721
- **E-mail:** vd.priv8@pm.me
- **XDA-Developers:** @VD171 https://xdaforums.com/m/vd171.4699873/
- **GitHub:** @VD171 https://github.com/VD171

## Lizenz

Der eigene Code von VDLiveUpdate steht unter **Apache-2.0**; siehe [LICENSE](LICENSE). Er bettet einen kleinen
`ed25519-mini`-Verifier und ein statisches `curl` für den Fetch-Bootstrap ein, jeweils unter eigener Lizenz; siehe
[NOTICE.md](NOTICE.md) und die `PROVENANCE.json`-Dateien neben den mitgelieferten Binaries.

## Markenzeichen

VDLiveUpdate ist ein unabhängiges, inoffizielles Projekt, das mit keinem Dritten verbunden oder von ihm unterstützt ist.
"Android" ist eine Marke von Google LLC; "KernelSU", "Magisk" und "APatch" sind die Marken ihrer
jeweiligen Autoren. VDLU läuft vollständig auf deinem Gerät und auf deinem eigenen Release-Host.

## Tags

`VDLU` `flashless-update` `incremental-update` `KernelSU` `Magisk` `APatch` `module-update` `ed25519` `content-addressed` `OTA` `self-update` `Android` `VDLiveUpdate`

---

📣 **Join the channel for updates:** @Priv8_VD https://t.me/Priv8_VD
