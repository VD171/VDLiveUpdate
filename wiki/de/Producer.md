# Producer

Der **Producer** ist die PC- / Release-Seite von VDLU: der kleine Satz an Werkzeugen, die einen fertigen Modulbaum in einen signierten, inhaltsadressierten Feed verwandeln, von dem das Gerät aktualisieren kann. Nichts hiervon läuft auf dem Telefon. Diese Werkzeuge laufen auf deiner Release-Maschine (oder, für die Teile, bei denen es sicher ist, in CI).

Es gibt vier davon:

| Werkzeug | Läuft auf | Sprache | Aufgabe |
|---|---|---|---|
| `vdlu-pack` | PC / CI | python3 | Den finalen Modulbaum in `manifest.json` + `blobs/<sha256>` durchgehen |
| `vdlu-keygen` | PC | sh + openssl | Ein ed25519-Signaturschlüsselpaar erzeugen |
| `vdlu-sign` | PC | sh + openssl | `key_id` + Signatur in ein Manifest einfügen, an Ort und Stelle |
| `vdlu-gc` | PC | python3 | Waisen-Blobs aus einem veröffentlichten Feed entfernen (ausfallsicher) |

Der Release-Ablauf besteht aus drei Schritten, einmal pro Release durchgeführt: **packen, dann signieren, dann veröffentlichen**. `vdlu-keygen` ist eine einmalige Einrichtung, und `vdlu-gc` ist Pflege, die du ausführst, wenn der Feed wächst. Alles, was der Producer ausgibt, entspricht dem [[Feed Format]], das die Engine auf dem Gerät konsumiert.

---

## vdlu-pack

`vdlu-pack` nimmt den **exakten Baum, den dein `.zip` ausliefert** (den finalen Baum, nachdem dein Build seine eigene Whitelist und ABI-Beschneidung angewendet hat) und erzeugt den Feed dafür.

```sh
vdlu-pack <module_tree_dir> <out_dir> <module_id> <version> \
          [--version-name v106] [--channel stable] [--prev ./prev/manifest.json]
```

Es schreibt zwei Dinge in `<out_dir>`:

- `manifest.json` - die vollständige Beschreibung des Zielbaums (jede Datei mit ihrem `sha256`, `size`, `mode`, ihrer Kodierung und Reboot-Klasse), noch **unsigniert** (die Felder `key_id` und `sig` sind leere Platzhalter).
- `blobs/<sha256>` (oder `blobs/<sha256>.gz`) - ein Blob pro unterschiedlichem Dateiinhalt.

### Inhaltsadressiert und deduplizierend

Jeder Blob wird nach dem **sha256 seines originalen (unkomprimierten) Inhalts** benannt. Weil der Name der Hash ist, landet identischer Inhalt auf demselben Blob. `vdlu-pack` schreibt einen Blob nur, wenn er nicht bereits vorhanden ist, also:

- Eine Datei, die sich nicht geändert hat, behält denselben Blob-Namen und wird nie neu geschrieben oder neu gepusht.
- Zwei verschiedene Dateien mit identischem Inhalt teilen sich einen Blob.
- Eine zurückgesetzte Datei nutzt den Blob wieder, der von zuvor bereits da war.

Die Veröffentlichung ist daher **inkrementell durch Konstruktion**: über Releases hinweg wächst `blobs/` nur, und nur wirklich neuer Inhalt wird hinzugefügt. Das Gerät lädt nach denselben Hashes, sodass es nur die Blobs lädt, die es nicht bereits hält.

### Kompression (das `enc`-Feld)

Für jede Datei entscheidet `vdlu-pack`, wie der Blob gespeichert wird:

- `gz`, wenn die Datei mindestens 4096 Byte groß ist **und** gzip (deterministisch `-9 -n`) mindestens 10 Prozent spart.
- `raw` sonst (kleine Dateien, die On-the-wire-gzip ohnehin abdeckt, oder bereits inkompressible Daten).
- Fehlt `gzip` auf dem Build-Host, wird alles `raw` gespeichert. Das Packen schlägt hieran nie fehl.

