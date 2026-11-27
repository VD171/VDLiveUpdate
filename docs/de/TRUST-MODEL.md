> **Languages:** [English](../TRUST-MODEL.md) · [العربية](../ar/TRUST-MODEL.md) · [Čeština](../cs/TRUST-MODEL.md) · Deutsch · [Español](../es/TRUST-MODEL.md) · [فارسی](../fa/TRUST-MODEL.md) · [Français](../fr/TRUST-MODEL.md) · [हिन्दी](../hi/TRUST-MODEL.md) · [Bahasa Indonesia](../id/TRUST-MODEL.md) · [Italiano](../it/TRUST-MODEL.md) · [日本語](../ja/TRUST-MODEL.md) · [한국어](../ko/TRUST-MODEL.md) · [Nederlands](../nl/TRUST-MODEL.md) · [Polski](../pl/TRUST-MODEL.md) · [Português](../pt/TRUST-MODEL.md) · [Русский](../ru/TRUST-MODEL.md) · [Svenska](../sv/TRUST-MODEL.md) · [ไทย](../th/TRUST-MODEL.md) · [Türkçe](../tr/TRUST-MODEL.md) · [Українська](../uk/TRUST-MODEL.md) · [Tiếng Việt](../vi/TRUST-MODEL.md) · [中文](../zh/TRUST-MODEL.md)

---

# Sicherheitsrichtlinie und Vertrauensmodell

VDLiveUpdate (VDLU) wendet **flashless Root-Updates** auf ein Live-Modul an: es schreibt
nach `/data/adb/modules/<mod>` und swapt beim Boot eine Zygisk-`.so`. Jedes Feld eines
geholten Manifests (`path`, `sha256`, `delete[]`, `mode`, ...) ist **feindliche Eingabe** -
ein vergifteter Feed oder ein MITM liefert es. Diese Seite ist das Vertrauensmodell und die
Richtlinie zur verantwortungsvollen Offenlegung. Den vollständigen Nahtvertrag siehe
[`INTERFACES.md`](INTERFACES.md), und die Engine-/Producer-Interna in [`ENGINE.md`](ENGINE.md)
und [`PRODUCER.md`](PRODUCER.md), die Wiki-Seite **Security-and-Trust-Model** trägt dasselbe
Modell für Leser außerhalb des Repos.

## Unterstützte Versionen

Sicherheitsfixes landen in der neuesten `ENGINE_VERSION`, ein signiertes Manifest deklariert
über `engine_min` die minimale Engine, die es braucht, und die On-Device-Engine lehnt ein
Manifest ab, das mehr verlangt, als sie implementiert. Von älteren vendorisierten Engines
wird erwartet, dass sie **neu vendorisiert** werden, um einen Fix zu übernehmen, nicht dass
sie an Ort und Stelle nachgepatcht werden.

| ENGINE_VERSION | Status |
|---|---|
| 7 (aktuell) | unterstützt - ein Modul, das dem Feed voraus ist, nie zurücksetzen (der live installierte `versionCode` bildet die Untergrenze der "from"-Version), Boot-Self-Heal eines veralteten Downgrade-Plans |
| 6 | abgelöst - Boot-Self-Heal eines veralteten Journals mit `target <= 0` (die Baseline 0 eines entfernten Stubs steuert keine UI- oder Boot-Aktion mehr) |
| 5 | abgelöst - engine-seitiger Trust-Anchor-Ausschluss (das `vdlu/`-Verzeichnis wird ignoriert, selbst wenn ein Feed es trägt), 128 MiB pro Datei / 2 MiB Manifest-Obergrenzen |
| 4 | abgelöst - `key_id`-Allowlist, Ablehnung von Dot-Segment-/Trailing-Slash-Pfaden, Größen-Caps, Lock zur Check-Zeit |
| <= 3 | nicht unterstützt - die aktuelle Engine neu vendorisieren |

Jede Änderung an der Engine-Verifizierungs- oder Apply-Logik bumpt `ENGINE_VERSION`.

## Eine Schwachstelle melden

Melde privat. Öffne **kein** öffentliches Issue, keinen PR und keinen Forenbeitrag für einen
Sicherheitsbug. Nutze die Projektkontakte (siehe [`CONTRIBUTING.md`](../CONTRIBUTING.md)):

