> **Languages:** [English](../PRODUCER.md) · [العربية](../ar/PRODUCER.md) · [Čeština](../cs/PRODUCER.md) · Deutsch · [Español](../es/PRODUCER.md) · [فارسی](../fa/PRODUCER.md) · [Français](../fr/PRODUCER.md) · [हिन्दी](../hi/PRODUCER.md) · [Bahasa Indonesia](../id/PRODUCER.md) · [Italiano](../it/PRODUCER.md) · [日本語](../ja/PRODUCER.md) · [한국어](../ko/PRODUCER.md) · [Nederlands](../nl/PRODUCER.md) · [Polski](../pl/PRODUCER.md) · [Português](../pt/PRODUCER.md) · [Русский](../ru/PRODUCER.md) · [Svenska](../sv/PRODUCER.md) · [ไทย](../th/PRODUCER.md) · [Türkçe](../tr/PRODUCER.md) · [Українська](../uk/PRODUCER.md) · [Tiếng Việt](../vi/PRODUCER.md) · [中文](../zh/PRODUCER.md)

---

# VDLU-Producer + Signierschicht

Baut die inhaltsadressierte Auslieferung (Manifest + Blobs) für ein Modul und signiert sie.
Richtet sich nach [`INTERFACES.md`](INTERFACES.md) §3/§6/§7.

| tool | läuft auf | Sprache | Aufgabe |
|---|---|---|---|
| `producer/vdlu-pack` | PC / CI | python3 | den finalen Modulbaum durchlaufen -> `manifest.json` + `blobs/` |
| `producer/vdlu-keygen` | PC | sh + openssl | ed25519-Schlüsselpaar (`<id>.pem` priv, `<id>.pub` PEM, `<id>.pub.raw` RAW 32B für das schlanke Keyring) |
| `producer/vdlu-sign` | PC | sh + openssl | `key_id` + `sig` in ein Manifest injizieren, an Ort und Stelle |
| `engine/vdlu-verify` | **Gerät** | sh + ed25519-mini | `sig` via das eingebettete ed25519-mini verifizieren; Keyring = RAW 32B Pubkey (KEIN openssl auf dem Gerät) |

## Pipeline

```sh
# 1. one-time: a signing key. Keep the .pem off every device and off any repo push.
producer/vdlu-keygen release-2026 ./keys

# 2. each release: pack the final tree (same tree the .zip ships, post-whitelist).
producer/vdlu-pack  ./module_tree  ./out  demo 106 --version-name v106 --channel stable \
                    [--prev ./prev/manifest.json]      # delete[] = paths gone since prev

# 3. sign the manifest in place.
producer/vdlu-sign  ./out/manifest.json  ./keys/release-2026.pem  release-2026

# 4. publish ./out/{manifest.json,blobs/} to <source> (Pages batch for public; rsync for private).
#    The slim device keyring holds ./keys/release-2026.pub.raw as keyring/release-2026.pub (RAW 32B).
```

`vdlu-pack` ist inhaltsadressiert und deduplizierend: ein Blob, dessen `<sha256>` bereits existiert, wird nicht
neu geschrieben, sodass die Veröffentlichung inkrementell ist und der unveränderte / zurückgesetzte Inhalt nie erneut gepusht wird.

### `enc`-Entscheidung (vdlu-pack)

`sha256` ist **immer** vom originalen (unkomprimierten) Inhalt, `enc` benennt nur, wie der Blob gespeichert wird.

- `gz`, wenn `size >= 4096` **und** gzip (`-9 -n`, deterministisch) mindestens 10% spart (`comp <= raw*0.90`).
- `raw` ansonsten (kleiner Text, den HTTP-gzip bereits abdeckt, oder bereits inkompressible Daten).
- gzip fehlt auf dem Build-Host -> alles `raw` (schlägt nie fehl).

Ein Blob wird einmal gespeichert, in einem Format: `blobs/<sha256>` (raw) oder `blobs/<sha256>.gz` (gz). Das Gerät
dekomprimiert mit toybox `gunzip` (immer vorhanden), sodass kein zstd gebundelt wird.

### `class`-Entscheidung (vdlu-pack) - Reboot-Taxonomie

Abgeleitet aus dem Pfad (INTERFACES §3, doc §4). Nur Standardwerte, eine Pfadregel stuft `reboot`->`live` nie herab.

| class | gematcht durch | angewandt |
|---|---|---|
| `reboot` | `system/**`, `zygisk/**/*.so`, `*.rule` | gestaget `.vdlu-new`, Swap beim Boot |
| `soft` | root `service.sh` / `post-fs-data.sh` / `boot-completed.sh` | live geschrieben, läuft nächsten Boot |
| `live` | alles andere (webroot, bin, lib, confs, module.prop, ...) | live geschrieben, atomar |

