# VDLiveUpdate (VDLU)

**VDLU ist eine flashlose, inkrementelle Selbstaktualisierungs-Engine für KernelSU- / APatch- / Magisk-Module: ein installiertes Modul aktualisiert seine eigenen Dateien über einen signierten Feed, lädt nur das Geänderte und wendet den größten Teil davon ohne Neustart an.**

Ein normales Modul-Update liefert das gesamte `.zip` erneut aus, sodass ein paar geänderte Zeilen einen kompletten erneuten Download kosten, und ein statisches Update-Manifest kann nur auf eine einzige `zipUrl` zeigen (eine Variante für jedes Gerät). VDLU geht einen anderen Weg: es vergleicht den tatsächlich installierten Baum mit einem signierten, inhaltsadressierten Feed, lädt nur die Deltas herunter und schreibt sie an Ort und Stelle. Eine arm64-Vollinstallation bleibt arm64-voll, eine Lite-Installation bleibt lite, und das Modul wird nie neu geflasht.

VDLU ist dazu gedacht, in ein Modul **vendored** (eingebettet) zu werden, abgelegt unter `<module>/vdlu/`. Es ist kein eigenständiges Modul.

## Ziele

- **Flashlose Selbstaktualisierung.** Aktualisiere ein installiertes Modul an Ort und Stelle, over the air, ohne Root-Manager, ohne erneutes Flashen des `.zip` und ohne Verlust der installierten Variante.
- **Inkrementell nach Inhalt.** Übertrage nur die Blobs, deren Inhalt sich geändert hat. Ein inhaltsadressierter Feed (`manifest.json` + `blobs/<sha256>`) bedeutet, dass unveränderte oder zurückgesetzte Dateien nie erneut geladen werden.
- **Neustartfrei, wo es sicher ist.** Gewöhnliche Dateien werden sofort live angewendet. Ein inszenierter Neustart ist nur den wenigen Dateien vorbehalten, die ihn wirklich brauchen (eine `.so`, ein `/system`-Overlay, eine `sepolicy.rule`).
- **Schlank auf dem Gerät.** Reines POSIX `sh`, kein `jq`, kein `bash`, kein `openssl` auf dem Gerät. Die Prüfung stützt sich auf ein eingebettetes `ed25519-mini`; das einzige heruntergeladene Binary ist ein statisches `curl`, das nur für `https`-Feeds verwendet wird.
- **Fail-closed und ehrlich.** Jedes Manifest-Feld wird als feindliche Eingabe behandelt und validiert, bevor irgendetwas heruntergeladen wird. Nichts wird jemals als "fertig" gemeldet, es sei denn, ein erneutes Hashen beweist es, und nichts wird überschrieben, ohne zuvor ein Backup anzulegen.

## Besonderheiten

Was VDLU von einem typischen OTA-Client unterscheidet:

- **Flashlos und inkrementell.** Inhaltsadressiertes Diff / Fetch / Apply mit Deduplizierung: das Gerät berechnet das Delta gegen den signierten Feed und zieht nur fehlende Blobs.
- **Neustartfrei, wo möglich.** Gewöhnliche Dateien werden live angewendet; nur `.so`, `/system`-Overlays und `sepolicy.rule`-Dateien werden inszeniert und bei einem einzigen Neustart getauscht. Siehe [[Reboot Handling]].
- **POSIX `sh` auf dem Gerät.** Läuft unter toybox / busybox / mksh. Kein `jq` (ein `gron`-artiger `awk`-Flattener parst JSON), keine `bash`-Spezialitäten, keine schwere Laufzeitumgebung.
- **Schlanke Prüfung.** Ein eingebettetes `ed25519-mini` verifiziert Signaturen. Es gibt **kein `openssl` auf dem Gerät**; der private Schlüssel berührt nie ein Gerät oder CI.
- **Fail-closed-Sicherheit.** `validate_plan()` verwirft das **gesamte** Manifest bei jedem fehlerhaften Feld (absoluter oder `..`-Pfad, ein `sha256`, der nicht aus 64 Hex-Zeichen besteht, ein ungültiger Modus / eine ungültige Klasse / eine ungültige Kodierung). Zwei Profile, `trusted` und `hardened`, wobei `hardened` durch Inversion fail-closed ist. Siehe [[Security and Trust Model]].
- **Wiederaufnehmbar und atomar.** Ein Journal macht jede Transaktion absturzsicher; Schreibvorgänge nutzen `rename` / `mv`; vor jedem Überschreiben wird ein Backup angelegt, sodass ein fehlgeschlagenes Apply zurückrollt, statt das Modul zu beschädigen.

## Hier starten

| Wenn du... möchtest | Gehe zu |
|---|---|
| VDLU Schritt für Schritt in dein Modul übernehmen | [[Quick Start]] |
| Das gesamte System auf einen Blick verstehen | [[Architecture]] |
| Die geräteseitige Engine (`update.sh`) kennenlernen | [[Engine]] |
| Einen Feed auf deinem PC bauen und signieren | [[Producer]] |
| Das Updates-Panel einbinden | [[WebUI]] |
| Das Vertrauensmodell und die Bedrohungslage lesen | [[Security and Trust Model]] |
| Das Manifest- und Blob-Layout sehen | [[Feed Format]] |
| Wissen, was einen Neustart auslöst und warum | [[Reboot Handling]] |
| Eine häufige Frage stellen | [[FAQ]] |
| Beitragen | [[Contributing]] |

## Projektlinks

- **Quellcode:** https://github.com/VD171/VDLiveUpdate
- **Kanal (Updates):** @Priv8_VD https://t.me/Priv8_VD

VDLiveUpdate ist ein unabhängiges, inoffizielles Projekt. "Android" ist eine Marke von Google LLC; "KernelSU", "Magisk" und "APatch" sind die Marken ihrer jeweiligen Autoren. VDLU läuft vollständig auf deinem Gerät und deinem eigenen Release-Host.
