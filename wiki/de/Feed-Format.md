# Feed Format

Der **Feed** ist das, was VDLU über die Leitung serviert und wovon das Gerät aktualisiert. Es ist ein schlichtes statisches Verzeichnis, servierbar von allem (GitHub Pages, ein rsync-Ziel, ein `file://`-Pfad):

```
<source>/
  manifest.json          # the signed description of the current release
  blobs/<sha256>         # one blob per distinct file content
  blobs/<sha256>.gz      # (when the blob is stored gzipped)
```

Das Modul selbst liefert zudem eine zusätzliche Datei, `baseline.json`, innerhalb des `.zip` aus (nicht aus dem Feed serviert). Der Producer, der all dies baut, ist in [[Producer]] beschrieben; diese Seite ist der On-wire-Vertrag.

---

## manifest.json

Das Manifest ist die vollständige Beschreibung eines Release: jede Datei im Zielbaum, was zu löschen ist, und die Signatur über das Ganze.

```json
{
  "schema": 1,
  "module": "demo",
  "version": 106,
  "version_name": "v106",
  "built": "2026-11-19T12:00:00Z",
  "engine_min": 3,
  "channel": "stable",
  "key_id": "release-2026",
  "files": [
    {
      "path": "webroot/index.html",
      "sha256": "<hex64>",
      "size": 1234,
      "mode": "0644",
      "enc": "raw",
      "class": "live"
    }
  ],
  "delete": ["webroot/old.html"],
  "sig": "<base64>"
}
```

### Felder

| Feld | Bedeutung |
|---|---|
| `schema` | Formatversion des Manifests selbst (derzeit `1`). |
| `module` | Die Modul-Id. Das Gerät lehnt das Manifest ab, wenn es nicht zu seiner eigenen Modul-Id passt, sodass ein gültig signierter Feed für ein anderes Modul nicht an seiner Stelle serviert werden kann. |
| `version` | Ganzzahlige Version. Die Engine aktualisiert nur vorwärts; ein Feed älter als das Gerät ist ein harmloser "ahead"-Zustand, kein Fehler. |
| `version_name` | Menschenlesbarer Versions-String (zum Beispiel `v106`). |
| `built` | ISO-8601-Build-Zeitstempel. Respektiert `SOURCE_DATE_EPOCH` für Reproduzierbarkeit. |
| `engine_min` | Die minimale Engine-Version, die erforderlich ist, um dieses Manifest anzuwenden. |
| `channel` | Release-Kanal (zum Beispiel `stable`). |
| `key_id` | Welcher Schlüssel im Geräte-Keyring dieses Manifest signierte. Wählt den öffentlichen Schlüssel für die Prüfung aus, und muss in der Modul-Update-Allowlist der Engine stehen (siehe [[Security and Trust Model]]); ein Schlüssel, der lediglich im Keyring vorhanden, aber nicht in der Allowlist ist, wird abgelehnt, bevor sein Pubkey geladen wird. |
| `files[]` | Der **vollständige** Zielbaum (kein Diff). Jeder Eintrag: `path`, `sha256`, `size`, `mode`, `enc` (`raw`/`gz`), `class` (`live`/`soft`/`reboot`). |
| `delete[]` | Pfade, die im vorherigen Release vorhanden waren, aber jetzt fort sind, damit das Gerät sie entfernt. |
| `sig` | Die ed25519-Signatur, base64. Siehe die Kanonisierung unten. |

`files[]` beschreibt den **gesamten** Baum, kein Delta. Das Gerät berechnet das Delta selbst, indem es das Manifest mit dem vergleicht, was es bereits hat, und lädt nur die Blobs, deren `sha256` ihm fehlt. Der `sha256` ist immer vom originalen (unkomprimierten) Inhalt; `enc` sagt nur, wie dieser Blob in `blobs/` gespeichert ist. Die Bedeutung von `class` und was das Gerät mit jedem Wert tut, ist in [[Reboot Handling]] behandelt.

---

## Kanonisierung (die signierten Bytes)

Dies ist die wichtigste Invariante im Format. Der PC-Signierer und der geräteseitige Verifizierer laufen auf völlig verschiedenen Laufzeitumgebungen (openssl auf dem PC, toybox + ein winziger eingebetteter Verifizierer auf dem Gerät, und **überhaupt keine JSON-Bibliothek** auf dem Gerät). Sie müssen dennoch die exakt selben Bytes ableiten, um zu signieren und zu verifizieren. Die Regel ist daher eine bewusste **Byte-Transformation**, keine JSON-Neuserialisierung.

