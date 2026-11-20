# Architecture

VDLU hat zwei Seiten, die durch eine Sache in der Mitte verbunden sind. Auf dem PC verwandelt der [[Producer]] einen Modulbaum in einen signierten, inhaltsadressierten Feed. Auf dem Gerät liest die [[Engine]] diesen Feed, ermittelt, was sich geändert hat, und wendet es an. Die Naht zwischen beiden ist das **signierte Manifest plus der Blob-Speicher** (das [[Feed Format]]). Nichts sonst überquert die Lücke.

```
        PC / release host                                device
  +--------------------------+                 +---------------------------+
  |  Producer                |                 |  Engine  (update.sh)      |
  |  vdlu-pack  -> manifest  |    signed       |  POSIX sh, no jq          |
  |  vdlu-sign  -> sig       |    feed         |  DIFF FETCH APPLY COMMIT  |
  |  vdlu-gc    -> prune     | =============>  |  journal + rollback       |
  +--------------------------+   manifest.json |  ed25519-mini verify      |
                                 blobs/<sha>   +-------------+-------------+
                                                             |
                                                       +-----v------+
                                                       |  WebUI     |
                                                       |  Updates   |
                                                       |  panel     |
                                                       +------------+
```

Die beiden Seiten teilen sich nie eine Laufzeitumgebung. Der Producer nutzt `python3` und `openssl`; die Engine ist reines POSIX `sh` mit toybox und einem eingebetteten `ed25519-mini`. Sie stimmen nur überein, weil beide **dieselben kanonischen Bytes** aus einem Manifest ableiten (siehe [[Security and Trust Model]]). Die WebUI ist ein dünnes Vanilla-JS-Panel, das die Engine über die Root-Manager-Brücke antreibt und ihr Fortschritts-Journal liest; sie enthält keine eigene Update-Logik. Siehe [[WebUI]].

## Die zwei Seiten

| Seite | Läuft auf | Gebaut aus | Aufgabe |
|---|---|---|---|
| [[Producer]] | PC / CI | `python3` + `sh` + `openssl` | Den Modulbaum in `manifest.json` + `blobs/` durchgehen, signieren, Waisen entfernen |
| [[Engine]] | Gerät | POSIX `sh` + toybox + `ed25519-mini` | Den installierten Baum gegen den Feed vergleichen, Deltas laden, anwenden, committen |
| [[WebUI]] | Gerät (Webview) | Vanilla JS/CSS | Updates auslösen, Fortschritt zeigen, Konfig bearbeiten, das Neustart-Banner zeigen |

## Die Update-Pipeline

Jedes Update ist eine Transaktion, ausgeführt in fester Reihenfolge:

```
  DIFF  ------>  FETCH  ------>  APPLY  ------>  COMMIT
  read feed      download        write live     re-hash all,
  + validate     only missing    files now,      promote target
  + plan         blobs, verify   stage reboot     -> current,
  (no changes)   each sha256     ones             DONE or
                                                  PENDING_REBOOT
```

- **DIFF** (`update.sh check` ist diese Phase, schreibgeschützt). Die Engine lädt nur das Manifest, führt `validate_plan()` über jedes Feld aus, **bevor** sie irgendetwas anfasst, und vergleicht dann den Feed mit `current.json`, um einen Plan pro Datei zu erstellen. Sie ändert nichts auf der Platte. Ein Gerät, das dem Feed voraus ist, ist ein harmloses "ahead"-Ergebnis, kein Fehler.
- **FETCH.** Lädt nur die Blobs herunter, die dem Plan fehlen, nach `<sha>.part`, dekomprimiert `gz`, prüft `sha256sum` gegen das Manifest und verschiebt (`mv`) jeden verifizierten Blob atomar in den Cache. Ein bereits zwischengespeicherter Blob (oder einer, der aus einer unveränderten lokalen Datei geseedet wurde) wird übersprungen, sodass ein Zurücksetzen oder eine gemeinsam genutzte Datei nichts kostet. Drei Fehlschläge bei einem Blob brechen die Phase ab, ohne etwas anzuwenden. Ein durch die Netzwerkrichtlinie blockierter Download endet als `DEFERRED` (wiederaufnehmbar), nicht als Fehler.
- **APPLY.** Gewöhnliche (`live` / `soft`) Dateien werden jetzt geschrieben: Backup nach `rollback/<v>/`, eine `.vdlu-tmp` schreiben, `chmod`, verifizieren, dann atomares `rename` über das Ziel. Dateien der Reboot-Klasse werden in `staged/<path>.vdlu-new` materialisiert und der Live-Inode bleibt unberührt. Ein `delete[]`-Eintrag wird gesichert und dann entfernt. Jeder Schritt ist idempotent: eine Datei, die bereits den Ziel-Hash hat, wird übersprungen.
- **COMMIT.** Hasht jede Live-Datei erneut; nur wenn alles übereinstimmt, befördert die Engine `target.json` zu `current.json`. Wurde etwas inszeniert, endet die Transaktion in `PENDING_REBOOT`; andernfalls in `DONE`.

## Inhaltsadressiertes Manifest und Blobs

Der Feed ist inhaltsadressiert: das Manifest listet den **vollständigen** Zielbaum auf, jede Datei getragen von ihrem `sha256`, und der Blob-Speicher hält eine Kopie jedes unterschiedlichen Inhalts unter `blobs/<sha256>` (oder `blobs/<sha256>.gz`).