Symlinks werden **nicht gefolgt** (leakt nie Inhalt von außerhalb des Baums, z.B. ein Link auf
`/etc/shadow`) und werden mit einer Warnung übersprungen, da das Manifest-Schema keinen Symlink-Typ hat.
Nicht-reguläre Dateien (Verzeichnisse, FIFOs, Devices) werden übersprungen. `built` beachtet `SOURCE_DATE_EPOCH` für
reproduzierbare Manifeste.

### Baseline (der Installations-Seed) - unsigniert, schlüssellos

`baseline.json` (ausgeliefert unter `vdlu/baseline.json` im Modul-Zip) seedet `current.json` bei einer frischen Installation,
sodass das Gerät "current" geboren wird (kein from:0, kein Re-Fetch). Die Engine behandelt es als **lokalen vertrauenswürdigen Seed**
(es kam im geflashten Zip an, das die Installations-Vertrauensgrenze ist) und **verifiziert seine Signatur NICHT** -
nur das vom Feed GEHOLTE Manifest durchläuft `vdlu-verify`. Die Baseline braucht also **keinen Schlüssel**: sie ist
einfach `vdlu-pack`-Ausgabe über den ausgelieferten Baum (unsigniert, `sig`/`key_id` bleiben leer). Eine CI kann sie daher
**schlüssellos** erzeugen und hält den Signierschlüssel 100% aus der CI heraus - nur der veröffentlichte FEED wird signiert (Betreiber,
lokal). `vdlu-pack` schließt `baseline.json` aus seinem eigenen Manifest aus (Anti-Selbstreferenz). Nicht fatal, wenn
abwesend: das Gerät startet einfach from:0 beim ersten Update, nie kaputt.

## Kanonisierung (der Konvergenzpunkt)

`vdlu-sign` und `engine/vdlu-verify` müssen **dieselben Bytes** aus einem Manifest ableiten, auf zwei
verschiedenen Laufzeitumgebungen (PC openssl vs Gerät toybox). Die Regel ist bewusst eine Byte-
Transformation, keine JSON-Reserialisierung, sodass sie keine JSON-Bibliothek auf dem Gerät braucht:

1. `vdlu-pack` schreibt `manifest.json` **kompakt, Schlüssel sortiert, UTF-8**
   (`json.dumps(obj, sort_keys=True, separators=(",",":"), ensure_ascii=False)`), immer einschließlich
   der Felder `key_id` und `sig` (leere String-Platzhalter bis signiert). Dies ist die kanonische
   Speicherform.
2. **Kanonische Form = dieser Text mit entferntem `"sig"`-Feld.** Da die Schlüssel sortiert sind, erscheint `sig`
   immer als `,"sig":"<value>",`, eingeklammert von `"schema"` (davor) und `"version"` (danach),
   beide immer vorhanden. Das Entfernen hinterlässt wohlgeformtes `...,"schema":N,"version":...`.
   JSON escaped jedes `"` innerhalb von String-Werten zu `\"`, sodass das strukturelle Token `"sig":"`
   eindeutig ist, selbst gegenüber einem Dateinamen, der wörtlich `"sig":"` enthält (getestet).
3. Die signierte/verifizierte Nachricht ist der **sha256-Hex** (64 ASCII-Zeichen, kein Zeilenumbruch) der kanonischen
   Form. ed25519 über diesen Hex (`openssl pkeyutl -sign/-verify -rawin`).

Das Entfernen in POSIX sh (identische Funktion in beiden Tools, kein `sed`/`jq`):

```sh
# $1 = full manifest text (trailing newline already stripped by $(cat ...))
_pre=${_c%%\"sig\":\"*}     # up to  ...,"schema":N,
_rest=${_c#*\"sig\":\"}      # after "sig":"
_tail=${_rest#*\",}          # after <value>",  ->  "version":...
printf '%s%s' "$_pre" "$_tail" | sha256sum | cut -d' ' -f1
```

`key_id` ist Teil der kanonischen Form (nur `sig` wird entfernt), `vdlu-sign` setzt `key_id` **vor**
dem Hashen. Der Wert-Platzhalter, ob leer (`"sig":""`, Signierzeit) oder gefüllt (Verifizierzeit), ergibt die
identischen kanonischen Bytes, sodass Signieren und Verifizieren per Konstruktion übereinstimmen.