Der `sha256` im Manifest ist **immer** vom originalen Inhalt; `enc` benennt nur, wie der Blob zufällig gespeichert ist. Das Gerät dekomprimiert `gz`-Blobs mit toybox `gunzip` und prüft dann den Hash gegen das Original.

### Reboot-Klasse und Sicherheit

`vdlu-pack` taggt jede Datei zudem mit einer Reboot-`class` (`live`, `soft`, `reboot`), abgeleitet aus ihrem Pfad, sodass die Engine weiß, was ohne Neustart angewendet werden kann und was inszeniert werden muss. Die Regeln und was das Gerät mit jeder Klasse tut, sind in [[Reboot Handling]] behandelt.

Ein paar Dinge, die `vdlu-pack` bewusst **nicht** tut:

- Es folgt keinen Symlinks (es überspringt sie mit einer Warnung, sodass Inhalt von außerhalb des Baums, wie ein Link zu einer Systemdatei, nie in einen Blob gelangen kann).
- Es überspringt nicht-reguläre Dateien (Verzeichnisse, FIFOs, Geräte).
- Es respektiert `SOURCE_DATE_EPOCH` für den `built`-Zeitstempel, sodass Manifeste reproduzierbar sind.
- Es schließt einen festen Satz von Pfaden vollständig aus dem Feed aus (die Vertrauenswurzel, Installer-Gerüstbau und ein paar andere). Die vollständige Liste, und warum jeder ausgeschlossen ist, steht in [[Feed Format]].

### Die `delete[]`-Liste

Übergib `--prev <previous manifest.json>` und `vdlu-pack` berechnet `delete[]`: die Pfade, die im vorherigen Release existierten, aber in diesem fort sind, sodass das Gerät sie entfernt, statt Waisen zurückzulassen. Ausgeschlossene Pfade werden nie als Löschungen ausgegeben, selbst wenn sie im vorherigen Manifest erscheinen (siehe [[Feed Format]] für die genaue Semantik).

---

## vdlu-keygen

Ein einmaliger Schritt. `vdlu-keygen` erzeugt das ed25519-Signaturschlüsselpaar für deinen Feed.

```sh
vdlu-keygen <id> <out_dir>
```

Es schreibt drei Dateien:

| Datei | Was es ist | Wohin es geht |
|---|---|---|
| `<id>.pem` | Der **private** Signaturschlüssel (Modus `0600`) | Bleibt auf deiner Release-Maschine. Niemals. |
| `<id>.pub` | Der öffentliche Schlüssel als PEM | Nur PC-seitiges Tooling |
| `<id>.pub.raw` | Der öffentliche Schlüssel als **rohe 32 Byte** | Als geräteseitiger Keyring-Eintrag des Moduls ausgeliefert |

Der rohe 32-Byte-öffentliche-Schlüssel ist das, was der Geräteverifizierer liest (er trägt kein `openssl`, kann also die PEM nicht lesen). Du bettest `<id>.pub.raw` in das Modul als `vdlu/keyring/<id>.pub` ein. Die PEM ist nur für den PC-seitigen Gebrauch. Diese Trennung, und wie die Schlüsselrotation funktioniert, wird in [[Security and Trust Model]] erklärt.

> Die private `.pem` ist das eine Geheimnis im gesamten System. Halte sie von jedem Gerät fern und aus jedem Repository-Push heraus. Siehe den CI-Hinweis unten.

---

## vdlu-sign

`vdlu-sign` nimmt das unsignierte Manifest, das `vdlu-pack` erzeugt hat, und signiert es **an Ort und Stelle**.

```sh
vdlu-sign <manifest.json> <privkey.pem> <key_id>
```

Es setzt das `key_id`-Feld, berechnet die kanonische Form des Manifests und schreibt die ed25519-Signatur (base64) in das `sig`-Feld. Die Signatur erfolgt über eine präzise Byte-Transformation des Manifests, sodass PC und Gerät genau dieselben signierten Bytes ableiten, ohne JSON-Bibliothek auf dem Gerät. Diese Transformation (die **Kanonisierung**) ist die wichtigste Invariante im Format, und sie ist vollständig in [[Feed Format]] dokumentiert.