- **Deduplizierung.** Identischer Inhalt irgendwo im Baum, oder über Releases hinweg, ist ein Blob. Die Veröffentlichung ist inkrementell: ein Blob, dessen `sha256` bereits auf dem Host existiert, wird nie erneut gepusht, und das Gerät lädt nie Inhalte erneut, die es bereits hat.
- **sha256 ist vom Original.** Der Hash benennt immer den unkomprimierten Inhalt; `enc` (`raw` oder `gz`) vermerkt nur, wie dieser eine Blob zufällig gespeichert ist. Das Gerät dekomprimiert `gz` mit toybox `gunzip`, sodass kein zusätzlicher Kompressor mitgeliefert wird.
- **Varianten-stabil.** Weil das Gerät gegen das vergleicht, was tatsächlich installiert ist, kann der Feed eine ganze Modulfamilie tragen; jede Installation zieht nur die Blobs, die ihre eigene Variante vervollständigen.

Das vollständige Layout Feld für Feld steht in [[Feed Format]].

## Das wiederaufnehmbare Journal

Jede Transaktion ist absturzsicher, weil ihr Fortschritt in einem Journal (`journal.json`) lebt, und das fixierte Ziel der laufenden Transaktion in `target.json` lebt. Der Zustandsautomat läuft in fester Reihenfolge:

```
PLANNED -> FETCHING -> FETCHED -> APPLYING -> APPLIED_LIVE -> ( PENDING_REBOOT | DONE )
                                                               \-> ERROR / DEFERRED
```

| Zustand | Bedeutung |
|---|---|
| `PLANNED` | Plan erstellt, noch nichts geladen |
| `FETCHING` / `FETCHED` | Blobs werden geladen / alle Blobs vorhanden und verifiziert |
| `APPLYING` / `APPLIED_LIVE` | Dateien werden geschrieben / alle Live-Dateien geschrieben |
| `PENDING_REBOOT` | Eine Datei der Reboot-Klasse ist inszeniert, wartet auf den Boot-Tausch |
| `DONE` | Erneutes Hashen von allem stimmte überein; `current.json` befördert |
| `ERROR` | Harter Fehler; Modul unbeschädigt gelassen, Live-Dateien aus `rollback/` zurückgesetzt |
| `DEFERRED` | Download durch die Netzwerkrichtlinie zurückgehalten; Plan bleibt bestehen, wird später fortgesetzt |

`DONE` wird **erst** erreicht, sobald ein erneutes Hashen von allem übereinstimmt, sodass das Journal nie behauptet, ein halb angewendetes Update sei vollständig. Ein Absturz, ein abgebrochenes Netzwerk oder ein Neustart auf halbem Weg hinterlässt ein wiederaufnehmbares Journal; `update.sh resume` (oder `boot`) setzt bei der aktuellen Phase an. Siehe [[Engine]] für den Befehlssatz und die geräteseitigen Zustandsdateien.

## Atomizität und Rollback

Nichts wird jemals an Ort und Stelle überschrieben und nichts geht verloren:

- **Atomare Schreibvorgänge.** Jede Datei landet über eine temporäre Datei (`.vdlu-tmp`) und ein atomares `rename` / `mv`, sodass ein Leser nie eine halb geschriebene Datei sieht.
- **Backup vor dem Überschreiben.** Der vorherige Inhalt wandert nach `rollback/<version>/<path>`, bevor die neue Datei darüber umbenannt wird (die letzten paar Versionen werden aufbewahrt). Schlägt ein Apply fehl, werden die Live-Dateien aus der Rollback-Kopie zurückgesetzt, statt beschädigt zurückzubleiben. Ein fehlgeschlagenes Backup **bricht** das Apply ab, statt ohne Sicherheitsnetz zu überschreiben.
- **Serialisiert.** Ein `mkdir`-basierter Lock (`lock.d/`, da `flock` auf toybox nicht funktioniert, mit Stale-Recovery per PID) serialisiert gleichzeitige Läufe.

## Das neustartfreie Prinzip

Die meisten Dateien können getauscht werden, während das Modul live ist, sodass VDLU sie sofort anwendet. Nur drei Klassen brauchen einen Neustart, weil ein laufender Prozess sie bereits gemappt hat: eine `.so` (von Zygisk geladen), ein `/system`-Overlay und eine `sepolicy.rule`. Diese werden **inszeniert, nie über einen Live-Inode geschrieben** und in einem Pre-Zygote-Schritt beim nächsten Boot eingetauscht. Die vollständige Taxonomie und der Boot-Ablauf stehen in [[Reboot Handling]].

## Die Fail-closed-Vertrauenshaltung

Der Feed ist das Einzige, das vom PC zum Gerät übergeht, daher behandelt die Engine jedes seiner Bytes als feindlich. `validate_plan()` läuft in der DIFF-Phase, vor jedem Download, und verwirft das gesamte Manifest bei jedem fehlerhaften Feld. Die Signaturprüfung nutzt ein eingebettetes `ed25519-mini` (kein `openssl` auf dem Gerät), der private Schlüssel berührt nie ein Gerät oder CI, und das `hardened`-Profil ist durch Inversion fail-closed, sodass ein beschädigter Profilwert nie stillschweigend einen unsignierten Feed akzeptieren kann. Das vollständige Modell, die zwei Profile und die Bedrohungen, die jedes beantwortet, stehen in [[Security and Trust Model]].