Python reproduziert es als `re.sub(r'"sig":"[^"]*",', '', text.rstrip("\\n"), count=1)` dann sha256 - verwendet
nur zur Gegenprüfung, die maßgeblichen Produzenten sind die beiden sh-Tools.

## Signatur (ed25519)

- `vdlu-keygen` (PC): `openssl genpkey -algorithm ed25519` (priv `0600`) + `openssl pkey -pubout` (pub **PEM**,
  zum Signieren/openssl) + `openssl pkey -pubout -outform DER | tail -c 32` -> **`.pub.raw` (RAW 32B)** (das ed25519
  SPKI DER ist ein 12-Byte-Präfix + der 32-Byte-Schlüssel, sodass `tail -c 32` DER Schlüssel IST). Es emittiert BEIDE.
- `vdlu-sign` (PC): `openssl pkeyutl -sign -rawin` über den kanonischen sha256-Hex, Signatur base64 gespeichert.
- `vdlu-verify` (**Gerät, schlank**): `ed25519-mini <pubkey32> <msg> <sig64>` - liest das Keyring als den **RAW 32B**
  Pubkey, KEIN openssl auf dem Gerät. `key_id` ist pfad-bereinigt (kein `/`, `.`, `..`, `"`). 🚨 Das Keyring liefert den
  **`.pub.raw` (32B)** aus, niemals den `.pub` PEM (113B): der PEM ist nur PC-seitig und `ed25519-mini` kann ihn nicht lesen.

Trust-Modell (INTERFACES §6, doc §11/§13): `profile=hardened` (public) macht verify obligatorisch - eine
fehlgeschlagene oder fehlende Signatur bricht das Update ab. `profile=trusted` (privat, SSH-gestagete Quelle) behandelt
verify als best-effort, aber der sha256 jedes Blobs wird unabhängig davon geprüft.

## Keyring + Rotation

Das Keyring ist ein Verzeichnis von `<key_id>.pub`-Dateien, jede der **RAW 32B** ed25519-Pubkey (aus `keygen`s
`.pub.raw`), NICHT PEM - `ed25519-mini` liest rohe 32 Byte. Liefere den aktuellen **und** den vorherigen Raw-Pubkey aus
(doc §13), sodass ein rotierter Schlüssel ältere Installationen nicht brickt. `vdlu-sign` mit dem neuen `key_id` und das Gerät,
das `<keyring>/<key_id>.pub` (raw) wählt, ist der gesamte Rotationsmechanismus - keine Engine-Änderung. Das Keyring ist
**stabil** über Releases hinweg (nur Schlüsselrotation ändert es): ein Re-Vendor muss es **verifizieren-nicht-kopieren** und es niemals
mit dem PC-seitigen `.pub` PEM überschreiben.

**Keyrings mit mehreren Schlüsseln MÜSSEN den Modul-Schlüssel pinnen.** Die Engine beschränkt, welcher `key_id` ein MODULE-UPDATE signieren darf, auf die `key_id`-Allowlist der config (INTERFACES §5/§6), fail-closed geprüft, bevor die Pubkey ausgewählt wird. Ein Keyring mit einem Schlüssel ist standardsicher (dieser eine Schlüssel wird akzeptiert). Aber ein Modul, dessen Keyring AUCH einen Schlüssel geringeren Vertrauens trägt - z. B. einen Fingerprint-Feed-Schlüssel neben dem Release-Schlüssel - wird abgelehnt, bis seine `config` den Modul-Schlüssel deklariert, z. B. `key_id=vd-2026` (kommagetrennt für die Rotation, z. B. `key_id=vd-2026,vd-2027`). Das verhindert, dass ein geleakter Schlüssel geringeren Vertrauens ein flashless Root-Update signiert.

`vdlu-pack` **schließt das Keyring und die `verify/`-Binaries aus dem Feed aus** (die Trust-Root ist flash-only, wird nie über die Leitung ausgeliefert), neben `baseline.json`, dem Installer-Gerüst (`META-INF/`, `customize.sh`), dem `.vd/`-Flash-Gate, den CI-gefüllten `update.json`/`update-mmrl.json` und den per-Datei-`.sha256`-Begleitern. Nur der moduleigene Inhalt ist per Feed aktualisierbar, sodass ein Manifest niemals den On-Device-Trust-Anchor umschreiben kann.

<!-- doc-footer -->

---

> _Diese Dokumentation wurde mit Claude (Anthropic) erstellt und wird von VD171 gepflegt. Korrekturen und Verbesserungen sind willkommen, siehe [CONTRIBUTING.md](CONTRIBUTING.md)._