- Telegram: **@VD_Priv8** (https://t.me/VD_Priv8)
- Kanal: **@Priv8_VD** (https://t.me/Priv8_VD)
- E-Mail: **vd.priv8@pm.me**

Bitte gib die Engine-Version, das verwendete `profile` und ein Manifest oder einen Feed an,
der das Problem reproduziert. Fixes werden als neue `ENGINE_VERSION` mit einem
`CHANGELOG.md`-Eintrag ausgeliefert, koordiniere den Zeitpunkt der Offenlegung im
Melde-Thread.

## Vertrauensmodell

- **Detached ed25519-Signaturen.** Der Producer signiert das kanonische Manifest auf dem PC
  (openssl), das Gerät verifiziert mit dem eingebetteten `ed25519-mini` - **kein openssl auf
  dem Gerät**. Die signierte Nachricht ist der sha256-Hex des Manifests ohne sein
  `sig`-Feld (Schlüssel sortiert, kompakt, UTF-8), sodass Signieren und Verifizieren auf zwei
  Laufzeitumgebungen dieselben Bytes ableiten, ohne JSON-Bibliothek auf dem Gerät.
- **Keyring = RAW 32-Byte-Pubkeys**, flash-only. Das Gerät-Keyring liefert `<key_id>.pub` als
  den rohen 32-Byte-Schlüssel aus (niemals den PEM), `vdlu-pack` **schließt** das Keyring und
  die `verify/`-Binaries aus dem Feed **aus**, sodass ein Manifest den On-Device-Trust-Anchor
  niemals über die Leitung umschreiben kann.
- **Engine-seitiger Trust-Anchor-Ausschluss (VDLU#2).** Unabhängig vom obigen
  producer-seitigen Ausschluss **ignoriert** die On-Device-Engine jeden `vdlu/`-Pfad
  (`update.sh`, `vdlu-verify`, `verify/*`, `keyring/*`, config) in einem geholten Plan - sie
  holt, wendet oder löscht sie nie, selbst wenn ein Feed sie trägt. Ein publizierter Feed
  liefert den gesamten Modulbaum aus, `vdlu/` inbegriffen, sodass die Engine diese Pfade
  stillschweigend verwirft, statt das Manifest abzulehnen: das Modul aktualisiert dennoch, und
  der Trust-Anchor ändert sich nur durch ein vollständiges signiertes Re-Flash. Ein einzelner
  geleakter Signierschlüssel kann den Verifier oder den Signierschlüssel nicht mehr über die
  Leitung tauschen und Root persistieren.
- **Module-Update-`key_id`-Allowlist (fail-closed, vor der Pubkey-Auswahl).** Ein Keyring kann
  legitim mehr als einen Schlüssel tragen (zum Beispiel einen Fingerprint-Feed-Schlüssel
  geringeren Vertrauens neben dem Release-Schlüssel). Bevor `<key_id>.pub` je ausgewählt wird,
  lehnt `verify_manifest` jedes Manifest ab, dessen `key_id` nicht in der konfigurierten
  Allowlist steht, in **beiden** Profilen, und spiegelt die aufgelöste Menge via
  `VDLU_KEYID_ALLOW` in `vdlu-verify`. Das schließt einen Bypass, bei dem ein geleakter
  Schlüssel geringeren Vertrauens sonst ein vollständiges flashless Root-Update signieren
  könnte. Standardsicher, wenn `key_id` nicht gesetzt ist: ein **Keyring mit einem Schlüssel**
  pinnt automatisch auf diesen einen Schlüssel, ein **Keyring mit mehreren Schlüsseln** wird
  abgelehnt, bis `key_id` gepinnt ist (kommagetrennt für die Rotation).
- **Die Fingerprint-Feed-Vertrauenswurzel ist ein separater, gepinnter Pfad** mit eigenem
  Schlüssel, sie ist über den obigen Module-Update-Pfad niemals erreichbar.
- **Die Baseline ist ein lokaler vertrauenswürdiger Seed.** `baseline.json` kommt im
  geflashten Zip an - der Installations-Vertrauensgrenze - also ist sie unsigniert und
  schlüssellos und wird **nicht** durch `vdlu-verify` geführt, nur ein vom Feed **geholtes**
  Manifest wird verifiziert. Das hält den Signierschlüssel aus der CI heraus.

## Fail-closed-Garantien

- **`validate_plan` läuft vor jedem Fetch oder Apply.** In `do_diff`, fail-closed, lehnt es
  das **gesamte** Manifest ab, wenn irgendein `path` absolut ist, ein `..`- oder `.`-Segment
  enthält, auf `/` endet oder ein Steuerzeichen enthält, wenn irgendein `sha256` nicht
  `^[0-9a-f]{64}$` ist, oder wenn irgendein `mode`/`class`/`enc` ungültig ist. Kein feindliches
  Feld erreicht eine Shell, und `cmd_check` trägt keine `system()`-Interpolation.
- **Pfad-Containment.** Jeder Schreib- und Löschvorgang ist via `contained()` auf `MODULE_DIR`
  beschränkt - apply, delete und das Reboot-`stage_file` passieren alle denselben Guard.
  Symlinks im Baum werden vom Producer übersprungen (leaken nie Inhalt von außerhalb).
- **Zwei Profile, fail-closed per Inversion.** `trusted` (privat, SSH-gestagete Quelle) ist das
  **einzige** Opt-in zu best-effort verify, **jeder** andere Wert - inklusive Tippfehler,
  abschließendem Leerzeichen/CR oder anderer Groß-/Kleinschreibung - wird als `hardened`
  behandelt, wo eine gültige Signatur **obligatorisch** ist und ein Fehler abbricht. Der
  `sha256` jedes Blobs wird in beiden Profilen geprüft.
- **Signatur + Hash vor jedem Tool-Exec.** Das geholte statische `curl` läuft als root, also
  verifiziert `install-tool` die tools-manifest-Signatur (ed25519-mini, obligatorisch in
  **jedem** Profil) und den Hash des curl **bevor** es installiert und ausgeführt wird -
  sig+hash vor exec schließt das RCE.
- **Wiederaufnehmbare, pin-sichere Transaktion.** Das im Flug befindliche Manifest ist in
  `target.json` gepinnt, ein Crash, Netzwerkverlust oder Reboot nimmt aus dem Journal wieder
  auf, ohne den Plan neu zu entscheiden. Downgrade ist blockiert (monotone `version`), das
  signierte `module`-Feld muss `MODID` gleichen, und `delete[]` läuft nur bei `finalize_done`
  (ein `PENDING_REBOOT` löscht nichts). Nichts ist je "erledigt" ohne ein vollständiges
  erneutes Hashen, nichts wird überschrieben ohne zuvor ein `rollback/<v>/`-Backup.

## Härtung (Defense in Depth)

- **Größen-Caps.** Das Manifest, das tools-manifest und der curl-lose `wget`/`head -c`-Download-
  Pfad sind alle gebunden, bevor sie gelesen werden (Anti-OOM / Anti-Flood). Ein Blob scheitert
  in seiner Phase nach 3 Versuchen. Die Obergrenzen sind **128 MiB pro Datei**
  (`MAX_FILE_BYTES`) und **2 MiB für das Manifest** (`MAX_MANIFEST_BYTES`), durchgesetzt in
  `update.sh` und in `vdlu-verify` gespiegelt.
- **Lock zur Check-Zeit.** `check` nimmt das mkdir-Lock, bevor es sein Work-Verzeichnis neu
  baut, sodass ein paralleler Run es nicht überholen kann.
- **Staging-Containment.** `stage_file` hat denselben `contained()`-Guard wie die
  Live-Apply-Primitiven, sodass ein gestageter Reboot-hard-Pfad ebenfalls nicht aus
  `MODULE_DIR` ausbrechen kann.
- **TLS ist Defense in Depth, nicht die Trust-Root.** Das statische curl nutzt mbedTLS mit dem
  Android-Trust-Store (`--capath`, `ca_path`-Override), die Integritätsgarantie ist die
  ed25519-Signatur, der Cert-Check ist eine zweite Schicht.

## Siehe auch

- [`INTERFACES.md`](INTERFACES.md) - der unveränderliche Nahtvertrag (§5 config, §6 Signatur, §11 Toolchain).
- [`ENGINE.md`](ENGINE.md) - die Device-seitige Engine und ihr Zustandsautomat.
- [`PRODUCER.md`](PRODUCER.md) - Packen, Signieren, Kanonisierung und Schlüsselrotation.
- Wiki: **Security-and-Trust-Model**.

<!-- doc-footer -->

---

> _Diese Dokumentation wurde mit Claude (Anthropic) erstellt und wird von VD171 gepflegt. Korrekturen und Verbesserungen sind willkommen, siehe [CONTRIBUTING.md](CONTRIBUTING.md)._