Der private Schlüssel wird nur hier gelesen, auf deiner Maschine, und verlässt sie nie.

### Der Signaturschlüssel bleibt fern von CI

Dies ist ein bewusster Designpunkt. CI kann `vdlu-pack` ausführen und eine vollkommen gültige **schlüssellose Baseline** erzeugen (ein unsigniertes Seed-Manifest; siehe [[Feed Format]]), sodass eine frische Installation aktuell geboren wird, ohne dass CI je einen privaten Schlüssel berührt. Das eigentliche Signieren des veröffentlichten Feeds wird von dir, lokal, mit `vdlu-sign` durchgeführt. So ist der Signaturschlüssel zu 100 Prozent aus CI heraus, und nur der Feed, den du von Hand veröffentlichst, ist signiert.

---

## vdlu-gc

Weil Blobs inhaltsadressiert und unveränderlich sind, wächst `blobs/` nur je: `vdlu-pack` fügt hinzu, es entfernt nie. Über viele Releases hinweg sammelt der Feed (und die Pages-Site, die ihn hostet) Blobs an, die kein aktuelles Manifest mehr referenziert. `vdlu-gc` entfernt diese Waisen.

```sh
vdlu-gc <feed_dir> [--keep-last N] [--keep extra.json ...] [--apply]
```

Es baut die **behaltene Menge** von Manifesten: das aktuelle `manifest.json`, plus die letzten `N` archivierten Manifeste nach Version (Standard `N=3`, was eine Rollback-Marge gibt), plus alle, die du mit `--keep` benennst. Ein Blob, der von **keinem** behaltenen Manifest referenziert wird, ist ein Waise und ein Kandidat für die Entfernung. Die behaltene Menge ist eine Vereinigung, sodass ein Blob bleibt, solange ein behaltenes Release ihn noch braucht; ein Gerät, das auf einer älteren behaltenen Version sitzt, verliert sein Fetch nie.

`vdlu-gc` ist auf Sicherheit gebaut:

- **Standardmäßig Trockenlauf.** Ohne `--apply` druckt es nur, was es entfernen *würde*. Du fügst `--apply` hinzu, um tatsächlich zu löschen.
- **Ausfallsicher.** Findet es überhaupt kein behaltenes Manifest, weigert es sich zu entfernen, statt zu riskieren, einen Feed zu leeren.
- **Aufbewahrung nach Referenz, nicht nach Datum.** Ein Blob wird behalten, weil ein behaltenes Manifest auf ihn zeigt, nie wegen eines Zeitstempels.

Nach dem Entfernen pushe den kleineren Feed zu deinem Host. Verteile das Schreiben, wenn dein Host gebündelte Schreibvorgänge rate-limitiert.

---

## Alles zusammengesetzt

Ein typisches Release, von Anfang bis Ende:

```sh
# einmalig: einen Signaturschluessel erstellen. Die .pem von jedem Geraet und jedem Repo-Push fernhalten.
vdlu-keygen release-2026 ./keys

# jedes Release: den finalen ausgelieferten Baum packen (post-whitelist, derselbe Baum, den das .zip ausliefert)
vdlu-pack ./module_tree ./out demo 106 --version-name v106 --channel stable \
          --prev ./prev/manifest.json

# das Manifest an Ort und Stelle signieren (lokal, privater Schluessel verlaesst nie deine Maschine)
vdlu-sign ./out/manifest.json ./keys/release-2026.pem release-2026

# veroeffentliche ./out/{manifest.json,blobs/} zu deiner Quelle (GitHub Pages, rsync, ...).
# gelegentlich: Waisen-Blobs entfernen
vdlu-gc ./feed --keep-last 3            # zuerst Trockenlauf
vdlu-gc ./feed --keep-last 3 --apply    # dann loeschen
```

Für das vollständige durchgearbeitete Beispiel der Übernahme von VDLU in ein Modul siehe [[Quick Start]]. Für die On-wire-Form all dessen, was der Producer ausgibt, siehe [[Feed Format]]. Für die Begründung hinter der Schlüsselbehandlung und was aus dem Feed herausgehalten wird, siehe [[Security and Trust Model]].