**Schritt 1: eine feste Speicherform.** `vdlu-pack` schreibt `manifest.json` kompakt, mit sortierten Schlüsseln, UTF-8, immer `key_id` und `sig` enthaltend (als leere Strings, bis signiert):

```
json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
```

**Schritt 2: nur `sig` entfernen.** Die kanonische Form ist dieser exakte Text mit **nur dem entfernten `"sig"`-Feld**. Weil die Schlüssel sortiert sind, erscheint `sig` immer als `,"sig":"<value>",`, eingeklammert von `"schema"` davor und `"version"` danach (beide immer vorhanden), sodass das Entfernen wohlgeformten Text hinterlässt. JSON escaped jedes `"` innerhalb eines String-Werts als `\"`, sodass der strukturelle Token `"sig":"` eindeutig ist, selbst gegenüber einem Dateinamen, der wörtlich `"sig":"` enthält.

Das Entfernen ist eine Handvoll POSIX-Parameter-Expansionen, identisch im Signierer und im Verifizierer, ohne `sed` und ohne `jq`:

```sh
# $1 = the full manifest text
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

**Schritt 3: den Hash davon signieren.** Die signierte/verifizierte Nachricht ist das **sha256-Hex** (64 ASCII-Zeichen, kein Zeilenumbruch) der kanonischen Form. ed25519 signiert dieses Hex.

Zwei Konsequenzen ergeben sich hieraus durch Konstruktion:

- `key_id` ist Teil der kanonischen Form (nur `sig` wird entfernt). `vdlu-sign` setzt `key_id` **vor** dem Hashen, sodass die Schlüsselidentität von der Signatur abgedeckt ist.
- Ob der `sig`-Platzhalter leer ist (`"sig":""`, zur Sign-Zeit) oder gefüllt (zur Verify-Zeit), das Entfernen ergibt die identischen kanonischen Bytes. Signieren und Verifizieren stimmen automatisch überein.

Die zwei POSIX-sh-Werkzeuge sind maßgeblich. Ein Python-Äquivalent, `re.sub(r'"sig":"[^"]*",', '', text, count=1)` dann sha256, existiert nur, um sie gegenzuprüfen.

Die Vertrauensbegründung rund um all dies (warum die Prüfung geräteseitig ist, wie `hardened` fail-closed fällt) lebt in [[Security and Trust Model]].

---

## baseline.json (der Install-Seed)

Wenn ein Modul frisch installiert wird, sollte es für seine eigene ausgelieferte Version bereits "aktuell" sein, ohne unnötige Selbstaktualisierung der gerade installierten Version. Das ist, was `baseline.json` tut.

`baseline.json` wird **innerhalb des Modul-Zips** ausgeliefert (unter `vdlu/baseline.json`), nicht auf dem Feed. Bei einer frischen Installation seedet die Engine ihren "aktive Version"-Datensatz daraus, sodass das Gerät aktuell geboren wird, ohne `from:0` und ohne erneutes Laden von dem, was es bereits hat.

Schlüsseleigenschaften:

- Es ist eine **schlüssellose Kopie des signierten Manifests** für die ausgelieferte Version: dieselbe `vdlu-pack`-Ausgabe, unsigniert gelassen (`key_id` und `sig` bleiben leer).
- Es ist **nicht verifiziert**. Die Engine behandelt es als lokalen vertrauenswürdigen Seed, weil es innerhalb des geflashten Zips ankam, was die Install-Vertrauensgrenze ist. Nur ein *vom Feed geladenes* Manifest durchläuft die Signaturprüfung.
- Weil es keine Signatur braucht, **kann CI es schlüssellos erzeugen**, was den Signaturschlüssel vollständig aus CI hält (siehe [[Producer]]).
- `vdlu-pack` **schließt `baseline.json` aus seinem eigenen Manifest aus**, sodass das Manifest nie die Baseline referenziert (das wäre eine Selbstreferenzschleife: Manifest zu Baseline zu Manifest).
- Es ist **nicht fatal, wenn abwesend**. Ohne es startet das Gerät bei seinem ersten Update einfach von `from:0` und lädt, was es braucht. Nie kaputt, nur weniger optimal.

---

## Blobs

Jeder unterschiedliche Dateiinhalt ist ein Blob unter `blobs/`, benannt nach dem **sha256 des originalen Inhalts**:

- `blobs/<sha256>` für einen Roh-Blob.
- `blobs/<sha256>.gz` für einen gezippten Blob (gzip wird nur behalten, wenn die Datei mindestens 4096 Byte groß ist und die Kompression mindestens 10 Prozent spart).

Ein Blob wird einmal gespeichert, in einem Format. Die Inhaltsadressierung gibt Deduplizierung gratis: unveränderter, gemeinsam genutzter oder zurückgesetzter Inhalt mappt auf einen Blob, der bereits existiert, sodass der Feed nur durch wirklich neuen Inhalt wächst und das Gerät nur die Hashes lädt, die ihm fehlen. Das Gerät prüft den `sha256` jedes heruntergeladenen Blobs gegen das Manifest (nach dem Dekomprimieren eines `gz`-Blobs), bevor es ihn verwendet.

---

## Was aus dem Feed ausgeschlossen ist, und warum

Der Feed trägt **nur den eigenen Inhalt des Moduls**. Ein fester Satz von Pfaden wird absichtlich herausgehalten. `vdlu-pack` wendet ein Ausschlussprädikat sowohl beim Durchgehen des Baums als auch beim Berechnen von `delete[]` an.

| Ausgeschlossen | Warum |
|---|---|
| `vdlu/keyring/`, `vdlu/verify/` (die Vertrauenswurzel: rohe öffentliche Schlüssel + das Verifizierer-Binary) | **Dies ist der zentrale Sicherheitsgrund.** Der Vertrauensanker ist **flash-only**. Wären der Keyring oder Verifizierer feed-lieferbar, könnte ein Manifest genau das Ding überschreiben, das es validiert. Sie von der Leitung fernzuhalten bedeutet, dass ein Manifest nie den geräteseitigen Vertrauensanker neu schreiben kann. |
| `vdlu/baseline.json` | Es ist eine Kopie des signierten Manifests (der Install-Seed); es zu packen wäre eine Selbstreferenzschleife. |
| `.vd/` Flash-Infrastruktur | Flash-Gate-Gerüstbau, der im Zip ausgeliefert wird, nie live angewendet. |
| `update.json`, `update-mmrl.json` | Ihre Größe/sha werden von CI *nachdem* die Zips gebaut sind eingefüllt, sodass die ausgelieferte Kopie von jeder Feed-Kopie abweicht. Sie zu feeden würde ein Phantom-Einzeldatei-Fetch bei jeder Erst-Selbstaktualisierung einer Installation verursachen, und sie sind geräteseitig ohnehin vestigial (der Manager liest das Remote-Roh-Update-JSON). |
| `META-INF/`, `customize.sh` (Installer-Gerüstbau) | Vom Manager zur **Flash**-Zeit konsumiert und nicht im installierten Modul behalten. Sie sind kein VDLU-Inhalt; sie zu servieren verschwendet Blobs und, wenn eine je zwischen Versionen geändert würde, würde sie als Installer-Datei in das Live-Modulverzeichnis geschrieben. |
| Per-Datei-`.sha256`-Begleiter | Sie gehören nur zum flashbaren Zip, werden nach einem inkrementellen Update veraltet und würden das Manifest verdoppeln. |
| Dev-/Doc-Dateien (`RELEASE.md`, `CLAUDE.md`, `.gitignore`) | Nie an das Gerät ausgeliefert; sie zu servieren verschwendet Blobs und wühlt das signierte Manifest bei jeder Doc-Bearbeitung auf. |

Die Begründung hinter dem Vertrauenswurzel-Ausschluss ist in [[Security and Trust Model]] erweitert.

---

## delete[]-Semantik

`delete[]` sagt dem Gerät, welche Pfade zu entfernen sind, sodass eine zwischen Releases fallengelassene Datei nicht geräteseitig als Waise verweilt. Es wird berechnet, indem `--prev <previous manifest.json>` an `vdlu-pack` übergeben wird: ein Pfad, der im vorherigen Release war und nicht im aktuellen ist, wird zu einem Delete-Eintrag.

Die wichtige Regel: **ausgeschlossene Pfade werden nie als Löschungen ausgegeben, selbst mit `--prev`.** Jeder vorherige Pfad wird durch dasselbe Ausschlussprädikat geführt, das beim Durchgehen des Baums verwendet wird. Wenn ein `--prev` auf ein älteres Manifest zeigt, das noch jetzt-ausgeschlossene Pfade auflistete (eine verirrte `baseline.json`, `META-INF/*`, ein Keyring-Eintrag usw.), werden diese Pfade **nicht** in Delete-Einträge verwandelt. Ein ausgeschlossener Pfad war nie Feed-Inhalt, also ist er nicht VDLUs zum Löschen, und dem Gerät wird nie befohlen, eine Datei zu entfernen, die nicht durch den Feed serviert wurde. Das ist, was die Ausschlussliste davon abhält, je als zerstörerische Anweisung zurückzuschlagen.
